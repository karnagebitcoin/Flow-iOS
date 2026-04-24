import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var breakReminderCoordinator: BreakReminderCoordinator
    @EnvironmentObject private var relaySettings: RelaySettingsStore

    @ObservedObject var sheetState: SettingsSheetState

    var body: some View {
        ZStack {
            appSettings.themePalette.sheetBackground
                .ignoresSafeArea()

            NavigationStack(path: navigationPathBinding) {
                VStack(spacing: 0) {
                    ThemedSettingsTitleHeader("Settings") {
                        ThemedToolbarDoneButton {
                            dismiss()
                        }
                    }

                    ThemedSettingsForm {
                        ThemedSettingsSection {
                            SettingsValueNavigationRow(
                                title: "General",
                                systemImage: "slider.horizontal.3",
                                value: .general
                            )

                            SettingsValueNavigationRow(
                                title: "Appearance",
                                systemImage: "paintbrush",
                                value: .appearance
                            )

                            SettingsValueNavigationRow(
                                title: "Feeds",
                                systemImage: "newspaper",
                                value: .feeds
                            )

                            SettingsValueNavigationRow(
                                title: "Notifications",
                                systemImage: "bell.badge",
                                value: .notifications
                            )

                            SettingsValueNavigationRow(
                                title: "Media",
                                systemImage: "photo.on.rectangle.angled",
                                value: .media
                            )

                            SettingsValueNavigationRow(
                                title: "Muted Content",
                                systemImage: "speaker.slash",
                                value: .mutedContent
                            )

                            SettingsValueNavigationRow(
                                title: "Keys",
                                systemImage: "key",
                                value: .keys
                            )

                            SettingsValueNavigationRow(
                                title: "Connection",
                                subtitle: connectionSummaryText,
                                systemImage: "dot.radiowaves.left.and.right",
                                value: .connection
                            )
                        }
                    }
                    .padding(.top, -4)
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(sheetState.navigationPath.isEmpty ? .hidden : .visible, for: .navigationBar)
                .navigationDestination(for: SettingsDestination.self) { destination in
                    settingsDestinationView(for: destination)
                }
                .overlay {
                    BreakReminderOverlayHost(coordinator: breakReminderCoordinator)
                }
                .task {
                    await appSettings.refreshNotificationAuthorizationStatus()
                }
                .sheet(isPresented: isShowingPrimaryColorPickerBinding) {
                    SettingsNativeColorPicker(
                        title: "Primary Color",
                        color: Binding(
                            get: { appSettings.primaryColor },
                            set: { appSettings.primaryColor = $0 }
                        ),
                        onDismiss: {
                            sheetState.isShowingPrimaryColorPicker = false
                        }
                    )
                    .preferredColorScheme(appSettings.preferredColorScheme)
                }
            }
        }
        .presentationBackground(appSettings.themePalette.sheetBackground)
        .preferredColorScheme(appSettings.preferredColorScheme)
    }

    private var connectionSummaryText: String {
        let count = Set(relaySettings.readRelays + relaySettings.writeRelays).count
        return "Connected to \(count) \(count == 1 ? "source" : "sources")"
    }

    private var navigationPathBinding: Binding<[SettingsDestination]> {
        Binding(
            get: { sheetState.navigationPath },
            set: { sheetState.navigationPath = $0 }
        )
    }

    private var isShowingPrimaryColorPickerBinding: Binding<Bool> {
        Binding(
            get: { sheetState.isShowingPrimaryColorPicker },
            set: { sheetState.isShowingPrimaryColorPicker = $0 }
        )
    }

    @ViewBuilder
    private func settingsDestinationView(for destination: SettingsDestination) -> some View {
        switch destination {
        case .general:
            SettingsGeneralView()
        case .appearance:
            SettingsAppearanceView(
                onOpenPrimaryColorPicker: {
                    sheetState.isShowingPrimaryColorPicker = true
                }
            )
        case .feeds:
            SettingsFeedsView()
        case .notifications:
            SettingsNotificationsView()
        case .media:
            SettingsMediaView()
        case .mutedContent:
            SettingsMutedContentView()
        case .keys:
            KeysView()
        case .connection:
            RelaySettingsView()
        }
    }
}

@MainActor
final class SettingsSheetState: ObservableObject {
    @Published var navigationPath: [SettingsDestination] = []
    @Published var isShowingPrimaryColorPicker = false

    func reset() {
        navigationPath.removeAll()
        isShowingPrimaryColorPicker = false
    }
}

enum SettingsDestination: Hashable {
    case general
    case appearance
    case feeds
    case notifications
    case media
    case mutedContent
    case keys
    case connection
}
