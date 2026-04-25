import SwiftUI

struct SettingsTypographyView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettingsStore

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var typographyOptions: [AppFontOption] {
        AppFontOption.allCases.filter(\.isEnabled)
    }

    var body: some View {
        ThemedSettingsForm {
            ThemedSettingsSection("Typography") {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(typographyOptions) { option in
                        fontOptionCard(for: option)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowBackground(settingsSurfaceStyle.cardBackground)
        }
        .navigationTitle("Typography")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var settingsSurfaceStyle: SettingsFormSurfaceStyle {
        appSettings.settingsFormSurfaceStyle(for: colorScheme)
    }

    private func fontOptionCard(for option: AppFontOption) -> some View {
        let isSelected = appSettings.activeFontOption == option

        return Button {
            appSettings.fontOption = option
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(appSettings.themePalette.secondaryBackground)
                    .frame(height: 108)
                    .overlay(alignment: .bottomLeading) {
                        Text(option.previewWord)
                            .font(option.previewFont(size: 24, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(14)
                    }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(appSettings.primaryColor)
                        .padding(10)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? appSettings.primaryColor : appSettings.themeSeparator(defaultOpacity: 0.18),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
