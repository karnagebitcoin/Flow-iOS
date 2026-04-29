import SwiftUI

struct HomeSlideoutMenuView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.sideMenuPresentationIsOpen) private var isMenuPresented
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @State private var accountHeaderName: String?
    @State private var accountHeaderHandle: String?
    @State private var accountHeaderAvatarURL: URL?
    @State private var isShowingProfileQR = false

    let onViewProfile: () -> Void
    let onOpenScannedProfile: (String) -> Void
    let onManageSettings: () -> Void
    let onManageAccounts: () -> Void
    let onLogout: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Menu")
                    .font(appSettings.appFont(.headline, weight: .semibold))
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(appSettings.themePalette.foreground)
                        .frame(width: 32, height: 32)
                        .background(appSettings.themePalette.sheetCardBackground.opacity(0.82), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(appSettings.themePalette.separator.opacity(0.22), lineWidth: 0.8)
                        }
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close menu")
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()
                .overlay(appSettings.themeSeparator(defaultOpacity: 0.18))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    if let currentAccount = auth.currentAccount {
                        revealedMenuRow(index: 0) {
                            accountHeader(currentAccount)
                                .padding(14)
                                .background(
                                    appSettings.primaryColor.opacity(
                                        SideMenuTransitionLayout.profileHeaderPrimaryFillOpacity
                                    ),
                                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .stroke(appSettings.primaryColor.opacity(0.1), lineWidth: 0.8)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                        }

                        Divider()
                            .overlay(appSettings.themeSeparator(defaultOpacity: 0.18))
                    }

                    revealedMenuRow(index: 1) {
                        menuButton(
                            title: "View Profile",
                            icon: "person",
                            action: onViewProfile
                        )
                    }

                    revealedMenuRow(index: 2) {
                        menuButton(
                            title: "Settings",
                            icon: "gearshape",
                            action: onManageSettings
                        )
                    }

                    revealedMenuRow(index: 3) {
                        menuButton(
                            title: "Manage Accounts",
                            icon: "arrow.left.arrow.right.circle",
                            action: onManageAccounts
                        )
                    }

                    if auth.isLoggedIn {
                        revealedMenuRow(index: 4) {
                            menuButton(
                                title: "Log Out",
                                icon: "rectangle.portrait.and.arrow.right",
                                tint: .red,
                                action: onLogout
                            )
                        }
                    }

                    Spacer(minLength: 24)
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(menuBackground)
        .sheet(isPresented: $isShowingProfileQR) {
            if let currentAccount = auth.currentAccount {
                ProfileQRCodeSheet(
                    npub: currentAccount.npub,
                    displayName: resolvedAccountName(for: currentAccount),
                    handle: resolvedAccountHandle,
                    avatarURL: accountHeaderAvatarURL,
                    onOpenProfile: { pubkey in
                        onOpenScannedProfile(pubkey)
                    }
                )
                .presentationBackground(menuBackground)
            }
        }
        .task(id: accountHeaderLookupID) {
            await refreshAccountHeaderName()
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileMetadataUpdated)) { notification in
            guard let updatedPubkey = (notification.userInfo?["pubkey"] as? String)?.lowercased(),
                  let currentPubkey = auth.currentAccount?.pubkey.lowercased(),
                  updatedPubkey == currentPubkey else {
                return
            }
            Task {
                await refreshAccountHeaderName()
            }
        }
    }

    private var menuBackground: Color {
        effectiveMenuColorScheme == .light ? .white : appSettings.themePalette.sheetBackground
    }

    private var effectiveMenuColorScheme: ColorScheme {
        appSettings.preferredColorScheme ?? colorScheme
    }

    private func accountHeader(_ account: AuthAccount) -> some View {
        let resolvedName = resolvedAccountName(for: account)

        return HStack(spacing: 12) {
            Button {
                onViewProfile()
            } label: {
                accountHeaderAvatar(fallbackName: resolvedName)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View profile")

            VStack(alignment: .leading, spacing: 4) {
                Text(resolvedName)
                    .font(appSettings.appFont(.subheadline, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Active")
                    .font(appSettings.appFont(.caption1))
                    .foregroundStyle(appSettings.themePalette.secondaryForeground)
            }

            Spacer(minLength: 0)

            Button {
                isShowingProfileQR = true
            } label: {
                Image(systemName: "qrcode")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(appSettings.themePalette.foreground)
                    .frame(width: 36, height: 36)
                    .background(appSettings.themePalette.sheetCardBackground.opacity(0.86), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(appSettings.themePalette.separator.opacity(0.2), lineWidth: 0.8)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show profile QR")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accountHeaderAvatar(fallbackName: String) -> some View {
        AvatarView(
            url: accountHeaderAvatarURL,
            fallback: fallbackName,
            size: 60,
            fallbackGradient: appSettings.avatarFallbackGradient(forAccountPubkey: auth.currentAccount?.pubkey),
            fallbackForeground: appSettings.avatarFallbackForeground(forAccountPubkey: auth.currentAccount?.pubkey)
        )
    }

    private func accountHeaderFallbackAvatar(fallbackName: String) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.85), Color.accentColor.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(fallbackName.prefix(1).uppercased())
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
        }
    }

    private func menuButton(
        title: String,
        icon: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let iconTint = tint ?? appSettings.themeIconAccentColor
        let textTint = tint ?? appSettings.themePalette.foreground

        return Button {
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(iconTint)
                    .frame(width: 34, height: 34)
                    .background(
                        iconTint.opacity(SideMenuTransitionLayout.menuIconBackgroundOpacity),
                        in: Circle()
                    )

                Text(title)
                    .font(appSettings.appFont(.body))
                    .foregroundStyle(textTint)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func revealedMenuRow<Content: View>(
        index: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(isMenuPresented ? 1 : SideMenuTransitionLayout.rowClosedOpacity)
            .offset(
                x: isMenuPresented ? 0 : SideMenuTransitionLayout.rowClosedXOffset,
                y: isMenuPresented ? 0 : SideMenuTransitionLayout.rowClosedYOffset
            )
            .animation(rowAnimation(index: index), value: isMenuPresented)
    }

    private func rowAnimation(index: Int) -> Animation? {
        guard !accessibilityReduceMotion else { return nil }

        let animation = Animation.easeOut(duration: 0.24)
        guard isMenuPresented else { return animation }

        return animation.delay(Double(index) * SideMenuTransitionLayout.rowStaggerDelay)
    }

    @MainActor
    private var accountHeaderLookupID: String {
        let accountID = auth.currentAccount?.id ?? "none"
        let relaySignature = relaySettings.readRelayURLs
            .map { $0.absoluteString.lowercased() }
            .joined(separator: ",")
        return "\(accountID)|\(relaySignature)"
    }

    @MainActor
    private func resolvedAccountName(for account: AuthAccount) -> String {
        guard let accountHeaderName = trimmedNonEmpty(accountHeaderName) else {
            return account.shortLabel
        }
        return accountHeaderName
    }

    @MainActor
    private func refreshAccountHeaderName() async {
        guard let account = auth.currentAccount else {
            accountHeaderName = nil
            accountHeaderHandle = nil
            accountHeaderAvatarURL = nil
            return
        }

        accountHeaderName = nil
        accountHeaderHandle = nil
        accountHeaderAvatarURL = nil

        let normalizedPubkey = account.pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cacheResult = await ProfileCache.shared.resolve(pubkeys: [account.pubkey, normalizedPubkey])
        if let cachedProfile = cacheResult.hits[account.pubkey] ?? cacheResult.hits[normalizedPubkey] {
            accountHeaderName = preferredDisplayName(from: cachedProfile)
            accountHeaderHandle = preferredHandle(from: cachedProfile)
            accountHeaderAvatarURL = preferredAvatarURL(from: cachedProfile)
        }

        let readRelayURLs = relaySettings.readRelayURLs
        guard !readRelayURLs.isEmpty else {
            return
        }

        let fetchedProfile = await NostrFeedService().fetchProfile(relayURLs: readRelayURLs, pubkey: normalizedPubkey)
        if let fetchedProfile {
            accountHeaderName = preferredDisplayName(from: fetchedProfile)
            accountHeaderHandle = preferredHandle(from: fetchedProfile)
            accountHeaderAvatarURL = preferredAvatarURL(from: fetchedProfile)
        }
    }

    private func preferredDisplayName(from profile: NostrProfile) -> String? {
        if let displayName = trimmedNonEmpty(profile.displayName) {
            return displayName
        }
        return trimmedNonEmpty(profile.name)
    }

    private func preferredAvatarURL(from profile: NostrProfile) -> URL? {
        profile.resolvedAvatarURL
    }

    private func preferredHandle(from profile: NostrProfile) -> String? {
        if let name = trimmedNonEmpty(profile.name) {
            return "@\(normalizedHandleComponent(from: name))"
        }
        if let displayName = trimmedNonEmpty(profile.displayName) {
            return "@\(normalizedHandleComponent(from: displayName))"
        }
        return nil
    }

    private var resolvedAccountHandle: String? {
        trimmedNonEmpty(accountHeaderHandle)
    }

    private func normalizedHandleComponent(from value: String) -> String {
        let compact = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        return compact.isEmpty ? "user" : compact
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
