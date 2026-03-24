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
    @Environment(\.dismiss) private var dismiss

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
                            Picker("Tab", selection: $selectedTab) {
                                ForEach(availableTabs) { tab in
                                    Text(tab.rawValue).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)
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
                    Button("Close") {
                        dismiss()
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

    private var signInSection: some View {
        Section {
            SecureField("nsec1... or 64-char hex", text: $privateKeyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if let signInError {
                Text(signInError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button("Sign In") {
                handleSignIn()
            }
            .buttonStyle(.borderedProminent)
        } footer: {
            Text("Use private-key sign in to enable posting, reactions, and replies.")
        }
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
                                    Text(account.signerType == .nsec ? "Private key account" : "Read-only account")
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
