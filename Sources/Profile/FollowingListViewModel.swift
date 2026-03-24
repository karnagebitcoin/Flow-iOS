import Foundation

@MainActor
final class FollowingListViewModel: ObservableObject {
    struct Row: Identifiable, Hashable {
        let pubkey: String
        let profile: NostrProfile?

        var id: String { pubkey }

        var displayName: String {
            if let displayName = profile?.displayName?.trimmed, !displayName.isEmpty {
                return displayName
            }
            if let name = profile?.name?.trimmed, !name.isEmpty {
                return name
            }
            return shortNostrIdentifier(pubkey)
        }

        var handle: String {
            if let name = profile?.name?.trimmed, !name.isEmpty {
                return "@\(name.replacingOccurrences(of: " ", with: "").lowercased())"
            }
            if let displayName = profile?.displayName?.trimmed, !displayName.isEmpty {
                return "@\(displayName.replacingOccurrences(of: " ", with: "").lowercased())"
            }
            return "@\(shortNostrIdentifier(pubkey).lowercased())"
        }

        var avatarURL: URL? {
            guard let picture = profile?.picture?.trimmed, let url = URL(string: picture) else {
                return nil
            }
            return url
        }

        var nip05Domain: String? {
            guard let nip05 = profile?.nip05?.trimmed, !nip05.isEmpty else { return nil }
            let lowercased = nip05.lowercased()
            guard let atIndex = lowercased.lastIndex(of: "@") else { return nil }
            let domain = lowercased[lowercased.index(after: atIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            return domain.isEmpty ? nil : String(domain)
        }
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    let pubkey: String
    let readRelayURLs: [URL]

    private let service: NostrFeedService
    private var hasLoadedInitialState = false
    private static let fastFollowingFetchTimeout: TimeInterval = 3
    private static let fastFollowingRelayFetchMode: RelayFetchMode = .firstNonEmptyRelay

    init(
        pubkey: String,
        readRelayURLs: [URL],
        service: NostrFeedService = NostrFeedService()
    ) {
        self.pubkey = pubkey
        self.readRelayURLs = readRelayURLs
        self.service = service
    }

    func loadIfNeeded() async {
        guard !hasLoadedInitialState else { return }
        await refresh(markInitialLoad: true)
        hasLoadedInitialState = true
    }

    func refresh(markInitialLoad: Bool = false) async {
        if isLoading || isRefreshing {
            return
        }

        let isInitialLoad = markInitialLoad || !hasLoadedInitialState
        isLoading = isInitialLoad
        isRefreshing = !isInitialLoad
        errorMessage = nil

        if rows.isEmpty,
           let cachedSnapshot = await service.cachedFollowListSnapshot(pubkey: pubkey) {
            let followedPubkeys = cachedSnapshot.followedPubkeys
            let cachedProfiles = await service.cachedProfiles(pubkeys: followedPubkeys)
            rows = followedPubkeys.map { Row(pubkey: $0, profile: cachedProfiles[$0]) }
        }

        defer {
            isLoading = false
            isRefreshing = false
        }

        do {
            guard let snapshot = try await service.fetchFollowListSnapshot(
                relayURLs: readRelayURLs,
                pubkey: pubkey,
                fetchTimeout: Self.fastFollowingFetchTimeout,
                relayFetchMode: Self.fastFollowingRelayFetchMode
            ) else {
                rows = []
                return
            }

            let followedPubkeys = snapshot.followedPubkeys
            let profileRelayURLs = relayTargetsForFollowingProfiles(snapshot: snapshot)
            let profilesByPubkey = await service.fetchProfiles(
                relayURLs: profileRelayURLs,
                pubkeys: followedPubkeys,
                fetchTimeout: Self.fastFollowingFetchTimeout,
                relayFetchMode: Self.fastFollowingRelayFetchMode
            )
            rows = followedPubkeys.map { Row(pubkey: $0, profile: profilesByPubkey[$0]) }
        } catch {
            if rows.isEmpty {
                errorMessage = "Couldn't load this following list right now."
            } else {
                errorMessage = "Couldn't refresh this following list."
            }
        }
    }

    private func relayTargetsForFollowingProfiles(snapshot: FollowListSnapshot) -> [URL] {
        var seen = Set<String>()
        var targets: [URL] = []

        func append(_ url: URL) {
            let key = url.absoluteString.lowercased()
            guard seen.insert(key).inserted else { return }
            targets.append(url)
        }

        for url in readRelayURLs {
            append(url)
        }

        // Use relay hints from contact list tags to improve profile hit-rate.
        for hintURLs in snapshot.relayHintsByPubkey.values {
            for url in hintURLs {
                append(url)
                if targets.count >= 28 {
                    return targets
                }
            }
        }

        return targets
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
