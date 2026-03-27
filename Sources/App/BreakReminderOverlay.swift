import SwiftUI

struct BreakReminderQuote: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
    let author: String

    static func next(excluding excludedID: String?) -> BreakReminderQuote {
        let availableQuotes = all.filter { $0.id != excludedID }
        return availableQuotes.randomElement() ?? all[0]
    }

    private static let all: [BreakReminderQuote] = [
        BreakReminderQuote(
            id: "gandhi_speed",
            text: "There is more to life than increasing its speed.",
            author: "Mahatma Gandhi"
        ),
        BreakReminderQuote(
            id: "tolstoy_time_patience",
            text: "The strongest of all warriors are these two - Time and Patience.",
            author: "Leo Tolstoy"
        ),
        BreakReminderQuote(
            id: "pericles_counselor",
            text: "Time is the wisest counselor of all.",
            author: "Pericles"
        ),
        BreakReminderQuote(
            id: "curtin_not_wasted",
            text: "Time you enjoy wasting is not wasted time.",
            author: "Marthe Troly-Curtin"
        ),
        BreakReminderQuote(
            id: "emerson_patience",
            text: "Adopt the pace of nature: her secret is patience.",
            author: "Ralph Waldo Emerson"
        )
    ]
}

@MainActor
final class BreakReminderCoordinator: ObservableObject {
    @Published private(set) var presentedQuote: BreakReminderQuote?

    private var timerTask: Task<Void, Never>?
    private var scenePhase: ScenePhase = .inactive
    private var interval: BreakReminderInterval = .off
    private var isEnabled = false
    private var lastQuoteID: String?

    private static let presentationAnimation = Animation.spring(response: 0.42, dampingFraction: 0.88)

    deinit {
        timerTask?.cancel()
    }

    func update(
        isEnabled: Bool,
        interval: BreakReminderInterval,
        scenePhase: ScenePhase
    ) {
        let configurationChanged =
            self.isEnabled != isEnabled ||
            self.interval != interval ||
            self.scenePhase != scenePhase

        self.isEnabled = isEnabled
        self.interval = interval
        self.scenePhase = scenePhase

        guard configurationChanged else { return }

        guard isEnabled, scenePhase == .active, interval.duration != nil else {
            cancelTimer(resetPresentation: true)
            return
        }

        guard presentedQuote == nil else { return }
        restartTimer()
    }

    func dismissReminder() {
        withAnimation(Self.presentationAnimation) {
            presentedQuote = nil
        }
        restartTimer()
    }

    func presentPreviewReminder() {
        timerTask?.cancel()
        timerTask = nil

        let quote = BreakReminderQuote.next(excluding: lastQuoteID)
        lastQuoteID = quote.id

        withAnimation(Self.presentationAnimation) {
            presentedQuote = quote
        }
    }

    private func restartTimer() {
        timerTask?.cancel()
        timerTask = nil

        guard isEnabled,
              scenePhase == .active,
              presentedQuote == nil,
              let duration = interval.duration else {
            return
        }

        timerTask = Task { [weak self] in
            let nanoseconds = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                guard self.isEnabled,
                      self.scenePhase == .active,
                      self.presentedQuote == nil,
                      self.interval.duration != nil else {
                    return
                }

                let quote = BreakReminderQuote.next(excluding: self.lastQuoteID)
                self.lastQuoteID = quote.id
                self.timerTask = nil

                withAnimation(Self.presentationAnimation) {
                    self.presentedQuote = quote
                }
            }
        }
    }

    private func cancelTimer(resetPresentation: Bool) {
        timerTask?.cancel()
        timerTask = nil

        guard resetPresentation, presentedQuote != nil else { return }

        withAnimation(Self.presentationAnimation) {
            presentedQuote = nil
        }
    }
}

struct BreakReminderOverlayHost: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    @ObservedObject var coordinator: BreakReminderCoordinator

    var body: some View {
        Group {
            if let quote = coordinator.presentedQuote {
                BreakReminderOverlayPresentation(
                    quote: quote,
                    accentColor: appSettings.primaryColor,
                    onDismiss: { coordinator.dismissReminder() }
                )
            } else {
                Color.clear
                    .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(coordinator.presentedQuote != nil)
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: coordinator.presentedQuote?.id)
    }
}

struct BreakReminderOverlayPresentation: View {
    @Environment(\.colorScheme) private var colorScheme

    let quote: BreakReminderQuote
    let accentColor: Color
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black
                    .opacity(colorScheme == .dark ? 0.28 : 0.14)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .transition(.opacity)

                BreakReminderSheet(
                    quote: quote,
                    accentColor: accentColor,
                    onDismiss: onDismiss
                )
                .padding(.horizontal, 12)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct BreakReminderSheet: View {
    @Environment(\.colorScheme) private var colorScheme

    let quote: BreakReminderQuote
    let accentColor: Color
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Capsule(style: .continuous)
                .fill(accentColor.opacity(colorScheme == .dark ? 0.32 : 0.2))
                .frame(width: 46, height: 5)

            VStack(spacing: 8) {
                Text("Want to take a quick break?")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)

            placeholderArtworkCard

            VStack(spacing: 12) {
                Image(systemName: "quote.opening")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(accentColor)

                Text(quote.text)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)

                Text(quote.author)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(accentColor.opacity(colorScheme == .dark ? 0.12 : 0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(accentColor.opacity(colorScheme == .dark ? 0.28 : 0.16), lineWidth: 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(maxWidth: 540, alignment: .center)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.regularMaterial)

                LinearGradient(
                    colors: [
                        accentColor.opacity(colorScheme == .dark ? 0.14 : 0.08),
                        Color.clear,
                        Color.black.opacity(colorScheme == .dark ? 0.12 : 0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(accentColor.opacity(colorScheme == .dark ? 0.24 : 0.14), lineWidth: 0.9)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color(.secondarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss break reminder")
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.12), radius: 22, x: 0, y: 10)
        .accessibilityElement(children: .contain)
    }

    private var placeholderArtworkCard: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(accentColor.opacity(colorScheme == .dark ? 0.12 : 0.08))
            .frame(height: 132)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.square.badge.questionmark")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(accentColor)

                    Text("Author artwork placeholder")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        accentColor.opacity(colorScheme == .dark ? 0.24 : 0.14),
                        style: StrokeStyle(lineWidth: 1, dash: [7, 6])
                    )
            }
    }
}
