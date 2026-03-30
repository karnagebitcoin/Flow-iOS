import SwiftUI

struct SettingsFlowPlusView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var premiumStore: FlowPremiumStore
    @State private var isPurchasingFlowPlus = false

    var body: some View {
        Form {
            Section {
                membershipCard
            }

            Section("Customize") {
                FlowPlusDestinationRow(
                    title: "Themes",
                    subtitle: currentThemeSummary,
                    systemImage: "sparkles",
                    isEnabled: hasFlowPlusCustomizationAccess
                ) {
                    SettingsFlowPlusThemesView()
                }

                FlowPlusDestinationRow(
                    title: "Typography",
                    subtitle: currentTypographySummary,
                    systemImage: "textformat",
                    isEnabled: hasFlowPlusCustomizationAccess
                ) {
                    SettingsFlowPlusTypographyView()
                }
            }

            if let error = premiumStore.lastErrorMessage, !error.isEmpty {
                Section {
                    Text(error)
                        .font(appSettings.appFont(.footnote))
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Flow Plus")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await premiumStore.refreshProducts()
            await premiumStore.refreshEntitlements()
        }
    }

    private var unlockButtonTitle: String {
        "Unlock for \(premiumStore.flowPlusProduct?.displayPrice ?? "$5.99")"
    }

    private var hasFlowPlusCustomizationAccess: Bool {
        premiumStore.isFlowPlusActive || appSettings.hasFlowPlusCustomizationAccess
    }

    private var currentThemeSummary: String {
        guard hasFlowPlusCustomizationAccess else {
            return "Unlock Flow Plus to open"
        }

        if appSettings.activeTheme.requiresFlowPlus {
            return appSettings.activeTheme.title
        }
        return "Choose a premium theme"
    }

    private var currentTypographySummary: String {
        guard hasFlowPlusCustomizationAccess else {
            return "Unlock Flow Plus to open"
        }

        if appSettings.activeFontOption.requiresFlowPlus {
            return appSettings.activeFontOption.title
        }
        return "Choose a premium font"
    }

    private var canPreviewFlowPlus: Bool {
        premiumStore.isFlowPlusActive || appSettings.canBeginFlowPlusPreview()
    }

    private var previewStatusText: String {
        if premiumStore.isFlowPlusActive {
            return "Themes and typography are unlocked."
        }

        if appSettings.isFlowPlusPreviewUnlocked {
            return "Theme and typography previews are unlocked for this session."
        }

        if appSettings.canBeginFlowPlusPreview() {
            return "Preview themes and typography once per session before unlocking."
        }

        return "Preview already used this session."
    }

    private var membershipCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Flow Plus")
                        .font(appSettings.appFont(.title3, weight: .semibold))

                    Text("Unlock new themes, fonts and other fun enhancements with Flow Plus.")
                        .font(appSettings.appFont(.footnote))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                membershipStatusBadge
            }

            if premiumStore.isFlowPlusActive {
                Link(destination: manageSubscriptionsURL) {
                    primaryMembershipButtonLabel("Manage Subscription")
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 10) {
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

                    Button {
                        _ = appSettings.beginFlowPlusPreview()
                    } label: {
                        Text("Preview")
                            .font(appSettings.appFont(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                appSettings.themePalette.secondaryBackground,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canPreviewFlowPlus)
                    .opacity(canPreviewFlowPlus ? 1 : 0.6)
                }
            }

            Text(previewStatusText)
                .font(appSettings.appFont(.footnote))
                .foregroundStyle(.secondary)
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
        } else if appSettings.isFlowPlusPreviewUnlocked {
            Label("Preview", systemImage: "eye.fill")
                .font(appSettings.appFont(.caption1, weight: .semibold))
                .foregroundStyle(appSettings.primaryColor)
        } else {
            Label("Locked", systemImage: "sparkles")
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
}

private struct SettingsFlowPlusThemesView: View {
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
        Form {
            Section("Themes") {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(premiumThemeOptions) { option in
                        themeOptionCard(for: option)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Themes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func themeOptionCard(for option: AppThemeOption) -> some View {
        let isSelected = appSettings.activeTheme == option

        return Button {
            if option.requiresFlowPlus && !premiumStore.isFlowPlusActive {
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
                        isSelected ? appSettings.primaryColor : appSettings.themePalette.separator.opacity(0.18),
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
        case .black, .dark:
            return .white.opacity(0.85)
        }
    }
}

private struct SettingsFlowPlusTypographyView: View {
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
        Form {
            Section("Typography") {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(typographyOptions) { option in
                        fontOptionCard(for: option)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Typography")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fontOptionCard(for option: AppFontOption) -> some View {
        let isSelected = appSettings.activeFontOption == option

        return Button {
            if option.requiresFlowPlus && !premiumStore.isFlowPlusActive {
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
                        isSelected ? appSettings.primaryColor : appSettings.themePalette.separator.opacity(0.18),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct FlowPlusDestinationRow<Destination: View>: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    let title: String
    let subtitle: String
    let systemImage: String
    let isEnabled: Bool
    let destination: Destination

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        isEnabled: Bool,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.destination = destination()
    }

    var body: some View {
        Group {
            if isEnabled {
                NavigationLink {
                    destination
                } label: {
                    rowContent
                }
            } else {
                rowContent
            }
        }
        .opacity(isEnabled ? 1 : 0.6)
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(appSettings.primaryColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(appSettings.appFont(.body, weight: .regular))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(appSettings.appFont(.footnote))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !isEnabled {
                Image(systemName: "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
