import SwiftUI

struct AppThemeBackgroundView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    var body: some View {
        let palette = appSettings.themePalette

        ZStack {
            palette.background

            if appSettings.activeTheme == .sakura {
                LinearGradient(
                    colors: [
                        Color(red: 0.976, green: 0.659, blue: 1.0).opacity(0.30),
                        Color(red: 1.0, green: 0.404, blue: 0.941).opacity(0.20),
                        palette.background.opacity(0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        Color(red: 0.976, green: 0.659, blue: 1.0).opacity(0.22),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 12,
                    endRadius: 320
                )
                .offset(x: -24, y: -40)
            }
        }
    }
}
