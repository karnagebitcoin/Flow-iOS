import Foundation

@MainActor
final class HashtagFeedViewModel: ObservableObject {
    private struct VisibleItemsCacheKey: Equatable {
        let itemsRevision: Int
        let mode: FeedMode
        let hideNSFW: Bool
        let filterRevision: Int
    }

    @Published private(set) var items: [FeedItem] = [] {
        didSet {
            itemsRevision &+= 1
            clearVisibleItemsCache()
        }
    }
    @Published var mode: FeedMode = .posts {
        didSet { clearVisibleItemsCache() }
    }
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var errorMessage: String?

    let relayURL: URL
    let readRelayURLs: [URL]
    let normalizedHashtag: String

    private let pageSize: Int
    private let service: NostrFeedService
    private let requestKinds = [1, 1111, 1244]
    private static let fastHashtagFetchTimeout: TimeInterval = 3
    private static let fullHashtagFetchTimeout: TimeInterval = 8
    private static let fastHashtagRelayFetchMode: RelayFetchMode = .firstNonEmptyRelay
    private var oldestCreatedAt: Int?
    private var hasReachedEnd = false
    private var hasLoadedInitialState = false
    private var itemHydrationTask: Task<Void, Never>?
    private var relayExpansionTask: Task<Void, Never>?
    private var itemsRevision = 0
    private var visibleItemsCacheKey: VisibleItemsCacheKey?
    private var visibleItemsCache: [FeedItem] = []

    private static let supplementalRelayURLs: [URL] = [
        URL(string: "wss://relay.damus.io/"),
        URL(string: "wss://nos.lol/"),
        URL(string: "wss://relay.nostr.band/"),
        URL(string: "wss://nostr.mom/")
    ].compactMap { $0 }

    init(
        hashtag: String,
        relayURL: URL,
        readRelayURLs: [URL]? = nil,
        pageSize: Int = 70,
        service: NostrFeedService = NostrFeedService()
    ) {
        let sharedReadRelays = RelaySettingsStore.shared.readRelayURLs
        let normalizedReadRelays = Self.normalizedRelayURLs(
            readRelayURLs ?? (sharedReadRelays.isEmpty ? [relayURL] : sharedReadRelays)
        )

        self.readRelayURLs = normalizedReadRelays.isEmpty ? [relayURL] : normalizedReadRelays
        self.relayURL = self.readRelayURLs.first ?? relayURL
        self.normalizedHashtag = hashtag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .lowercased()
        self.pageSize = pageSize
        self.service = service
    }

    deinit {
        itemHydrationTask?.cancel()
        relayExpansionTask?.cancel()
    }

    var relayLabel: String {
        if readRelayURLs.count > 1 {
            return "\(readRelayURLs.count) relays"
        }
        return relayURL.host() ?? relayURL.absoluteString
    }

    var visibleItems: [FeedItem] {
        let key = VisibleItemsCacheKey(
            itemsRevision: itemsRevision,
            mode: mode,
            hideNSFW: AppSettingsStore.shared.hideNSFWContent,
            filterRevision: MuteStore.shared.filterRevision
        )

        if visibleItemsCacheKey == key {
            return visibleItemsCache
        }

        let hideNSFW = AppSettingsStore.shared.hideNSFWContent
        let filtered = items.filter { item in
            if MuteStore.shared.shouldHideAny(item.moderationEvents) {
                return false
            }
            if hideNSFW && item.moderationEvents.contains(where: { $0.containsNSFWHashtag }) {
                return false
            }
            switch mode {
            case .posts where item.displayEvent.isReplyNote:
                return false
            default:
                return true
            }
        }

        visibleItemsCacheKey = key
        visibleItemsCache = filtered
        return filtered
    }

    private var muteFilterSnapshot: MuteFilterSnapshot {
        MuteStore.shared.filterSnapshot
    }

    func loadIfNeeded() async {
        guard !hasLoadedInitialState else { return }
        hasLoadedInitialState = true
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        guard !normalizedHashtag.isEmpty else {
            items = []
            errorMessage = "Missing hashtag."
            return
        }

        isLoading = true
        errorMessage = nil
        hasReachedEnd = false
        oldestCreatedAt = nil
        itemHydrationTask?.cancel()
        relayExpansionTask?.cancel()
        itemHydrationTask = nil

        defer {
            isLoading = false
        }

        do {
            let fetched = try await fetchInitialHashtagPage()
            items = pruneMutedItems(fetched)
            oldestCreatedAt = items.last?.event.createdAt ?? fetched.last?.event.createdAt
            hasReachedEnd = fetched.count < pageSize
            scheduleItemHydration(for: items)
            scheduleRelayExpansionIfNeeded()
        } catch {
            if items.isEmpty {
                errorMessage = "Couldn't load #\(normalizedHashtag) right now."
            } else {
                errorMessage = "Couldn't refresh #\(normalizedHashtag)."
            }
        }
    }

