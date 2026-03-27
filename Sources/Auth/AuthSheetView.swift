import NostrSDK
import SwiftUI

enum AuthSheetTab: String, CaseIterable, Identifiable {
    case signIn = "Sign In"
    case signUp = "Sign Up"
    case accounts = "Accounts"

    var id: String { rawValue }
}

struct AuthSheetView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private let initialTab: AuthSheetTab
    private let availableTabs: [AuthSheetTab]
    @State private var selectedTab: AuthSheetTab
    @State private var privateKeyInput = ""
    @State private var signInError: String?
    @State private var accountProfiles: [String: NostrProfile] = [:]
    @State private var pendingAccountRemoval: AuthAccount?

    init(
        initialTab: AuthSheetTab = .signIn,
        availableTabs: [AuthSheetTab] = AuthSheetTab.allCases
    ) {
        let validTabs = availableTabs.isEmpty ? [.signIn] : availableTabs
        self.initialTab = initialTab
        self.availableTabs = validTabs
        let resolvedInitialTab = validTabs.contains(initialTab) ? initialTab : validTabs[0]
        _selectedTab = State(initialValue: resolvedInitialTab)
    }

    var body: some View {
        NavigationStack {
            Group {
                if selectedTab == .signUp {
                    SignupOnboardingView(
                        canSwitchToSignIn: availableTabs.contains(.signIn),
                        onSwitchToSignIn: {
                            selectedTab = .signIn
                        },
                        onComplete: {
                            dismiss()
                        }
                    )
                } else {
                    Form {
                        if availableTabs.count > 1 {
                            FlowCapsuleTabBar(
                                selection: $selectedTab,
                                items: availableTabs,
                                title: { $0.rawValue }
                            )
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
                }
            }
            .navigationTitle(selectedTab == .signUp ? "Create Account" : "Account")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                let resolvedInitialTab = availableTabs.contains(initialTab) ? initialTab : availableTabs[0]
                if selectedTab != resolvedInitialTab {
                    selectedTab = resolvedInitialTab
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
                ToolbarItem(placement: .topBarTrailing) {
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
            }
        } footer: {
            Text("Use private-key sign in to enable posting, reactions, and replies.")
        }
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
        colorScheme == .dark ? Color.white.opacity(0.12) : Color(.secondarySystemBackground)
    }

    private var closeButtonBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color(.separator).opacity(0.20)
    }

    @ViewBuilder
    private var accountsSection: some View {
        Section {
            if auth.accounts.isEmpty {
                Text("No saved accounts yet.")
                    .foregroundStyle(.secondary)
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
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Text(accountBackupLabel(for: account))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if auth.currentAccount?.id == account.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
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
                }
            }
        }

        if auth.isLoggedIn {
            Section {
                Button("Log Out", role: .destructive) {
                    auth.logout()
                }
            }
        }
    }

    private func handleSignIn() {
        signInError = nil
        do {
            _ = try auth.loginWithNsecOrHex(privateKeyInput)
            dismiss()
        } catch {
            signInError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
        guard let picture = normalized(profile(for: account)?.picture),
              !picture.isEmpty,
              let url = URL(string: picture),
              url.scheme != nil else {
            return nil
        }
        return url
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
            AsyncImage(url: avatarURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    accountAvatarFallback(name: fallbackName)
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())
        } else {
            accountAvatarFallback(name: fallbackName)
        }
    }

    private func accountAvatarFallback(name: String) -> some View {
        ZStack {
            Circle()
                .fill(Color(.secondarySystemBackground))
            Text(String(name.prefix(1)).uppercased())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 42, height: 42)
    }
}
