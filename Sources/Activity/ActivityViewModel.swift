import Foundation

@MainActor
final class ActivityViewModel: ObservableObject {
    @Published private(set) var items: [ActivityRow] = []
    @Published var selectedFilter: ActivityFilter = .all
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    private let service: NostrFeedService
    private var hasLoadedInitialState = false
    private var currentUserPubkey: String?
    private var readRelayURLs: [URL]
    private var requestCounter = 0
    private static let fastActivityFetchTimeout: TimeInterval = 3
    private static let fastActivityRelayFetchMode: RelayFetchMode = .firstNonEmptyRelay

    init(service: NostrFeedService = NostrFeedService()) {
        self.service = service
        self.readRelayURLs = RelaySettingsStore.defaultReadRelayURLs.compactMap(URL.init(string:))
    }

    var visibleItems: [ActivityRow] {
        items
    }

    var primaryRelayURL: URL {
        readRelayURLs.first
            ?? URL(string: RelaySettingsStore.defaultReadRelayURLs.first ?? "wss://relay.damus.io/")!
    }

    func configure(currentUserPubkey: String?, readRelayURLs: [URL]) {
        let normalizedUser = normalizePubkey(currentUserPubkey)
        let normalizedRelays = normalizedRelayURLs(readRelayURLs)

        let relaysChanged = normalizedRelays.map { $0.absoluteString.lowercased() } != self.readRelayURLs.map { $0.absoluteString.lowercased() }
        let userChanged = normalizedUser != self.currentUserPubkey

        self.currentUserPubkey = normalizedUser
        if !normalizedRelays.isEmpty {
            self.readRelayURLs = normalizedRelays
        }

        guard hasLoadedInitialState else { return }
        guard relaysChanged || userChanged else { return }

        Task { [weak self] in
            await self?.refreshForSelectedTab(showFullScreenLoading: true)
        }
    }

    func loadIfNeeded() async {
        guard !hasLoadedInitialState else { return }
        hasLoadedInitialState = true
        await refreshForSelectedTab(showFullScreenLoading: true)
    }

    func refresh() async {
        await refreshForSelectedTab(showFullScreenLoading: visibleItems.isEmpty)
    }

    func selectedFilterChanged() async {
        await refreshForSelectedTab(showFullScreenLoading: visibleItems.isEmpty)
    }

    private func refreshForSelectedTab(showFullScreenLoading: Bool) async {
        if showFullScreenLoading {
            guard !isLoading else { return }
            isLoading = true
        } else {
            guard !isRefreshing else { return }
            isRefreshing = true
        }

        errorMessage = nil
        requestCounter += 1
        let requestID = requestCounter
        let filter = selectedFilter
        let relays = readRelayURLs
        let user = currentUserPubkey

        defer {
            isLoading = false
            isRefreshing = false
        }

        guard let user, !user.isEmpty else {
            items = []
            errorMessage = "Sign in to view activity."
            return
        }

        do {
            let fetched = try await service.fetchActivityRows(
                relayURLs: relays,
                currentUserPubkey: user,
                filter: filter,
                limit: 120,
                fetchTimeout: Self.fastActivityFetchTimeout,
                relayFetchMode: Self.fastActivityRelayFetchMode,
                profileFetchTimeout: Self.fastActivityFetchTimeout,
                profileRelayFetchMode: Self.fastActivityRelayFetchMode
            )
            guard requestID == requestCounter else { return }
            items = sortAndDeduplicate(items: fetched)
        } catch {
            guard requestID == requestCounter else { return }
            if items.isEmpty {
                errorMessage = "Couldn't load activity right now."
            } else {
                errorMessage = "Couldn't refresh activity."
            }
        }
    }

    private func sortAndDeduplicate(items: [ActivityRow]) -> [ActivityRow] {
        var dedupedByID: [String: ActivityRow] = [:]
        for item in items {
            dedupedByID[item.id] = item
        }

        return dedupedByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id > rhs.id
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func normalizePubkey(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizedRelayURLs(_ relayURLs: [URL]) -> [URL] {
        var seen = Set<String>()
        var ordered: [URL] = []

        for relayURL in relayURLs {
            let normalized = relayURL.absoluteString.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            ordered.append(relayURL)
        }

        return ordered
    }
}
