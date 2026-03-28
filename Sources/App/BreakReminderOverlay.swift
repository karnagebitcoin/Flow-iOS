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
    @ObservedObject var coordinator: BreakReminderCoordinator

    var body: some View {
        Group {
            if let quote = coordinator.presentedQuote {
                BreakReminderOverlayPresentation(
                    quote: quote,
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
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(reminderBackgroundColor)

            UnicornStudioBackgroundView(
                source: .bundledJSON("aura.json"),
                backgroundStyle: reminderBackgroundStyle
            )
            .scaleEffect(2, anchor: .center)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

            Text("How about a short break?")
                .font(.title3.weight(.semibold))
                .foregroundStyle(reminderTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
                .shadow(color: reminderTextShadowColor, radius: 8, x: 0, y: 3)
        }
        .frame(maxWidth: 540, alignment: .center)
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(reminderBorderColor, lineWidth: 0.9)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(dismissButtonForegroundColor)
                    .frame(width: 34, height: 34)
                    .background(dismissButtonBackgroundColor, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss break reminder")
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.12), radius: 22, x: 0, y: 10)
        .accessibilityElement(children: .contain)
    }

    private var reminderBackgroundStyle: UnicornStudioBackgroundView.BackgroundStyle {
        .clear
    }

    private var reminderBackgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private var reminderBorderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.08)
    }

    private var dismissButtonForegroundColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.82)
            : Color.black.opacity(0.68)
    }

    private var dismissButtonBackgroundColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.26)
            : Color.white.opacity(0.76)
    }

    private var reminderTextColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.76)
            : Color.black.opacity(0.62)
    }

    private var reminderTextShadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.28)
            : Color.white.opacity(0.6)
    }
}
