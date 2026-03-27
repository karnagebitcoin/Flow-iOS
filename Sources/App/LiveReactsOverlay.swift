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
