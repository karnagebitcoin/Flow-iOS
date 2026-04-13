import SwiftUI

struct SettingsFlowPlusView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var premiumStore: FlowPremiumStore
    @State private var isPurchasingFlowPlus = false

    var body: some View {
        ZStack {
            AppThemeBackgroundView()
                .ignoresSafeArea()

            ThemedSettingsForm {
                ThemedSettingsSection {
                    membershipCard
                }
                .listRowBackground(settingsSurfaceStyle.cardBackground)

                if let error = premiumStore.lastErrorMessage, !error.isEmpty {
                    ThemedSettingsSection {
                        Text(error)
                            .font(appSettings.appFont(.footnote))
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(settingsSurfaceStyle.cardBackground)
                }
            }
        }
        .navigationTitle("Halo Plus")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await premiumStore.refreshProducts()
            await premiumStore.refreshEntitlements()
        }
    }

    private var unlockButtonTitle: String {
        premiumStore.flowPlusPurchaseButtonTitle
    }

    private var hasFlowPlusCustomizationAccess: Bool {
        appSettings.hasFlowPlusCustomizationAccess
    }

    private var settingsSurfaceStyle: SettingsFormSurfaceStyle {
        appSettings.settingsFormSurfaceStyle(for: colorScheme)
    }

    private var isTemporaryTestingUnlockActive: Bool {
        hasFlowPlusCustomizationAccess && !premiumStore.isFlowPlusActive
    }

    private var monthlyPriceText: String {
        premiumStore.flowPlusMonthlyPriceText
    }

    private var membershipDetailText: String {
        if premiumStore.isFlowPlusActive {
            return "Themes and typography are unlocked."
        }
        if isTemporaryTestingUnlockActive {
            return "Premium themes and fonts are temporarily unlocked for this session."
        }
        return "Try it free for 7 days, then \(monthlyPriceText)/month."
    }

    private var membershipCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text("Halo Plus")
                    .font(appSettings.appFont(.title3, weight: .semibold))

                Spacer(minLength: 12)

                membershipStatusBadge
            }

            if premiumStore.isFlowPlusActive {
                Link(destination: manageSubscriptionsURL) {
                    primaryMembershipButtonLabel("Manage Subscription")
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 10) {
                    Button {
                        guard !isPurchasingFlowPlus else { return }
                        Task { @MainActor in
                            isPurchasingFlowPlus = true
                            _ = await premiumStore.purchaseFlowPlus()
                            isPurchasingFlowPlus = false
                        }
                    } label: {
                        primaryMembershipButtonLabel {
                            if isPurchasingFlowPlus {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            } else {
                                Text(unlockButtonTitle)
                                    .font(appSettings.appFont(.subheadline, weight: .semibold))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasingFlowPlus)

                    temporaryTestingUnlockButton
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                membershipBenefitRow(
                    systemImage: "heart.circle.fill",
                    text: "Help support Halo open source development."
                )
                membershipBenefitRow(
                    systemImage: "sparkles",
                    text: "Unlock new themes, fonts and other fun bonuses."
                )
            }

            Text(membershipDetailText)
                .font(appSettings.appFont(.footnote))
                .foregroundStyle(appSettings.themePalette.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var membershipStatusBadge: some View {
        if premiumStore.isFlowPlusActive {
            Label("Active", systemImage: "checkmark.seal.fill")
                .font(appSettings.appFont(.caption1, weight: .semibold))
                .foregroundStyle(.green)
        } else if isTemporaryTestingUnlockActive {
            Label("Testing Unlock", systemImage: "testtube.2")
                .font(appSettings.appFont(.caption1, weight: .semibold))
                .foregroundStyle(appSettings.primaryColor)
        } else {
            Label("7-Day Free Trial", systemImage: "gift.fill")
                .font(appSettings.appFont(.caption1, weight: .semibold))
                .foregroundStyle(appSettings.primaryColor)
        }
    }

    private var manageSubscriptionsURL: URL {
        URL(string: "https://apps.apple.com/account/subscriptions")!
    }

    private func primaryMembershipButtonLabel(_ title: String) -> some View {
        primaryMembershipButtonLabel {
            Text(title)
                .font(appSettings.appFont(.subheadline, weight: .semibold))
        }
    }

    private func primaryMembershipButtonLabel<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                appSettings.primaryGradient,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .foregroundStyle(.white)
    }

    @ViewBuilder
    private var temporaryTestingUnlockButton: some View {
        #if DEBUG
        if !premiumStore.isFlowPlusActive && !hasFlowPlusCustomizationAccess {
            Button {
                _ = appSettings.beginFlowPlusPreview()
                premiumStore.lastErrorMessage = nil
            } label: {
                Text("Temporarily Unlock for Testing")
                    .font(appSettings.appFont(.subheadline, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(appSettings.primaryColor)
        }
        #endif
    }

    private func membershipBenefitRow(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(appSettings.primaryColor)
                .frame(width: 20)

            Text(text)
                .font(appSettings.appFont(.footnote))
                .foregroundStyle(appSettings.themePalette.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsFlowPlusThemesView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var premiumStore: FlowPremiumStore

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var premiumThemeOptions: [AppThemeOption] {
        AppThemeOption.allCases.filter { $0.requiresFlowPlus && $0.isEnabled }
    }

    var body: some View {
        ThemedSettingsForm {
            ThemedSettingsSection("Themes") {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(premiumThemeOptions) { option in
                        themeOptionCard(for: option)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowBackground(settingsSurfaceStyle.cardBackground)
        }
        .navigationTitle("Themes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var settingsSurfaceStyle: SettingsFormSurfaceStyle {
        appSettings.settingsFormSurfaceStyle(for: colorScheme)
    }

    private func themeOptionCard(for option: AppThemeOption) -> some View {
        let isSelected = appSettings.activeTheme == option

        return Button {
            if option.requiresFlowPlus && !premiumStore.isFlowPlusActive {
                guard appSettings.hasFlowPlusCustomizationAccess else { return }
                _ = appSettings.beginThemePreview(option)
            } else {
                appSettings.theme = option
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(themePreviewFill(for: option))
                        .frame(height: 74)
                        .overlay {
                            Image(systemName: option.iconName)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(themePreviewForeground(for: option))
                        }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(appSettings.primaryColor)
                            .padding(8)
                    }
                }

                Text(option.title)
                    .font(appSettings.appFont(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(appSettings.themePalette.secondaryBackground)
            )
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

    private func themePreviewFill(for option: AppThemeOption) -> LinearGradient {
        switch option {
        case .sakura:
            return AppThemeOption.sakura.fixedPrimaryGradient ?? LinearGradient(
                colors: [
                    Color(red: 0.976, green: 0.659, blue: 1.0),
                    Color(red: 1.0, green: 0.404, blue: 0.941)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dracula:
            return AppThemeOption.dracula.fixedPrimaryGradient ?? LinearGradient(
                colors: [
                    Color(red: 0.741, green: 0.576, blue: 0.976),
                    Color(red: 1.0, green: 0.475, blue: 0.776)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .gamer:
            return AppThemeOption.gamer.fixedPrimaryGradient ?? LinearGradient(
                colors: [
                    Color(red: 0.553, green: 0.408, blue: 1.0),
                    Color(red: 0.329, green: 0.920, blue: 0.996)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .black:
            return LinearGradient(
                colors: [Color(red: 0.08, green: 0.08, blue: 0.10), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .white:
            return LinearGradient(
                colors: [Color.white, Color(.systemGray6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .system:
            return LinearGradient(
                colors: [Color(.systemGray6), Color(.systemGray4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dark:
            return LinearGradient(
                colors: [Color(red: 0.19, green: 0.16, blue: 0.28), Color(red: 0.09, green: 0.08, blue: 0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .light:
            return LinearGradient(
                colors: [Color(red: 0.99, green: 0.95, blue: 0.86), Color(red: 0.94, green: 0.98, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func themePreviewForeground(for option: AppThemeOption) -> Color {
        switch option {
        case .white, .light, .system:
            return Color(.label).opacity(0.75)
        case .sakura:
            return Color(red: 0.45, green: 0.21, blue: 0.32)
        case .dracula:
            return Color(red: 0.973, green: 0.973, blue: 0.949).opacity(0.92)
        case .gamer:
            return Color.white.opacity(0.92)
        case .black, .dark:
            return .white.opacity(0.85)
        }
    }
}

struct SettingsFlowPlusTypographyView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var premiumStore: FlowPremiumStore

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
            if option.requiresFlowPlus && !premiumStore.isFlowPlusActive {
                guard appSettings.hasFlowPlusCustomizationAccess else { return }
                appSettings.beginFontPreview(option)
            } else {
                appSettings.fontOption = option
            }
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
