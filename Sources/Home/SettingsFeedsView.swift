import SwiftUI

struct SettingsFeedsView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    var body: some View {
        ThemedSettingsForm {
            Section("Visible Feed Tabs") {
                SettingsToggleRow(
                    title: "Show Polls Feed",
                    isOn: Binding(
                        get: { appSettings.pollsFeedVisible },
                        set: { appSettings.pollsFeedVisible = $0 }
                    ),
                    footer: "Keep a dedicated Polls feed in the home feed picker for polls from people you follow."
                )
            }

            Section {
                SettingsNavigationRow(title: "Interests", systemImage: "sparkles") {
                    SettingsInterestsFeedView()
                }

                SettingsNavigationRow(title: "News", systemImage: "newspaper.fill") {
                    SettingsNewsFeedView()
                }

                SettingsNavigationRow(title: "Custom Feeds", systemImage: "square.stack.3d.up.fill") {
                    SettingsCustomFeedsView()
                }
            } footer: {
                Text("Choose what powers each feed. Interests uses hashtags from onboarding, News can combine relays, curated people, and hashtags, and Custom Feeds let you mix your own people, phrases, and topics.")
            }
        }
        .navigationTitle("Feeds")
        .navigationBarTitleDisplayMode(.inline)
    }
}
