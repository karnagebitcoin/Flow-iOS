import NostrSDK
import SwiftUI

enum AuthSheetTab: String, CaseIterable, Identifiable {
    case signIn = "Sign In"
    case signUp = "Sign Up"
    case accounts = "Accounts"

    var id: String { rawValue }
}

struct AuthSheetView: View {
    private enum PostAuthDestination {
        case dismiss
        case accounts
    }

    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private let initialTab: AuthSheetTab
    private let availableTabs: [AuthSheetTab]
    private let onSelectedTabChange: (AuthSheetTab) -> Void
    @State private var selectedTab: AuthSheetTab
    @State private var privateKeyInput = ""
    @State private var signInError: String?
    @State private var accountProfiles: [String: NostrProfile] = [:]
    @State private var pendingAccountRemoval: AuthAccount?
    @State private var postAuthDestination: PostAuthDestination

    init(
        initialTab: AuthSheetTab = .signIn,
        availableTabs: [AuthSheetTab] = AuthSheetTab.allCases,
        onSelectedTabChange: @escaping (AuthSheetTab) -> Void = { _ in }
    ) {
        let validTabs = availableTabs.isEmpty ? [.signIn] : availableTabs
        self.initialTab = initialTab
        self.availableTabs = validTabs
        self.onSelectedTabChange = onSelectedTabChange
        let resolvedInitialTab = validTabs.contains(initialTab) ? initialTab : validTabs[0]
        _selectedTab = State(initialValue: resolvedInitialTab)
        _postAuthDestination = State(initialValue: resolvedInitialTab == .accounts ? .accounts : .dismiss)
    }

