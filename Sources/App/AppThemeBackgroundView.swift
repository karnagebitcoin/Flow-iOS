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
                        AppThemePalette.dracula.background.opacity(0.98),
                        Color(red: 0.129, green: 0.133, blue: 0.173).opacity(0.96),
                        Color(red: 0.098, green: 0.102, blue: 0.129).opacity(0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        Color(red: 0.741, green: 0.576, blue: 0.976).opacity(0.16),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 12,
                    endRadius: 320
                )
                .offset(x: -24, y: -54)

                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.475, blue: 0.776).opacity(0.12),
                        Color.clear
                    ],
                    center: .bottomTrailing,
                    startRadius: 18,
                    endRadius: 360
                )
                .offset(x: 36, y: 52)

                RadialGradient(
                    colors: [
                        Color(red: 0.545, green: 0.914, blue: 0.992).opacity(0.10),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 16,
                    endRadius: 280
                )
                .offset(x: 24, y: -40)
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
            }
        }
    }
}
