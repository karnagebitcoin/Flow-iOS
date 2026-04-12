import SwiftUI

@MainActor
final class LiveReactsCoordinator: ObservableObject {
    @Published private(set) var emissions: [LiveReactionEmission] = []

    func emit(_ reaction: ActivityReaction) {
        let emission = LiveReactionEmission(
            reaction: reaction,
            horizontalDrift: CGFloat.random(in: -26...24),
            travelHeight: CGFloat.random(in: 124...198),
            sway: CGFloat.random(in: -18...18),
            rotation: Double.random(in: -20...20),
            startScale: CGFloat.random(in: 0.84...0.98),
            endScale: CGFloat.random(in: 1.14...1.46),
            size: CGFloat.random(in: 34...46),
            duration: Double.random(in: 1.2...1.8),
            opacity: Double.random(in: 0.74...0.98)
        )
        emissions.append(emission)
        AppHaptics.liveReactionTick()

        Task { [weak self] in
            let lifetime = UInt64((emission.duration + 0.25) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: lifetime)
            await MainActor.run {
                self?.emissions.removeAll { $0.id == emission.id }
            }
        }
    }

    func emitPreviewSequence() {
        let previewReactions: [ActivityReaction] = [
            ActivityReaction(content: "+", shortcode: nil, customEmojiImageURL: nil),
            ActivityReaction(content: "🔥", shortcode: nil, customEmojiImageURL: nil),
            ActivityReaction(content: "😂", shortcode: nil, customEmojiImageURL: nil),
            ActivityReaction(content: "😍", shortcode: nil, customEmojiImageURL: nil),
            ActivityReaction(content: "👏", shortcode: nil, customEmojiImageURL: nil)
        ]

        for (index, reaction) in previewReactions.enumerated() {
            Task { [weak self] in
                let delay = UInt64(index) * 220_000_000
                try? await Task.sleep(nanoseconds: delay)
                await MainActor.run {
                    self?.emit(reaction)
                }
            }
        }
    }
}

@MainActor
final class LiveReactsSubscriptionController: ObservableObject {
    private let liveSubscriber: NostrLiveFeedSubscriber
    private var liveUpdatesTask: Task<Void, Never>?
    private var subscriptionSignature: String?
    private var currentUserPubkey: String?
    private var readRelayURLs: [URL] = []
    private var isEnabled = false
    private var scenePhase: ScenePhase = .inactive
    private var onReaction: ((ActivityReaction) -> Void)?
    private var seenEventIDs = Set<String>()
    private var seenEventOrder: [String] = []

    private let maxTrackedEventIDs = 512

    init(liveSubscriber: NostrLiveFeedSubscriber = NostrLiveFeedSubscriber()) {
        self.liveSubscriber = liveSubscriber
    }

    deinit {
        liveUpdatesTask?.cancel()
    }

    func update(
        currentUserPubkey: String?,
        readRelayURLs: [URL],
        isEnabled: Bool,
        scenePhase: ScenePhase,
        onReaction: ((ActivityReaction) -> Void)? = nil
    ) {
        let normalizedUser = normalizePubkey(currentUserPubkey)
        let normalizedRelays = normalizedRelayURLs(readRelayURLs)
        let userChanged = normalizedUser != self.currentUserPubkey

        self.currentUserPubkey = normalizedUser
        self.readRelayURLs = normalizedRelays
        self.isEnabled = isEnabled
        self.scenePhase = scenePhase

        if let onReaction {
            self.onReaction = onReaction
        }

        if userChanged {
            resetSeenEventTracking()
        }

        refreshSubscription(forceRestart: userChanged)
    }

    private func refreshSubscription(forceRestart: Bool = false) {
        guard isEnabled,
              scenePhase == .active,
              let user = currentUserPubkey,
              !user.isEmpty,
              !readRelayURLs.isEmpty else {
            stopSubscription(resetSeenEvents: !isEnabled || currentUserPubkey == nil)
            return
        }

        let liveSince = max(Int(Date().timeIntervalSince1970) - 2, 0)
        let filter = NostrFilter(
            kinds: [7],
            limit: 100,
            since: liveSince,
            tagFilters: ["p": [user]]
        )
        let signature = readRelayURLs
            .map { $0.absoluteString.lowercased() }
            .sorted()
            .joined(separator: "|") + "|\(user)|\(scenePhase == .active)"
        let relays = readRelayURLs

        if !forceRestart,
           liveUpdatesTask != nil,
           subscriptionSignature == signature {
            return
        }

        stopSubscription(resetSeenEvents: false)
        subscriptionSignature = signature

        liveUpdatesTask = Task { [weak self] in
            guard let self else { return }

            await withTaskGroup(of: Void.self) { group in
                for relayURL in relays {
                    group.addTask { [weak self] in
                        guard let self else { return }
                        await self.liveSubscriber.run(
                            relayURL: relayURL,
                            filter: filter,
                            onNewEvent: { [weak self] event in
                                guard let self else { return }
                                await self.handleIncomingReactionEvent(event)
                            }
                        )
                    }
                }
                await group.waitForAll()
            }
        }
    }

