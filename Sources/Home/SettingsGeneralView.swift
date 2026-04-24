import SwiftUI

struct SettingsGeneralView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    @State private var previewQuote: BreakReminderQuote?
    @State private var lastPreviewQuoteID: String?
    @StateObject private var liveReactsPreviewCoordinator = LiveReactsCoordinator()

    var body: some View {
        ThemedSettingsForm {
            Section {
                LabeledContent("Break Reminder") {
                    Picker("Break Reminder", selection: breakReminderIntervalBinding) {
                        ForEach(BreakReminderInterval.allCases) { interval in
                            Text(interval.title).tag(interval)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Button {
                    presentPreviewReminder()
                } label: {
                    Label("Preview Break Reminder", systemImage: "hourglass.bottomhalf.filled")
                }

                SettingsToggleRow(
                    title: "Reaction Fountain",
                    isOn: Binding(
                        get: { appSettings.liveReactsEnabled },
                        set: { appSettings.liveReactsEnabled = $0 }
                    ),
                    footer: "Animate incoming reactions from the Pulse tab area in real time while Halo is open."
                )

                Button {
                    liveReactsPreviewCoordinator.emitPreviewSequence()
                } label: {
                    Label("Simulate Reaction Fountain", systemImage: "sparkles")
                }

                SettingsToggleRow(
                    title: "Floating Compose Button",
                    isOn: Binding(
                        get: { appSettings.floatingComposeButtonEnabled },
                        set: { appSettings.floatingComposeButtonEnabled = $0 }
                    ),
                    footer: "Show compose in the corner."
                )

                SettingsToggleRow(
                    title: "Hide NSFW Content",
                    isOn: Binding(
                        get: { appSettings.hideNSFWContent },
                        set: { appSettings.hideNSFWContent = $0 }
                    ),
                    footer: "Automatically hide notes tagged as NSFW."
                )

                SettingsToggleRow(
                    title: "Text Only Mode",
                    isOn: Binding(
                        get: { appSettings.textOnlyMode },
                        set: { appSettings.textOnlyMode = $0 }
                    ),
                    footer: "Strip media from notes and profiles to reduce bandwidth usage. Images and videos are replaced with placeholders."
                )

                SettingsToggleRow(
                    title: "Slow Connection Mode",
                    isOn: Binding(
                        get: { appSettings.slowConnectionMode },
                        set: { appSettings.slowConnectionMode = $0 }
                    ),
                    footer: "Connect only to relay.damus.io and hide reactions to reduce relay load."
                )
            } header: {
                Text("General")
            } footer: {
                Text("When enabled, Halo shows a gentle break reminder after the app has stayed open continuously for this long. Leaving the app or closing the reminder resets the timer. Use Preview to test the sheet right away.")
            }
        }
        .navigationTitle("General")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if let previewQuote {
                BreakReminderOverlayPresentation(
                    quote: previewQuote,
                    onDismiss: dismissPreviewReminder
                )
            }
        }
        .overlay(alignment: .bottomTrailing) {
            GeometryReader { proxy in
                let previewWidth = max(84, min(proxy.size.width * 0.26, 118))

                LiveReactsOverlayHost(coordinator: liveReactsPreviewCoordinator)
                    .frame(width: previewWidth, height: 250, alignment: .bottom)
                    .offset(x: -18, y: -18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .allowsHitTesting(false)
        }
    }

    private var breakReminderIntervalBinding: Binding<BreakReminderInterval> {
        Binding(
            get: { appSettings.breakReminderInterval },
            set: { appSettings.breakReminderInterval = $0 }
        )
    }

    private func presentPreviewReminder() {
        let quote = BreakReminderQuote.next(excluding: lastPreviewQuoteID)
        lastPreviewQuoteID = quote.id

        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            previewQuote = quote
        }
    }

    private func dismissPreviewReminder() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            previewQuote = nil
        }
    }
}