    var body: some View {
        NavigationStack {
            Group {
                if selectedTab == .signUp {
                    SignupOnboardingView(
                        canSwitchToSignIn: availableTabs.contains(.signIn),
                        onSwitchToSignIn: {
                            postAuthDestination = auth.accounts.isEmpty ? .dismiss : .accounts
                            selectedTab = .signIn
                        },
                        onComplete: {
                            handlePostAuthenticationCompletion()
                        }
                    )
                } else if selectedTab == .signIn {
                    signInExperience
                } else {
                    ZStack {
                        AppThemeBackgroundView()
                            .ignoresSafeArea()

                        Form {
                            if availableTabs.count > 1 {
                                FlowCapsuleTabBar(
                                    selection: $selectedTab,
                                    items: availableTabs,
                                    title: { $0.rawValue }
                                )
                                .listRowBackground(appSettings.themePalette.secondaryGroupedBackground)
                            }

                            switch selectedTab {
                            case .signIn:
                                signInSection
                            case .signUp:
                                EmptyView()
                            case .accounts:
                                accountsSection
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                    }
                }
            }
            .navigationTitle(selectedTab == .signUp ? "Create Account" : "Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(selectedTab == .signIn ? .hidden : .visible, for: .navigationBar)
            .onChange(of: selectedTab) { _, newValue in
                onSelectedTabChange(newValue)
                switch newValue {
                case .accounts:
                    postAuthDestination = .accounts
                case .signIn, .signUp:
                    postAuthDestination = auth.accounts.isEmpty ? .dismiss : .accounts
                }
            }
            .task(id: accountsProfileLookupID) {
                await refreshSavedAccountProfiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: .profileMetadataUpdated)) { _ in
                Task {
                    await refreshSavedAccountProfiles()
                }
            }
            .toolbar {
                if selectedTab != .signIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        closeToolbarButton
                    }
                }
            }
            .confirmationDialog(
                "Remove account?",
                isPresented: Binding(
                    get: { pendingAccountRemoval != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingAccountRemoval = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                if let pendingAccountRemoval {
                    Button("Remove Account", role: .destructive) {
                        auth.removeAccount(pendingAccountRemoval)
                        if auth.accounts.isEmpty {
                            dismiss()
                        }
                        self.pendingAccountRemoval = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingAccountRemoval = nil
                }
            } message: {
                if let pendingAccountRemoval {
                    Text("Remove \(accountDisplayName(for: pendingAccountRemoval)) from this device?")
                }
            }
        }
    }

    private var signInExperience: some View {
        ZStack {
            signInBackdrop

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    if availableTabs.count > 1 {
                        signInTabBarCard
                    }

                    if #available(iOS 26.0, *) {
                        VStack(spacing: 24) {
                            signInGlassCard
                            signInRestoreCard
                        }
                    } else {
                        VStack(spacing: 18) {
                            legacySignInCard
                            legacyRestoreCard
                        }
                    }

                    signInFooterNote
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 48)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                signInHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 18)
            }
        }
    }

    private var signInHeader: some View {
        ZStack {
            Text("Account")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            HStack {
                Spacer()
                closeToolbarButton
            }
        }
    }

    private var signInSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Text("Sign in with your private key")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                SecureField("Private key", text: $privateKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color(.separator).opacity(0.42), lineWidth: 1.15)
                    }

                if let signInError {
                    Text(signInError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    handleSignIn()
                } label: {
                    Text("Sign In")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .foregroundStyle(authPrimaryButtonForeground)
                        .background(
                            Capsule(style: .continuous)
                                .fill(authPrimaryButtonFill)
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(authPrimaryButtonBorder, lineWidth: 1)
                        }
                        .shadow(
                            color: colorScheme == .light ? Color.black.opacity(0.08) : .clear,
                            radius: colorScheme == .light ? 10 : 0,
                            y: colorScheme == .light ? 5 : 0
                        )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ICloudKeyRestoreView {
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Restore from iCloud")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Use a private key already backed up to iCloud Keychain.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color(.separator).opacity(0.28), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        } footer: {
            Text("Use private-key sign in to enable posting, reactions, and replies. If your key was backed up before, you can restore it from iCloud here.")
        }
    }

    private var signInBackdrop: some View {
        ZStack {
            UnicornStudioBackgroundView(
                source: .bundledJSON("sign_in_background.json"),
                opacity: 1,
                backgroundStyle: .clear,
                allowsInteraction: false
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.clear,
                    Color.clear,
                    Color.white.opacity(0.02),
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.14)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    @available(iOS 26.0, *)
    private var signInGlassCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign in with your private key")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(authInk.opacity(0.78))

            signInPrivateKeyField

            if let signInError {
                Text(signInError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            signInPrimaryButton
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(authBlurCardBackground(cornerRadius: 28))
    }

    private var signInTabBarCard: some View {
        Group {
            if #available(iOS 26.0, *) {
                FlowCapsuleTabBar(
                    selection: $selectedTab,
                    items: availableTabs,
                    title: { $0.rawValue }
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(authBlurCapsuleBackground)
            } else {
                FlowCapsuleTabBar(
                    selection: $selectedTab,
                    items: availableTabs,
                    title: { $0.rawValue }
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            }
        }
    }

    private var signInPrivateKeyField: some View {
        SecureField("Private key", text: $privateKeyInput)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.22))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.34), lineWidth: 1.15)
            }
    }

    private var signInPrimaryButton: some View {
        Group {
            if #available(iOS 26.0, *) {
                Button {
                    handleSignIn()
                } label: {
                    Text("Sign In")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .foregroundStyle(authInk)
                }
                .buttonStyle(.plain)
                .glassEffect(
                    .regular
                        .tint(Color.white.opacity(0.44))
                        .interactive(),
                    in: Capsule(style: .continuous)
                )
            } else {
                Button {
                    handleSignIn()
                } label: {
                    Text("Sign In")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .foregroundStyle(authPrimaryButtonForeground)
                        .background(
                            Capsule(style: .continuous)
                                .fill(authPrimaryButtonFill)
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(authPrimaryButtonBorder, lineWidth: 1)
                        }
                        .shadow(
                            color: colorScheme == .light ? Color.black.opacity(0.08) : .clear,
                            radius: colorScheme == .light ? 10 : 0,
                            y: colorScheme == .light ? 5 : 0
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var signInRestoreCard: some View {
        Group {
            if #available(iOS 26.0, *) {
                NavigationLink {
                    ICloudKeyRestoreView {
                        dismiss()
                    }
                } label: {
                    signInRestoreLabel
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .background(authBlurCardBackground(cornerRadius: 24))
            } else {
                legacyRestoreCard
            }
        }
    }

    private var signInRestoreLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Restore from iCloud")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Use a private key already backed up to iCloud Keychain.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var signInFooterNote: some View {
        Text("Use private-key sign in to enable posting, reactions, and replies. If your key was backed up before, you can restore it from iCloud here.")
            .font(.footnote)
            .foregroundStyle(Color.white.opacity(colorScheme == .dark ? 0.80 : 0.92))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .shadow(color: Color.black.opacity(0.18), radius: 10, y: 6)
    }

    private var legacySignInCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign in with your private key")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            signInPrivateKeyField

            if let signInError {
                Text(signInError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            signInPrimaryButton
        }
        .padding(18)
        .background(authBlurCardBackground(cornerRadius: 28))
    }

    private var legacyRestoreCard: some View {
        NavigationLink {
            ICloudKeyRestoreView {
                dismiss()
            }
        } label: {
            signInRestoreLabel
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(authBlurCardBackground(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }

    private func authBlurCardBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.12))
            }
            .overlay {
                shape
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.34), lineWidth: 0.9)
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.08),
                radius: colorScheme == .dark ? 20 : 16,
                y: colorScheme == .dark ? 10 : 8
            )
    }

    private var authBlurCapsuleBackground: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.10))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.32), lineWidth: 0.9)
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.14 : 0.06),
                radius: colorScheme == .dark ? 18 : 14,
                y: colorScheme == .dark ? 9 : 7
            )
    }

    private var authInk: Color {
        Color(red: 0.06, green: 0.10, blue: 0.18)
    }

    private var authPrimaryButtonFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.96) : authInk
    }

    private var authPrimaryButtonForeground: Color {
        colorScheme == .dark ? authInk : .white
    }

    private var authPrimaryButtonBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : authInk.opacity(0.16)
    }

    private var closeButtonForeground: Color {
        colorScheme == .dark ? .white.opacity(0.92) : authInk
    }

    private var closeButtonBackground: Color {
        appSettings.themePalette.secondaryGroupedBackground
    }

    private var closeButtonBorder: Color {
        appSettings.themePalette.separator.opacity(colorScheme == .dark ? 0.92 : 0.72)
    }

    private var closeToolbarButton: some View {
        Group {
            if #available(iOS 26.0, *), selectedTab == .signIn {
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(authInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .glassEffect(
                    .regular
                        .tint(Color.white.opacity(0.22))
                        .interactive(),
                    in: Capsule(style: .continuous)
                )
            } else {
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(closeButtonForeground)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(closeButtonBackground, in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(closeButtonBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var accountsSection: some View {
        Section {
            if auth.accounts.isEmpty {
                Text("No saved accounts yet.")
                    .foregroundStyle(appSettings.themePalette.mutedForeground)
                    .listRowBackground(appSettings.themePalette.secondaryGroupedBackground)
            } else {
                ForEach(auth.accounts) { account in
                    HStack(spacing: 12) {
                        Button {
                            auth.switchAccount(to: account)
                        } label: {
                            HStack(spacing: 12) {
                                accountAvatar(for: account)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(accountDisplayName(for: account))
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if let handle = accountHandle(for: account) {
                                        Text(handle)
                                            .font(.caption)
                                            .foregroundStyle(appSettings.themePalette.mutedForeground)
                                            .lineLimit(1)
                                    }
                                    Text(accountBackupLabel(for: account))
                                        .font(.caption2)
                                        .foregroundStyle(appSettings.themePalette.mutedForeground)
                                }
                                Spacer()
                                if auth.currentAccount?.id == account.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(appSettings.primaryColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive) {
                            pendingAccountRemoval = account
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.title3)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove account")
                    }
                    .listRowBackground(appSettings.themePalette.secondaryGroupedBackground)
                }
            }
        }

        if auth.isLoggedIn {
            Section {
                Button("Log Out", role: .destructive) {
                    auth.logout()
                }
            }
            .listRowBackground(appSettings.themePalette.secondaryGroupedBackground)
        }
    }

    private func handleSignIn() {
        signInError = nil
        do {
            _ = try auth.loginWithNsecOrHex(privateKeyInput)
            privateKeyInput = ""
            handlePostAuthenticationCompletion()
        } catch {
            signInError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func handlePostAuthenticationCompletion() {
        switch postAuthDestination {
        case .dismiss:
            dismiss()
        case .accounts:
            selectedTab = .accounts
            Task {
                await refreshSavedAccountProfiles()
            }
        }
    }

    private var effectiveReadRelayURLs: [URL] {
        appSettings.effectiveReadRelayURLs(from: relaySettings.readRelayURLs)
    }

    @MainActor
    private var accountsProfileLookupID: String {
        let accountsSignature = auth.accounts
            .map(\.pubkey)
            .sorted()
            .joined(separator: ",")
        let relaySignature = effectiveReadRelayURLs
            .map(\.absoluteString)
            .map { $0.lowercased() }
            .joined(separator: ",")
        return "\(accountsSignature)|\(relaySignature)"
    }

    @MainActor
    private func refreshSavedAccountProfiles() async {
        let pubkeys = auth.accounts.map { $0.pubkey.lowercased() }
        guard !pubkeys.isEmpty else {
            accountProfiles = [:]
            return
        }

        let cacheResult = await ProfileCache.shared.resolve(pubkeys: pubkeys)
        var mergedProfiles = cacheResult.hits

        let fetchedProfiles = await NostrFeedService().fetchProfiles(
            relayURLs: effectiveReadRelayURLs,
            pubkeys: pubkeys
        )
        for (pubkey, profile) in fetchedProfiles {
            mergedProfiles[pubkey.lowercased()] = profile
        }

        accountProfiles = mergedProfiles
    }

    private func profile(for account: AuthAccount) -> NostrProfile? {
        accountProfiles[account.pubkey.lowercased()]
    }

    private func accountDisplayName(for account: AuthAccount) -> String {
        if let profile = profile(for: account) {
            if let displayName = normalized(profile.displayName), !displayName.isEmpty {
                return displayName
            }
            if let name = normalized(profile.name), !name.isEmpty {
                return name
            }
        }
        return shortNostrIdentifier(account.pubkey)
    }

    private func accountHandle(for account: AuthAccount) -> String? {
        if let profile = profile(for: account) {
            if let name = normalized(profile.name), !name.isEmpty {
                return "@\(name)"
            }
            if let displayName = normalized(profile.displayName), !displayName.isEmpty {
                return "@\(displayName.replacingOccurrences(of: " ", with: "").lowercased())"
            }
        }
        return nil
    }

    private func avatarURL(for account: AuthAccount) -> URL? {
        profile(for: account)?.resolvedAvatarURL
    }

    private func accountBackupLabel(for account: AuthAccount) -> String {
        guard account.signerType == .nsec else {
            return "Read-only account"
        }
        return account.privateKeyBackupEnabled
            ? "Private key account • iCloud backup on"
            : "Private key account • stored on this device"
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    @ViewBuilder
    private func accountAvatar(for account: AuthAccount) -> some View {
        let fallbackName = accountDisplayName(for: account)
        if let avatarURL = avatarURL(for: account) {
            CachedAsyncImage(url: avatarURL, kind: .avatar) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    accountAvatarFallback(name: fallbackName, account: account)
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())
        } else {
            accountAvatarFallback(name: fallbackName, account: account)
        }
    }

    private func accountAvatarFallback(name: String, account: AuthAccount) -> some View {
        ZStack {
            Circle()
                .fill(appSettings.avatarFallbackGradient(forAccountPubkey: account.pubkey))
            Text(String(name.prefix(1)).uppercased())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(appSettings.avatarFallbackForeground(forAccountPubkey: account.pubkey))
        }
        .frame(width: 42, height: 42)
    }
}