    private func stopSubscription(resetSeenEvents: Bool) {
        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil
        subscriptionSignature = nil

        if resetSeenEvents {
            resetSeenEventTracking()
        }
    }

    private func handleIncomingReactionEvent(_ event: NostrEvent) async {
        guard event.kind == 7 else { return }
        guard let user = currentUserPubkey, !user.isEmpty else { return }
        guard event.mentionedPubkeys.contains(where: { $0.lowercased() == user }) else { return }
        guard normalizePubkey(event.pubkey) != user else { return }

        let normalizedEventID = event.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEventID.isEmpty else { return }
        guard registerSeenEventID(normalizedEventID) else { return }

        guard let reaction = event.activityAction?.reaction else { return }
        onReaction?(reaction)
    }

    private func registerSeenEventID(_ eventID: String) -> Bool {
        guard seenEventIDs.insert(eventID).inserted else { return false }

        seenEventOrder.append(eventID)
        if seenEventOrder.count > maxTrackedEventIDs,
           let removedEventID = seenEventOrder.first {
            seenEventOrder.removeFirst()
            seenEventIDs.remove(removedEventID)
        }
        return true
    }

    private func resetSeenEventTracking() {
        seenEventIDs = []
        seenEventOrder = []
    }

    private func normalizePubkey(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizedRelayURLs(_ relayURLs: [URL]) -> [URL] {
        var seen = Set<String>()
        var ordered: [URL] = []

        for relayURL in relayURLs {
            let normalized = relayURL.absoluteString.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            ordered.append(relayURL)
        }

        return ordered
    }
}

struct LiveReactionEmission: Identifiable, Equatable {
    let id = UUID()
    let reaction: ActivityReaction
    let horizontalDrift: CGFloat
    let travelHeight: CGFloat
    let sway: CGFloat
    let rotation: Double
    let startScale: CGFloat
    let endScale: CGFloat
    let size: CGFloat
    let duration: Double
    let opacity: Double
}

struct LiveReactsOverlayHost: View {
    @ObservedObject var coordinator: LiveReactsCoordinator

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(coordinator.emissions) { emission in
                LiveReactionParticleView(emission: emission)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LiveReactionParticleView: View {
    let emission: LiveReactionEmission

    @State private var isAnimating = false

    var body: some View {
        particle
            .opacity(isAnimating ? 0 : emission.opacity)
            .scaleEffect(isAnimating ? emission.endScale : emission.startScale)
            .offset(
                x: isAnimating ? emission.horizontalDrift : 0,
                y: isAnimating ? -emission.travelHeight : 0
            )
            .rotationEffect(.degrees(isAnimating ? emission.rotation : emission.rotation * 0.18))
            .modifier(LiveReactionSwayModifier(isAnimating: isAnimating, sway: emission.sway))
            .blur(radius: isAnimating ? 0.6 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: emission.duration)) {
                    isAnimating = true
                }
            }
    }

    @ViewBuilder
    private var particle: some View {
        if let customEmojiURL = emission.reaction.customEmojiImageURL {
            CachedAsyncImage(url: customEmojiURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                default:
                    fallbackParticle
                }
            }
            .frame(width: emission.size, height: emission.size)
            .shadow(color: Color.black.opacity(0.16), radius: 6, x: 0, y: 4)
        } else {
            fallbackParticle
        }
    }

    @ViewBuilder
    private var fallbackParticle: some View {
        let value = emission.reaction.displayValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value == "+" {
            Image(systemName: "heart.fill")
                .font(.system(size: emission.size * 0.78, weight: .semibold))
                .foregroundStyle(.pink)
                .frame(width: emission.size, height: emission.size)
                .background(Color.pink.opacity(0.14), in: Circle())
                .shadow(color: Color.black.opacity(0.14), radius: 6, x: 0, y: 4)
        } else {
            Text(value)
                .font(.system(size: emission.size * 0.92))
                .frame(width: emission.size * 1.1, height: emission.size * 1.1)
                .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 4)
        }
    }
}

private struct LiveReactionSwayModifier: ViewModifier {
    let isAnimating: Bool
    let sway: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(x: isAnimating ? sway : 0)
    }
}
