import SwiftUI

struct DMsView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Halo Link coming soon")
                    .font(appSettings.appFont(.headline, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("This tab is a placeholder while Halo Link is being built.")
                    .font(appSettings.appFont(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appSettings.themePalette.background)
            .navigationTitle("Halo Link")
        }
    }
}
