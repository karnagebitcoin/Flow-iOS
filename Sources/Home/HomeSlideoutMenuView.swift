import SwiftUI

struct HomeSlideoutMenuView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @State private var accountHeaderName: String?
    @State private var accountHeaderAvatarURL: URL?

    let onViewProfile: () -> Void
    let onManageRelays: () -> Void
    let onManageSettings: () -> Void
    let onManageAccounts: () -> Void
    let onLogout: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Menu")
                    .font(.headline)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let currentAccount = auth.currentAccount {
                        accountHeader(currentAccount)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                        Divider()
                    }

                    menuButton(
                        title: "View Profile",
                        icon: "person.crop.circle",
                        action: onViewProfile
                    )

                    menuButton(
                        title: "Network",
                        icon: "dot.radiowaves.left.and.right",
                        action: onManageRelays
                    )

                    menuButton(
                        title: "Settings",
                        icon: "gearshape",
                        action: onManageSettings
                    )

                    menuButton(
                        title: "Manage Accounts",
                        icon: "arrow.left.arrow.right.circle",
                        action: onManageAccounts
                    )

                    if auth.isLoggedIn {
                        menuButton(
                            title: "Log Out",
                            icon: "rectangle.portrait.and.arrow.right",
                            tint: .red,
                            action: onLogout
                        )
                    }

                    Spacer(minLength: 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
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

    private func accountHeader(_ account: AuthAccount) -> some View {
        let resolvedName = resolvedAccountName(for: account)

        return HStack(spacing: 12) {
            accountHeaderAvatar(fallbackName: resolvedName)

            VStack(alignment: .leading, spacing: 4) {
                Text(resolvedName)
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Signed in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accountHeaderAvatar(fallbackName: String) -> some View {
        Group {
            if let accountHeaderAvatarURL {
                AsyncImage(url: accountHeaderAvatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        accountHeaderFallbackAvatar(fallbackName: fallbackName)
                    }
                }
            } else {
                accountHeaderFallbackAvatar(fallbackName: fallbackName)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(Color(.separator).opacity(0.35), lineWidth: 0.8)
        }
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
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 22)

                Text(title)
                    .font(.body)
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
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
            accountHeaderAvatarURL = nil
            return
        }

        let normalizedPubkey = account.pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cacheResult = await ProfileCache.shared.resolve(pubkeys: [account.pubkey, normalizedPubkey])
        if let cachedProfile = cacheResult.hits[account.pubkey] ?? cacheResult.hits[normalizedPubkey] {
            accountHeaderName = preferredDisplayName(from: cachedProfile)
            accountHeaderAvatarURL = preferredAvatarURL(from: cachedProfile)
        }

        let readRelayURLs = relaySettings.readRelayURLs
        guard !readRelayURLs.isEmpty else {
            return
        }

        let fetchedProfile = await NostrFeedService().fetchProfile(relayURLs: readRelayURLs, pubkey: normalizedPubkey)
        if let fetchedProfile {
            accountHeaderName = preferredDisplayName(from: fetchedProfile)
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
        guard let picture = trimmedNonEmpty(profile.picture),
              let url = URL(string: picture),
              url.scheme != nil else {
            return nil
        }
        return url
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
