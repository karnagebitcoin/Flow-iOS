import SwiftUI

struct AppThemeBackgroundView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    var body: some View {
        let palette = appSettings.themePalette

        ZStack {
            palette.background

            if appSettings.activeTheme == .dracula {
                LinearGradient(
                    colors: [
                        AppThemePalette.dracula.background,
                        Color(red: 30.0 / 255.0, green: 30.0 / 255.0, blue: 40.0 / 255.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else if appSettings.activeTheme == .sakura {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.98),
                        Color(red: 1.0, green: 0.973, blue: 0.987).opacity(0.94),
                        Color(red: 0.989, green: 0.941, blue: 0.970).opacity(0.88)
                    ],
                    startPoint: .top,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        Color(red: 0.984, green: 0.855, blue: 0.928).opacity(0.14),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 340
                )
                .offset(x: -18, y: -36)

                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.940, blue: 0.972).opacity(0.10),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 18,
                    endRadius: 300
                )
                .offset(x: 16, y: -26)
            } else if appSettings.activeTheme == .gamer {
                LinearGradient(
                    colors: [
                        AppThemePalette.gamer.background.opacity(0.99),
                        AppThemePalette.gamer.chromeBackground.opacity(0.98),
                        Color(red: 0.024, green: 0.043, blue: 0.075).opacity(0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        Color(red: 0.553, green: 0.408, blue: 1.0).opacity(0.08),
                        Color.clear
                    ],
                    center: .bottomTrailing,
                    startRadius: 22,
                    endRadius: 360
                )
                .offset(x: 30, y: 54)
            }
        }
    }
}