    func loadMoreIfNeeded(currentItem: FeedItem) async {
        guard !isLoading, !isLoadingMore, !hasReachedEnd else { return }
        guard let lastVisibleID = visibleItems.last?.id, lastVisibleID == currentItem.id else { return }

        let until = max((oldestCreatedAt ?? Int(Date().timeIntervalSince1970)) - 1, 0)
        guard until > 0 else { return }

        isLoadingMore = true
        itemHydrationTask?.cancel()
        relayExpansionTask?.cancel()
        itemHydrationTask = nil
        defer {
            isLoadingMore = false
        }

        do {
            let fetched = try await service.fetchHashtagFeed(
                relayURLs: hashtagRelayURLs,
                hashtag: normalizedHashtag,
                kinds: requestKinds,
                limit: pageSize,
                until: until,
                hydrationMode: .cachedProfilesOnly,
                fetchTimeout: Self.fullHashtagFetchTimeout,
                relayFetchMode: .allRelays,
                moderationSnapshot: muteFilterSnapshot
            )

            if fetched.isEmpty {
                hasReachedEnd = true
                return
            }

            oldestCreatedAt = fetched.last?.event.createdAt
            hasReachedEnd = fetched.count < pageSize
            mergeKeepingNewest(itemsToMerge: fetched)
            scheduleItemHydration(for: items)
        } catch {
            errorMessage = "Couldn't load more posts."
        }
    }

    private func mergeKeepingNewest(itemsToMerge: [FeedItem]) {
        var byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for item in itemsToMerge {
            byID[item.id] = item
        }
        items = pruneMutedItems(byID.values.sorted {
            if $0.event.createdAt == $1.event.createdAt {
                return $0.id > $1.id
            }
            return $0.event.createdAt > $1.event.createdAt
        })
    }

    private func pruneMutedItems(
        _ sourceItems: [FeedItem],
        snapshot: MuteFilterSnapshot? = nil
    ) -> [FeedItem] {
        let snapshot = snapshot ?? muteFilterSnapshot
        guard snapshot.hasAnyRules else { return sourceItems }

        return sourceItems.filter { item in
            !snapshot.shouldHideAny(in: item.moderationEvents)
        }
    }

    private func clearVisibleItemsCache() {
        visibleItemsCacheKey = nil
        visibleItemsCache = []
    }

    private func scheduleItemHydration(for sourceItems: [FeedItem]) {
        itemHydrationTask?.cancel()

        let events = sourceItems.map(\.event)
        guard !events.isEmpty else { return }
        let relayTargets = hashtagRelayURLs

        itemHydrationTask = Task { [weak self] in
            guard let self else { return }
            let hydrated = await self.service.buildFeedItems(
                relayURLs: relayTargets,
                events: events,
                hydrationMode: .full,
                moderationSnapshot: self.muteFilterSnapshot
            )
            guard !Task.isCancelled else { return }
            guard !hydrated.isEmpty else { return }

            await MainActor.run {
                self.mergeKeepingNewest(itemsToMerge: hydrated)
            }
        }
    }

    private func fetchInitialHashtagPage() async throws -> [FeedItem] {
        let fastFetched = try await service.fetchHashtagFeed(
            relayURLs: hashtagRelayURLs,
            hashtag: normalizedHashtag,
            kinds: requestKinds,
            limit: pageSize,
            until: nil,
            hydrationMode: .cachedProfilesOnly,
            fetchTimeout: Self.fastHashtagFetchTimeout,
            relayFetchMode: Self.fastHashtagRelayFetchMode,
            moderationSnapshot: muteFilterSnapshot
        )

        if !fastFetched.isEmpty {
            return fastFetched
        }

        return try await service.fetchHashtagFeed(
            relayURLs: hashtagRelayURLs,
            hashtag: normalizedHashtag,
            kinds: requestKinds,
            limit: pageSize,
            until: nil,
            hydrationMode: .cachedProfilesOnly,
            fetchTimeout: Self.fullHashtagFetchTimeout,
            relayFetchMode: .allRelays,
            moderationSnapshot: muteFilterSnapshot
        )
    }

    private func scheduleRelayExpansionIfNeeded() {
        guard !hashtagRelayURLs.isEmpty else { return }

        relayExpansionTask?.cancel()
        relayExpansionTask = Task { [weak self] in
            guard let self else { return }

            let expanded = try? await self.service.fetchHashtagFeed(
                relayURLs: self.hashtagRelayURLs,
                hashtag: self.normalizedHashtag,
                kinds: self.requestKinds,
                limit: self.pageSize,
                until: nil,
                hydrationMode: .cachedProfilesOnly,
                fetchTimeout: Self.fullHashtagFetchTimeout,
                relayFetchMode: .allRelays,
                moderationSnapshot: self.muteFilterSnapshot
            )

            guard !Task.isCancelled else { return }
            guard let expanded, !expanded.isEmpty else { return }

            await MainActor.run {
                self.mergeKeepingNewest(itemsToMerge: expanded)
                self.oldestCreatedAt = self.items.last?.event.createdAt
                self.hasReachedEnd = expanded.count < self.pageSize && self.items.count <= expanded.count
                self.scheduleItemHydration(for: self.items)
            }
        }
    }

    private var hashtagRelayURLs: [URL] {
        Self.normalizedRelayURLs(readRelayURLs + Self.supplementalRelayURLs)
    }

    private static func normalizedRelayURLs(_ relayURLs: [URL]) -> [URL] {
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
