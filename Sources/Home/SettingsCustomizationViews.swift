import SwiftUI

private struct HolographicGradientPreviewCard: View {
    let option: HolographicGradientOption
    let theme: AppThemeOption
    let foregroundColor: Color

    var body: some View {
        let border = option.borderColor(for: theme)
        let accents = option.accentPalette(for: theme)

        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(option.uiGradient)

            overlayEffect

            Capsule(style: .continuous)
                .fill(option.buttonGradient)
                .frame(width: 108, height: 36)
                .shadow(color: accents.shadow.opacity(0.22), radius: 12, x: 0, y: 8)
                .overlay {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("History")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(foregroundColor)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var overlayEffect: some View {
        switch option.previewEffect {
        case .none:
            EmptyView()
        case .sheen:
            LinearGradient(
                colors: [
                    Color.white.opacity(0.20),
                    Color.white.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .radialGlow:
            ZStack {
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.40),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 70
                )
                .offset(x: -12, y: -12)

                RadialGradient(
                    colors: [
                        Color(red: 0.388, green: 0.910, blue: 1.0).opacity(0.18),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 78
                )
                .offset(x: 18, y: -8)

                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.525, blue: 0.894).opacity(0.16),
                        Color.clear
                    ],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: 84
                )
                .offset(x: -10, y: 16)
            }
        }
    }
}

private struct GeneratedButtonGradientPreviewCard: View {
    let gradient: GeneratedButtonGradient
    let foregroundColor: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(gradient.gradient)

            Capsule(style: .continuous)
                .fill(.black.opacity(0.13))
                .frame(width: 116, height: 36)
                .overlay {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("Preview")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(foregroundColor)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SettingsButtonGradientView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettingsStore
    @State private var generatedGradient = GeneratedButtonGradient.random()

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ThemedSettingsForm {
            ThemedSettingsSection("Button Text") {
                ColorPicker(
                    "Text Color",
                    selection: Binding(
                        get: { appSettings.buttonTextColor },
                        set: { appSettings.buttonTextColor = $0 }
                    ),
                    supportsOpacity: false
                )
            }
            .listRowBackground(settingsSurfaceStyle.cardBackground)

            ThemedSettingsSection("Generate") {
                generatedGradientCard
            }
            .listRowBackground(settingsSurfaceStyle.cardBackground)

            ThemedSettingsSection("Button Gradient") {
                LazyVGrid(columns: columns, spacing: 10) {
                    noGradientCard

                    ForEach(HolographicGradientOption.allCases) { option in
                        gradientCard(option)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowBackground(settingsSurfaceStyle.cardBackground)
        }
        .navigationTitle("Button Style")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            generatedGradient = appSettings.generatedButtonGradient ?? generatedGradient
        }
    }

    private var settingsSurfaceStyle: SettingsFormSurfaceStyle {
        appSettings.settingsFormSurfaceStyle(for: colorScheme)
    }

    private var noGradientCard: some View {
        let isSelected = appSettings.buttonGradientOption == nil && appSettings.generatedButtonGradient == nil

        return Button {
            appSettings.clearButtonGradient()
            appSettings.buttonTextColor = .white
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(appSettings.themePalette.secondaryBackground)
                        .frame(height: 86)
                        .overlay {
                            Capsule(style: .continuous)
                                .fill(appSettings.primaryColor)
                                .frame(width: 108, height: 36)
                                .overlay {
                                    Text("Color")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(appSettings.buttonTextColor)
                                }
                        }

                    if isSelected {
                        selectedBadge
                    }
                }

                Text("Solid Color")
                    .font(appSettings.appFont(.caption1, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay { cardBorder(isSelected: isSelected) }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func gradientCard(_ option: HolographicGradientOption) -> some View {
        let isSelected = appSettings.buttonGradientOption == option && appSettings.generatedButtonGradient == nil

        return Button {
            appSettings.buttonGradientOption = option
            appSettings.buttonTextColor = .black
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    HolographicGradientPreviewCard(
                        option: option,
                        theme: appSettings.activeTheme,
                        foregroundColor: appSettings.buttonTextColor
                    )
                        .frame(height: 86)

                    if isSelected {
                        selectedBadge
                    }
                }

                Text(option.title)
                    .font(appSettings.appFont(.caption1, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay { cardBorder(isSelected: isSelected) }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var generatedGradientCard: some View {
        let isSelected = appSettings.generatedButtonGradient == generatedGradient

        return VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                GeneratedButtonGradientPreviewCard(
                    gradient: generatedGradient,
                    foregroundColor: appSettings.buttonTextColor
                )
                .frame(height: 96)

                if isSelected {
                    selectedBadge
                }
            }

            HStack(spacing: 10) {
                Button {
                    generatedGradient = GeneratedButtonGradient.random()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(appSettings.appFont(.footnote, weight: .semibold))
                        .foregroundStyle(appSettings.primaryColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(appSettings.themePalette.secondaryBackground, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    appSettings.applyGeneratedButtonGradient(generatedGradient)
                } label: {
                    Text("Apply")
                        .font(appSettings.appFont(.footnote, weight: .semibold))
                        .foregroundStyle(appSettings.buttonTextColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(generatedGradient.gradient, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay { cardBorder(isSelected: isSelected) }
    }

    private var selectedBadge: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(appSettings.primaryColor)
            .padding(8)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(appSettings.themePalette.secondaryBackground)
    }

    private func cardBorder(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(
                isSelected ? appSettings.primaryColor : appSettings.themeSeparator(defaultOpacity: 0.18),
                lineWidth: isSelected ? 1.5 : 1
            )
    }
}

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
