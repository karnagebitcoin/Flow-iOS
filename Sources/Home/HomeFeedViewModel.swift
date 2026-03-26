import Foundation

enum FeedMode: String, CaseIterable, Identifiable {
    case posts
    case postsAndReplies

    var id: String { rawValue }

    var title: String {
        switch self {
        case .posts:
            return "Notes"
        case .postsAndReplies:
            return "Replies"
        }
    }
}

enum HomePrimaryFeedSource: Identifiable, Hashable {
    case network
    case following
    case interests
    case news
    case custom(String)
    case hashtag(String)

    var id: String {
        switch self {
        case .network:
            return "network"
        case .following:
            return "following"
        case .interests:
            return "interests"
        case .news:
            return "news"
        case .custom(let feedID):
            return "custom:\(Self.normalizeCustomFeedID(feedID))"
        case .hashtag(let hashtag):
            return "hashtag:\(Self.normalizeHashtag(hashtag))"
        }
    }

    var storageValue: String {
        switch self {
        case .network:
            return "network"
        case .following:
            return "following"
        case .interests:
            return "interests"
        case .news:
            return "news"
        case .custom(let feedID):
            return "custom:\(Self.normalizeCustomFeedID(feedID))"
        case .hashtag(let hashtag):
            return "hashtag:\(Self.normalizeHashtag(hashtag))"
        }
    }

    init?(storageValue: String) {
        let normalized = storageValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized == "network" || normalized == "myrelays" {
            self = .network
            return
        }
        if normalized == "following" {
            self = .following
            return
        }
        if normalized == "interests" {
            self = .interests
            return
        }
        if normalized == "news" {
            self = .news
            return
        }
        if normalized.hasPrefix("custom:") {
            let value = String(normalized.dropFirst("custom:".count))
            let feedID = Self.normalizeCustomFeedID(value)
            guard !feedID.isEmpty else { return nil }
            self = .custom(feedID)
            return
        }
        if normalized.hasPrefix("hashtag:") {
            let value = String(normalized.dropFirst("hashtag:".count))
            let hashtag = Self.normalizeHashtag(value)
            guard !hashtag.isEmpty else { return nil }
            self = .hashtag(hashtag)
            return
        }
        return nil
    }

    static func normalizeHashtag(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .lowercased()
    }

    static func normalizeCustomFeedID(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

@MainActor
final class HomeFeedViewModel: ObservableObject {
    private struct NewsFeedPageResult {
        let items: [FeedItem]
        let hadMoreAvailable: Bool
    }

    private struct VisibleItemsCacheKey: Equatable {
        let itemsRevision: Int
        let mode: FeedMode
        let showKinds: [Int]
        let mediaOnly: Bool
        let hideNSFW: Bool
        let filterRevision: Int
        let mutedConversationRevision: Int
        let ignoreMediaOnly: Bool
    }

    private struct LiveSubscriptionTarget: Sendable {
        let relayURL: URL
        let filter: NostrFilter
        let signature: String
    }

    @Published private(set) var items: [FeedItem] = [] {
        didSet {
            itemsRevision &+= 1
            clearVisibleItemsCache()
        }
    }
    @Published private(set) var bufferedNewItems: [FeedItem] = []
    @Published var mode: FeedMode = .posts {
        didSet { clearVisibleItemsCache() }
    }
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isBootstrappingFeed = false
    @Published private(set) var showKinds: [Int] {
        didSet { clearVisibleItemsCache() }
    }
    @Published private(set) var mediaOnly: Bool {
        didSet { clearVisibleItemsCache() }
    }
    @Published var feedSource: HomePrimaryFeedSource = .network
    @Published private(set) var interestHashtags: [String] = []
    @Published private(set) var favoriteHashtags: [String] = []
    @Published private(set) var customFeeds: [CustomFeedDefinition] = []
    @Published var errorMessage: String?
    @Published private(set) var readRelayURLs: [URL]
    @Published private(set) var relayURL: URL

    private let pageSize: Int
    private let service: NostrFeedService
    private let liveSubscriber: NostrLiveFeedSubscriber
    private let recentFeedStore: RecentFeedStore
    private let filterStore: HomeFeedFilterStore

    private let recentFeedMaxEvents = 120
    private let assetPrefetchItemCount = 24
    private let feedSourceStorage = UserDefaults.standard
    private let feedSourceStoragePrefix = "homeFeedSourcePreference"
    private let mutedConversationStoragePrefix = "homeFeedMutedConversations"
    private static let fastHomeFetchTimeout: TimeInterval = 3
    private static let fastHomeRelayFetchMode: RelayFetchMode = .firstNonEmptyRelay
    private static let newsFallbackRelayURL = URL(string: "wss://news.utxo.one")!
    private static let customFeedSupplementalRelayURLs: [URL] = [
        URL(string: "wss://relay.damus.io/"),
        URL(string: "wss://nos.lol/"),
        URL(string: "wss://relay.nostr.band/"),
        URL(string: "wss://nostr.mom/"),
        URL(string: "wss://search.nos.today/")
    ].compactMap { $0 }

    private var oldestCreatedAt: Int?
    private var hasReachedEnd = false
    private var isSilentRefreshing = false
    private var needsRefreshAfterCurrentRequest = false
    private var knownEventIDs = Set<String>()
    private var followingPubkeys: [String] = []
    private var currentUserPubkey: String?
    private var mutedConversationIDs = Set<String>() {
        didSet {
            mutedConversationRevision &+= 1
            clearVisibleItemsCache()
        }
    }
    private var itemsRevision = 0
    private var mutedConversationRevision = 0
    private var visibleItemsCacheKey: VisibleItemsCacheKey?
    private var visibleItemsCache: [FeedItem] = []

    private var liveSubscriptionKinds: [Int] = []
    private var liveSubscriptionSource: HomePrimaryFeedSource?
    private var liveSubscriptionConfigurationSignature: String?
    private var liveUpdatesTask: Task<Void, Never>?
    private var resetFeedTask: Task<Void, Never>?
    private var itemHydrationTask: Task<Void, Never>?
    private var latestRefreshRequestID = 0

    init(
        relayURL: URL,
        readRelayURLs: [URL]? = nil,
        pageSize: Int = 70,
        service: NostrFeedService = NostrFeedService(),
        liveSubscriber: NostrLiveFeedSubscriber = NostrLiveFeedSubscriber(),
        recentFeedStore: RecentFeedStore = .shared,
        filterStore: HomeFeedFilterStore = .shared
    ) {
        let defaults = filterStore.loadDefaults()

        let normalizedReadRelays = Self.normalizedRelayURLs(readRelayURLs ?? [relayURL])
        let initialReadRelayURLs = normalizedReadRelays.isEmpty ? [relayURL] : normalizedReadRelays
        let initialRelayURL = initialReadRelayURLs.first ?? relayURL

        self.readRelayURLs = initialReadRelayURLs
        self.relayURL = initialRelayURL
        self.pageSize = pageSize
        self.service = service
        self.liveSubscriber = liveSubscriber
        self.recentFeedStore = recentFeedStore
        self.filterStore = filterStore
        self.showKinds = defaults.showKinds
        self.mediaOnly = defaults.mediaOnly
    }

    deinit {
        liveUpdatesTask?.cancel()
        resetFeedTask?.cancel()
        itemHydrationTask?.cancel()
    }

    var feedSourceOptions: [HomePrimaryFeedSource] {
        let hashtagSources = favoriteHashtags.map { HomePrimaryFeedSource.hashtag($0) }
        let interestSources: [HomePrimaryFeedSource] = interestHashtags.isEmpty ? [] : [.interests]
        let customSources = customFeeds.map { HomePrimaryFeedSource.custom($0.id) }
        return [.network, .following] + interestSources + [.news] + customSources + hashtagSources
    }

    var kindFilterOptions: [FeedKindFilterOption] {
        FeedKindFilters.options
    }

    var visibleItems: [FeedItem] {
        filteredMainItems()
    }

    private var muteFilterSnapshot: MuteFilterSnapshot {
        MuteStore.shared.filterSnapshot
    }

    var visibleBufferedNewItemsCount: Int {
        filterVisibleItems(bufferedNewItems).count
    }

    var isUsingCustomFilters: Bool {
        !FeedKindFilters.isSameSelection(showKinds, FeedKindFilters.allOptionKinds) || mediaOnly
    }

    var shouldShowFilteredOutState: Bool {
        !isShowingLoadingPlaceholder && !items.isEmpty && visibleItems.isEmpty && errorMessage == nil
    }

    var mediaOnlyFilteredOutAll: Bool {
        mediaOnly && visibleItems.isEmpty && !filteredMainItems(ignoreMediaOnly: true).isEmpty
    }

    var isShowingLoadingPlaceholder: Bool {
        (isLoading || isBootstrappingFeed) && items.isEmpty
    }

    var relayDisplayName: String {
        if readRelayURLs.count > 1 {
            return "\(readRelayURLs.count) relays"
        }
        return relayURL.host() ?? relayURL.absoluteString
    }

    var followingFeedHasNoFollowings: Bool {
        feedSource == .following && !isLoading && followingPubkeys.isEmpty && errorMessage == nil
    }

    var interestsFeedHasNoHashtags: Bool {
        feedSource == .interests && !isLoading && interestHashtags.isEmpty && errorMessage == nil
    }

    var networkFeedHasNoTrustedAuthors: Bool { false }

    var filteredOutMessage: String {
        if mediaOnlyFilteredOutAll {
            return "This feed has posts, but the media-only filter is hiding them."
        }
        return "No posts match the current filters."
    }

    private var recentFeedKey: String {
        let sourceRelayURLs = relayURLs(for: feedSource)
        let requestKinds = feedKinds(for: feedSource)
        let filter = NostrFilter(
            kinds: requestKinds,
            limit: pageSize
        )

        let sourceDescriptor: String
        switch feedSource {
        case .network:
            sourceDescriptor = "network"
        case .following:
            sourceDescriptor = "following:\(currentUserPubkey ?? "anonymous")"
        case .interests:
            sourceDescriptor = "interests"
        case .news:
            sourceDescriptor = "news"
        case .custom(let feedID):
            if let feed = customFeedDefinition(id: feedID) {
                sourceDescriptor = "custom:\(feedID):\(feed.cacheSignature)"
            } else {
                sourceDescriptor = "custom:\(feedID)"
            }
        case .hashtag(let hashtag):
            sourceDescriptor = "hashtag:\(HomePrimaryFeedSource.normalizeHashtag(hashtag))"
        }

        let relaySignature = sourceRelayURLs
            .map { $0.absoluteString.lowercased() }
            .joined(separator: ",")
        return "recentFeed:\(sourceDescriptor):\(relaySignature):\(generateTimelineKey(relayURL: sourceRelayURLs.first ?? relayURL, filter: filter))"
    }

    func updateCurrentUserPubkey(_ pubkey: String?) {
        let normalized = pubkey?.lowercased()
        guard currentUserPubkey != normalized else { return }

        currentUserPubkey = normalized
        mutedConversationIDs = loadMutedConversationIDs(pubkey: normalized)
        let preferredSource = loadFeedSourcePreference(pubkey: normalized)
        let resolvedPreferredSource = resolvedFeedSource(preferredSource)
        if feedSource != resolvedPreferredSource {
            feedSource = resolvedPreferredSource
        }

        resetFeedStateAndReload()
    }

    func updateFavoriteHashtags(_ hashtags: [String]) {
        let normalized = Self.normalizedFavoriteHashtags(hashtags)
        guard favoriteHashtags != normalized else { return }

        favoriteHashtags = normalized

        if case .hashtag(let selectedHashtag) = feedSource,
           !normalized.contains(HomePrimaryFeedSource.normalizeHashtag(selectedHashtag)) {
            feedSource = .network
            storeFeedSourcePreference(feedSource, pubkey: currentUserPubkey)
            resetFeedStateAndReload()
        }
    }

    func updateCustomFeeds(_ feeds: [CustomFeedDefinition]) {
        guard customFeeds != feeds else { return }

        let previousFeeds = customFeeds
        customFeeds = feeds

        guard case .custom(let selectedID) = feedSource else { return }

        guard let updatedSelection = customFeedDefinition(id: selectedID) else {
            feedSource = .network
            storeFeedSourcePreference(feedSource, pubkey: currentUserPubkey)
            resetFeedStateAndReload()
            return
        }

        let previousSelection = previousFeeds.first { $0.id == selectedID }
        if previousSelection != updatedSelection {
            resetFeedStateAndReload()
        }
    }

    func updateInterestHashtags(_ hashtags: [String]) {
        let normalized = Self.normalizedFavoriteHashtags(hashtags)
        guard interestHashtags != normalized else { return }

        interestHashtags = normalized

        if feedSource == .interests && normalized.isEmpty {
            feedSource = .network
            storeFeedSourcePreference(feedSource, pubkey: currentUserPubkey)
            resetFeedStateAndReload()
            return
        }

        if feedSource == .interests {
            Task {
                await refresh(silent: true)
            }
        }
    }

    func updateNetworkTrustedPubkeys(_ pubkeys: [String]) {
        // Network is relay-based again, so trusted-pubkey updates are ignored.
    }

    func muteConversation(_ conversationID: String) {
        let normalized = conversationID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return }
        guard mutedConversationIDs.insert(normalized).inserted else { return }

        persistMutedConversationIDs(pubkey: currentUserPubkey)
        items.removeAll { $0.event.referencesConversation(id: normalized) }
        bufferedNewItems.removeAll { $0.event.referencesConversation(id: normalized) }
        knownEventIDs = Set(items.map(\.id))
        knownEventIDs.formUnion(bufferedNewItems.map(\.id))
    }

    func selectFeedSource(_ source: HomePrimaryFeedSource) {
        let resolvedSource = resolvedFeedSource(source)
        guard feedSource != resolvedSource else { return }
        feedSource = resolvedSource
        storeFeedSourcePreference(resolvedSource, pubkey: currentUserPubkey)
        resetFeedStateAndReload()
    }

    func updateRelayURL(_ newRelayURL: URL) {
        updateReadRelayURLs([newRelayURL])
    }

    func updateReadRelayURLs(_ newReadRelayURLs: [URL]) {
        let normalized = Self.normalizedRelayURLs(newReadRelayURLs)
        guard !normalized.isEmpty else { return }

        let existing = readRelayURLs.map { $0.absoluteString.lowercased() }
        let next = normalized.map { $0.absoluteString.lowercased() }
        guard existing != next else {
            return
        }

        readRelayURLs = normalized
        relayURL = normalized[0]
        resetFeedStateAndReload()
    }

    func loadIfNeeded() async {
        if items.isEmpty {
            let loadedFromCache = await loadRecentFeedSnapshot()
            if loadedFromCache {
                startLiveUpdatesIfNeeded()
                await refresh(silent: true)
            } else {
                await refresh()
            }
        } else {
            startLiveUpdatesIfNeeded()
        }
    }

    func isKindGroupEnabled(_ option: FeedKindFilterOption) -> Bool {
        let selected = Set(showKinds)
        return option.kinds.allSatisfy { selected.contains($0) }
    }

    func toggleKindGroup(_ option: FeedKindFilterOption) {
        var selected = Set(showKinds)
        let group = Set(option.kinds)

        if group.isSubset(of: selected) {
            selected.subtract(group)
            guard !selected.isEmpty else { return }
        } else {
            selected.formUnion(group)
        }

        applyCurrentFilters(showKinds: Array(selected), mediaOnly: mediaOnly)
    }

    func selectAllKinds() {
        applyCurrentFilters(showKinds: FeedKindFilters.allOptionKinds, mediaOnly: mediaOnly)
    }

    func setMediaOnly(_ enabled: Bool) {
        applyCurrentFilters(showKinds: showKinds, mediaOnly: enabled)
    }

    func disableMediaOnlyFilter() {
        setMediaOnly(false)
    }

    func refresh(silent: Bool = false, force: Bool = false) async {
        if !force && (isLoading || isSilentRefreshing) {
            needsRefreshAfterCurrentRequest = true
            return
        }

        needsRefreshAfterCurrentRequest = false
        if force {
            isLoading = false
            isSilentRefreshing = false
        }
        latestRefreshRequestID += 1
        let refreshRequestID = latestRefreshRequestID
        let requestSource = feedSource
        let requestUserPubkey = currentUserPubkey
        let startedWithEmptyItems = items.isEmpty

        if silent {
            isSilentRefreshing = true
        } else {
            isLoading = true
        }
        errorMessage = nil
        hasReachedEnd = false
        oldestCreatedAt = nil
        itemHydrationTask?.cancel()
        itemHydrationTask = nil

        defer {
            if latestRefreshRequestID == refreshRequestID {
                if silent {
                    isSilentRefreshing = false
                } else {
                    isLoading = false
                }

                if requestSource == feedSource, requestUserPubkey == currentUserPubkey {
                    isBootstrappingFeed = false
                }

                if needsRefreshAfterCurrentRequest {
                    needsRefreshAfterCurrentRequest = false
                    Task { [weak self] in
                        await self?.refresh()
                    }
                }
            }
        }

        do {
            var fetched: [FeedItem]
            let requestRelayURLs = relayURLs(for: requestSource)
            let requestKinds = feedKinds(for: requestSource)
            let requestHydrationMode: FeedItemHydrationMode = .cachedProfilesOnly
            let requestFetchTimeout = Self.fastHomeFetchTimeout
            let requestRelayFetchMode = Self.fastHomeRelayFetchMode

            if requestSource != .following {
                startLiveUpdatesIfNeeded()
            }

            switch requestSource {
            case .network:
                followingPubkeys = []
                fetched = try await service.fetchFeed(
                    relayURLs: requestRelayURLs,
                    kinds: requestKinds,
                    limit: pageSize,
                    until: nil,
                    hydrationMode: requestHydrationMode,
                    fetchTimeout: requestFetchTimeout,
                    relayFetchMode: requestRelayFetchMode,
                    moderationSnapshot: muteFilterSnapshot
                )

            case .interests:
                followingPubkeys = []
                let interestPage = try await fetchInterestsFeedPage(
                    limit: pageSize,
                    until: nil,
                    hydrationMode: requestHydrationMode,
                    fetchTimeout: requestFetchTimeout,
                    relayFetchMode: requestRelayFetchMode,
                    moderationSnapshot: muteFilterSnapshot
                )
                fetched = interestPage.items
                hasReachedEnd = !interestPage.hadMoreAvailable

            case .news:
                followingPubkeys = []
                let newsPage = try await fetchNewsFeedPage(
                    limit: pageSize,
                    until: nil,
                    hydrationMode: requestHydrationMode,
                    fetchTimeout: requestFetchTimeout,
                    relayFetchMode: requestRelayFetchMode,
                    moderationSnapshot: muteFilterSnapshot
                )
                fetched = newsPage.items
                hasReachedEnd = !newsPage.hadMoreAvailable

            case .custom(let feedID):
                followingPubkeys = []
                guard let feed = customFeedDefinition(id: feedID) else {
                    fetched = []
                    hasReachedEnd = true
                    break
                }
                let customPage = try await fetchCustomFeedPage(
                    feed: feed,
                    kinds: requestKinds,
                    limit: pageSize,
                    until: nil,
                    hydrationMode: requestHydrationMode,
                    fetchTimeout: requestFetchTimeout,
                    relayFetchMode: requestRelayFetchMode,
                    moderationSnapshot: muteFilterSnapshot
                )
                fetched = customPage.items
                hasReachedEnd = !customPage.hadMoreAvailable

            case .hashtag(let hashtag):
                followingPubkeys = []
                fetched = try await service.fetchHashtagFeed(
                    relayURLs: requestRelayURLs,
                    hashtag: hashtag,
                    kinds: requestKinds,
                    limit: pageSize,
                    until: nil,
                    hydrationMode: requestHydrationMode,
                    fetchTimeout: requestFetchTimeout,
                    relayFetchMode: requestRelayFetchMode,
                    moderationSnapshot: muteFilterSnapshot
                )

            case .following:
                guard let requestUserPubkey else {
                    throw HomeFeedError.followingRequiresLogin
                }

                var followings = localFollowings()
                if followings.isEmpty {
                    followings = try await service.fetchFollowings(
                        relayURLs: requestRelayURLs,
                        pubkey: requestUserPubkey,
                        relayFetchMode: requestRelayFetchMode
                    )
                }

                if requestSource != feedSource || requestUserPubkey != currentUserPubkey {
                    guard latestRefreshRequestID == refreshRequestID else { return }
                    needsRefreshAfterCurrentRequest = true
                    return
                }

                followingPubkeys = followings

                if followings.isEmpty {
                    guard latestRefreshRequestID == refreshRequestID else { return }
                    items = []
                    bufferedNewItems = []
                    knownEventIDs = []
                    oldestCreatedAt = nil
                    hasReachedEnd = true
                    startLiveUpdatesIfNeeded(forceRestart: true)
                    await persistRecentFeedSnapshot(from: [])
                    return
                }

                startLiveUpdatesIfNeeded(forceRestart: true)

                fetched = try await service.fetchFollowingFeed(
                    relayURLs: requestRelayURLs,
                    authors: followings,
                    kinds: requestKinds,
                    limit: pageSize,
                    until: nil,
                    hydrationMode: requestHydrationMode,
                    fetchTimeout: requestFetchTimeout,
                    relayFetchMode: requestRelayFetchMode,
                    moderationSnapshot: muteFilterSnapshot
                )
            }

            if requestSource != feedSource || requestUserPubkey != currentUserPubkey {
                guard latestRefreshRequestID == refreshRequestID else { return }
                needsRefreshAfterCurrentRequest = true
                return
            }

            if requestSource != .news,
               !FeedKindFilters.isSameSelection(requestKinds, showKinds) {
                guard latestRefreshRequestID == refreshRequestID else { return }
                needsRefreshAfterCurrentRequest = true
                return
            }

            guard latestRefreshRequestID == refreshRequestID else { return }

            let mergedItems = pruneMutedItems(startedWithEmptyItems
                ? mergeItemArrays(primary: bufferedNewItems, secondary: fetched)
                : fetched)

            items = mergedItems
            bufferedNewItems = []
            knownEventIDs = Set(mergedItems.map(\.id))
            oldestCreatedAt = mergedItems.last?.event.createdAt ?? fetched.last?.event.createdAt
            if !usesCompositePagination(requestSource) {
                hasReachedEnd = fetched.count < pageSize
            }
            scheduleAssetPrefetch(for: mergedItems)
            startLiveUpdatesIfNeeded()
            await persistRecentFeedSnapshot(from: mergedItems)
            scheduleItemHydration(
                for: mergedItems,
                source: requestSource,
                userPubkey: requestUserPubkey
            )
        } catch {
            guard latestRefreshRequestID == refreshRequestID else { return }
            switch error {
            case HomeFeedError.followingRequiresLogin:
                errorMessage = "Sign in to view the Following feed."
            case HomeFeedError.networkRequiresLogin:
                errorMessage = "Sign in to view the Network feed."
            default:
                if items.isEmpty {
                    errorMessage = "Couldn't load the home feed. Pull to refresh and try again."
                } else {
                    errorMessage = "Couldn't refresh right now."
                }
            }
        }
    }

    func loadMoreIfNeeded(currentItem: FeedItem) async {
        guard !isLoading, !isLoadingMore, !hasReachedEnd else { return }
        guard let lastVisibleID = visibleItems.last?.id, lastVisibleID == currentItem.id else { return }

        let until = max((oldestCreatedAt ?? Int(Date().timeIntervalSince1970)) - 1, 0)
        guard until > 0 else { return }

        let requestSource = feedSource
        let requestUserPubkey = currentUserPubkey
        let requestHydrationMode: FeedItemHydrationMode = .cachedProfilesOnly
        let requestFetchTimeout = Self.fastHomeFetchTimeout
        let requestRelayFetchMode = Self.fastHomeRelayFetchMode

        isLoadingMore = true
        itemHydrationTask?.cancel()
        itemHydrationTask = nil
        defer {
            isLoadingMore = false
        }

        do {
            var fetched: [FeedItem]
            let requestRelayURLs = relayURLs(for: requestSource)
            let requestKinds = feedKinds(for: requestSource)

            switch requestSource {
            case .network:
                fetched = try await service.fetchFeed(
                    relayURLs: requestRelayURLs,
                    kinds: requestKinds,
                    limit: pageSize,
                    until: until,
                    hydrationMode: requestHydrationMode,
                    fetchTimeout: requestFetchTimeout,
                    relayFetchMode: requestRelayFetchMode,
                    moderationSnapshot: muteFilterSnapshot
                )

            case .interests:
                let interestPage = try await fetchInterestsFeedPage(
                    limit: pageSize,
                    until: until,
                    hydrationMode: requestHydrationMode,
                    fetchTimeout: requestFetchTimeout,
                    relayFetchMode: requestRelayFetchMode,
                    moderationSnapshot: muteFilterSnapshot
                )
                fetched = interestPage.items
                hasReachedEnd = !interestPage.hadMoreAvailable

            case .news:
                let newsPage = try await fetchNewsFeedPage(
                    limit: pageSize,
                    until: until,
                    hydrationMode: requestHydrationMode,
                    fetchTimeout: requestFetchTimeout,
                    relayFetchMode: requestRelayFetchMode,
                    moderationSnapshot: muteFilterSnapshot
                )
                fetched = newsPage.items
                hasReachedEnd = !newsPage.hadMoreAvailable

            case .custom(let feedID):
                guard let feed = customFeedDefinition(id: feedID) else {
                    hasReachedEnd = true
                    return
                }
                let customPage = try await fetchCustomFeedPage(
                    feed: feed,
                    kinds: requestKinds,
                    limit: pageSize,
                    until: until,
                    hydrationMode: requestHydrationMode,
                    fetchTimeout: requestFetchTimeout,
                    relayFetchMode: requestRelayFetchMode,
                    moderationSnapshot: muteFilterSnapshot
                )
                fetched = customPage.items
                hasReachedEnd = !customPage.hadMoreAvailable

            case .hashtag(let hashtag):
                fetched = try await service.fetchHashtagFeed(
                    relayURLs: requestRelayURLs,
                    hashtag: hashtag,
                    kinds: requestKinds,
                    limit: pageSize,
                    until: until,
                    hydrationMode: requestHydrationMode,
                    fetchTimeout: requestFetchTimeout,
                    relayFetchMode: requestRelayFetchMode,
                    moderationSnapshot: muteFilterSnapshot
                )

            case .following:
                guard !followingPubkeys.isEmpty else {
                    hasReachedEnd = true
                    return
                }

                fetched = try await service.fetchFollowingFeed(
                    relayURLs: requestRelayURLs,
                    authors: followingPubkeys,
                    kinds: requestKinds,
                    limit: pageSize,
                    until: until,
                    hydrationMode: requestHydrationMode,
                    fetchTimeout: requestFetchTimeout,
                    relayFetchMode: requestRelayFetchMode,
                    moderationSnapshot: muteFilterSnapshot
                )
            }

            if requestSource != feedSource {
                return
            }

            if requestSource != .news,
               !FeedKindFilters.isSameSelection(requestKinds, showKinds) {
                return
            }

            if fetched.isEmpty {
                hasReachedEnd = true
                return
            }

            oldestCreatedAt = fetched.last?.event.createdAt
            if !usesCompositePagination(requestSource) {
                hasReachedEnd = fetched.count < pageSize
            }
            mergeKeepingNewest(itemsToMerge: fetched)
            await persistRecentFeedSnapshot(from: items)
            scheduleItemHydration(
                for: items,
                source: requestSource,
                userPubkey: requestUserPubkey
            )
        } catch {
            errorMessage = "Couldn't load more posts."
        }
    }

    func showBufferedNewItems() {
        guard !bufferedNewItems.isEmpty else { return }
        mergeKeepingNewest(itemsToMerge: bufferedNewItems)
        bufferedNewItems.removeAll()
        Task { [weak self] in
            guard let self else { return }
            await self.persistRecentFeedSnapshot(from: self.items)
        }
    }

    private func applyCurrentFilters(showKinds: [Int], mediaOnly: Bool) {
        let normalizedKinds = FeedKindFilters.normalizedKinds(showKinds)
        let kindsChanged = !FeedKindFilters.isSameSelection(normalizedKinds, self.showKinds)
        let mediaChanged = mediaOnly != self.mediaOnly

        guard kindsChanged || mediaChanged else { return }

        self.showKinds = normalizedKinds
        self.mediaOnly = mediaOnly
        filterStore.saveDefaults(showKinds: normalizedKinds, mediaOnly: mediaOnly)

        if kindsChanged {
            self.bufferedNewItems.removeAll()
            self.liveUpdatesTask?.cancel()
            self.liveUpdatesTask = nil
            self.liveSubscriptionKinds = []
            self.liveSubscriptionSource = nil
            self.liveSubscriptionConfigurationSignature = nil

            Task { [weak self] in
                guard let self else { return }
                let loadedFromCache = await self.loadRecentFeedSnapshot()
                self.startLiveUpdatesIfNeeded(forceRestart: true)
                if loadedFromCache {
                    await self.refresh(silent: true)
                } else {
                    await self.refresh()
                }
            }
        }
    }

    private func resetFeedStateAndReload() {
        isBootstrappingFeed = true
        bufferedNewItems.removeAll()
        items.removeAll()
        knownEventIDs.removeAll()
        oldestCreatedAt = nil
        hasReachedEnd = false
        followingPubkeys = []
        errorMessage = nil

        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil
        itemHydrationTask?.cancel()
        itemHydrationTask = nil
        liveSubscriptionKinds = []
        liveSubscriptionSource = nil
        liveSubscriptionConfigurationSignature = nil

        resetFeedTask?.cancel()
        resetFeedTask = Task { [weak self] in
            guard let self else { return }
            let loadedFromCache = await self.loadRecentFeedSnapshot()
            guard !Task.isCancelled else { return }
            self.startLiveUpdatesIfNeeded(forceRestart: true)
            if loadedFromCache {
                self.isBootstrappingFeed = false
                await self.refresh(silent: true, force: true)
            } else {
                await self.refresh(force: true)
            }
        }
    }

    private func startLiveUpdatesIfNeeded(forceRestart: Bool = false) {
        let liveKinds = feedKinds(for: feedSource)
        guard !liveKinds.isEmpty else { return }
        let source = feedSource
        let targets = liveSubscriptionTargets(for: source, kinds: liveKinds)
        guard !targets.isEmpty else {
            liveUpdatesTask?.cancel()
            liveUpdatesTask = nil
            liveSubscriptionKinds = []
            liveSubscriptionSource = source
            liveSubscriptionConfigurationSignature = nil
            return
        }

        let configurationSignature = targets
            .map(\.signature)
            .sorted()
            .joined(separator: "||")

        if !forceRestart,
           liveUpdatesTask != nil,
           FeedKindFilters.isSameSelection(liveKinds, liveSubscriptionKinds),
           liveSubscriptionSource == source,
           liveSubscriptionConfigurationSignature == configurationSignature {
            return
        }

        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil
        liveSubscriptionKinds = liveKinds
        liveSubscriptionSource = source
        liveSubscriptionConfigurationSignature = configurationSignature

        liveUpdatesTask = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                for target in targets {
                    group.addTask { [weak self] in
                        guard let self else { return }
                        await self.liveSubscriber.run(
                            relayURL: target.relayURL,
                            filter: target.filter,
                            onNewEvent: { [weak self] event in
                                guard let self else { return }
                                await self.handleLiveEvent(event)
                            },
                            onStatus: { [weak self] _ in
                                guard let self else { return }
                                await self.handleLiveStatus()
                            }
                        )
                    }
                }
                await group.waitForAll()
            }
        }
    }

    private func handleLiveStatus() async {
        // Keep status lightweight per HIG feedback guidance.
    }

    private func handleLiveEvent(_ event: NostrEvent) async {
        guard feedKinds(for: feedSource).contains(event.kind) else { return }
        guard !knownEventIDs.contains(event.id) else { return }

        let hydrated = await service.buildFeedItems(
            relayURLs: hydrationRelayURLs(for: feedSource),
            events: [event],
            moderationSnapshot: muteFilterSnapshot
        )
        guard let item = hydrated.first else { return }
        guard !knownEventIDs.contains(item.id) else { return }

        knownEventIDs.insert(item.id)
        bufferedNewItems = mergeItemArrays(
            primary: [item],
            secondary: bufferedNewItems
        )
        scheduleAssetPrefetch(for: [item])
    }

    private func mergeKeepingNewest(itemsToMerge: [FeedItem]) {
        items = pruneMutedItems(mergeItemArrays(primary: itemsToMerge, secondary: items))
        scheduleAssetPrefetch(for: items)

        let currentlyVisibleIDs = Set(items.map(\.id))
        bufferedNewItems.removeAll { currentlyVisibleIDs.contains($0.id) }

        knownEventIDs = currentlyVisibleIDs
        knownEventIDs.formUnion(bufferedNewItems.map(\.id))
    }

    private func liveSubscriptionTargets(
        for source: HomePrimaryFeedSource,
        kinds: [Int]
    ) -> [LiveSubscriptionTarget] {
        switch source {
        case .network:
            return subscriptionTargets(
                relayURLs: relayURLs(for: .network),
                filter: NostrFilter(kinds: kinds, limit: 100),
                scopeSignature: "network"
            )

        case .interests:
            let hashtags = configuredInterestHashtags()
            guard !hashtags.isEmpty else { return [] }
            return subscriptionTargets(
                relayURLs: relayURLs(for: .interests),
                filter: NostrFilter(kinds: kinds, limit: 100, tagFilters: ["t": hashtags]),
                scopeSignature: "interests:\(hashtags.joined(separator: ","))"
            )

        case .news:
            var targets: [LiveSubscriptionTarget] = []

            let newsRelayTargets = relayURLs(for: .news)
            targets.append(contentsOf: subscriptionTargets(
                relayURLs: newsRelayTargets,
                filter: NostrFilter(kinds: [1], limit: 100),
                scopeSignature: "news-relays"
            ))

            let hydrationTargets = hydrationRelayURLs(for: .news)
            let authors = Array(configuredNewsAuthorPubkeys().prefix(400))
            if !authors.isEmpty {
                targets.append(contentsOf: subscriptionTargets(
                    relayURLs: hydrationTargets,
                    filter: NostrFilter(authors: authors, kinds: [1], limit: 100),
                    scopeSignature: "news-authors:\(authors.joined(separator: ","))"
                ))
            }

            let hashtags = configuredNewsHashtags()
            if !hashtags.isEmpty {
                targets.append(contentsOf: subscriptionTargets(
                    relayURLs: hydrationTargets,
                    filter: NostrFilter(kinds: [1], limit: 100, tagFilters: ["t": hashtags]),
                    scopeSignature: "news-hashtags:\(hashtags.joined(separator: ","))"
                ))
            }

            return deduplicatedSubscriptionTargets(targets)

        case .custom(let feedID):
            guard let feed = customFeedDefinition(id: feedID) else { return [] }

            var targets: [LiveSubscriptionTarget] = []
            let relayTargets = relayURLs(for: source)

            let authors = Array(feed.authorPubkeys.prefix(400))
            if !authors.isEmpty {
                targets.append(contentsOf: subscriptionTargets(
                    relayURLs: relayTargets,
                    filter: NostrFilter(authors: authors, kinds: kinds, limit: 100),
                    scopeSignature: "custom-authors:\(feedID):\(authors.joined(separator: ","))"
                ))
            }

            let hashtags = Array(feed.hashtags.prefix(40))
            if !hashtags.isEmpty {
                targets.append(contentsOf: subscriptionTargets(
                    relayURLs: relayTargets,
                    filter: NostrFilter(kinds: kinds, limit: 100, tagFilters: ["t": hashtags]),
                    scopeSignature: "custom-hashtags:\(feedID):\(hashtags.joined(separator: ","))"
                ))
            }

            return deduplicatedSubscriptionTargets(targets)

        case .hashtag(let hashtag):
            let normalizedHashtag = HomePrimaryFeedSource.normalizeHashtag(hashtag)
            guard !normalizedHashtag.isEmpty else { return [] }
            return subscriptionTargets(
                relayURLs: relayURLs(for: source),
                filter: NostrFilter(kinds: kinds, limit: 100, tagFilters: ["t": [normalizedHashtag]]),
                scopeSignature: "hashtag:\(normalizedHashtag)"
            )

        case .following:
            let liveAuthors = Array(followingPubkeys.prefix(400)).sorted()
            guard !liveAuthors.isEmpty else { return [] }
            return subscriptionTargets(
                relayURLs: relayURLs(for: .following),
                filter: NostrFilter(authors: liveAuthors, kinds: kinds, limit: 100),
                scopeSignature: "following:\(liveAuthors.joined(separator: ","))"
            )
        }
    }

    private func subscriptionTargets(
        relayURLs: [URL],
        filter: NostrFilter,
        scopeSignature: String
    ) -> [LiveSubscriptionTarget] {
        Self.normalizedRelayURLs(relayURLs).map { relayURL in
            LiveSubscriptionTarget(
                relayURL: relayURL,
                filter: filter,
                signature: "\(scopeSignature)|\(relayURL.absoluteString.lowercased())"
            )
        }
    }

    private func deduplicatedSubscriptionTargets(_ targets: [LiveSubscriptionTarget]) -> [LiveSubscriptionTarget] {
        var seen = Set<String>()
        var ordered: [LiveSubscriptionTarget] = []

        for target in targets {
            guard seen.insert(target.signature).inserted else { continue }
            ordered.append(target)
        }

        return ordered
    }

    private func mergeItemArrays(primary: [FeedItem], secondary: [FeedItem]) -> [FeedItem] {
        var byID: [String: FeedItem] = Dictionary(uniqueKeysWithValues: secondary.map { ($0.id, $0) })

        for item in primary {
            byID[item.id] = item
        }

        return byID.values.sorted {
            if $0.event.createdAt == $1.event.createdAt {
                return $0.id > $1.id
            }
            return $0.event.createdAt > $1.event.createdAt
        }
    }

    private func filterVisibleItems(_ source: [FeedItem], ignoreMediaOnly: Bool = false) -> [FeedItem] {
        let allowedKinds = Set(showKinds)
        let hideNSFW = AppSettingsStore.shared.hideNSFWContent

        return source.filter { item in
            if mutedConversationIDs.contains(item.displayEvent.conversationID) {
                return false
            }

            if MuteStore.shared.shouldHideAny(item.moderationEvents) {
                return false
            }

            if hideNSFW && item.moderationEvents.contains(where: { $0.containsNSFWHashtag }) {
                return false
            }

            if !allowedKinds.contains(item.event.kind) {
                return false
            }

            switch mode {
            case .posts where item.displayEvent.isReplyNote:
                return false
            default:
                break
            }

            if !ignoreMediaOnly && mediaOnly && !item.displayEvent.hasMedia {
                return false
            }

            return true
        }
    }

    private func pruneMutedItems(
        _ source: [FeedItem],
        snapshot: MuteFilterSnapshot? = nil
    ) -> [FeedItem] {
        let snapshot = snapshot ?? muteFilterSnapshot
        guard snapshot.hasAnyRules else { return source }

        return source.filter { item in
            !snapshot.shouldHideAny(in: item.moderationEvents)
        }
    }

    private func filteredMainItems(ignoreMediaOnly: Bool = false) -> [FeedItem] {
        let key = VisibleItemsCacheKey(
            itemsRevision: itemsRevision,
            mode: mode,
            showKinds: showKinds,
            mediaOnly: mediaOnly,
            hideNSFW: AppSettingsStore.shared.hideNSFWContent,
            filterRevision: MuteStore.shared.filterRevision,
            mutedConversationRevision: mutedConversationRevision,
            ignoreMediaOnly: ignoreMediaOnly
        )

        if visibleItemsCacheKey == key {
            return visibleItemsCache
        }

        let filtered = filterVisibleItems(items, ignoreMediaOnly: ignoreMediaOnly)
        visibleItemsCacheKey = key
        visibleItemsCache = filtered
        return filtered
    }

    private func clearVisibleItemsCache() {
        visibleItemsCacheKey = nil
        visibleItemsCache = []
    }

    private func loadRecentFeedSnapshot() async -> Bool {
        guard let cachedEvents = await recentFeedStore.getRecentFeed(key: recentFeedKey),
              !cachedEvents.isEmpty else {
            return false
        }

        let hydrated = await service.buildFeedItems(
            relayURLs: hydrationRelayURLs(for: feedSource),
            events: cachedEvents.sorted(by: { $0.createdAt > $1.createdAt }),
            hydrationMode: .cachedProfilesOnly,
            moderationSnapshot: muteFilterSnapshot
        )
        let prunedHydrated = pruneMutedItems(hydrated)
        guard !prunedHydrated.isEmpty else { return false }

        items = prunedHydrated
        bufferedNewItems = []
        knownEventIDs = Set(prunedHydrated.map(\.id))
        oldestCreatedAt = prunedHydrated.last?.event.createdAt
        hasReachedEnd = false
        scheduleAssetPrefetch(for: prunedHydrated)
        return true
    }

    private func persistRecentFeedSnapshot(from source: [FeedItem]) async {
        let snapshot = Array(source.prefix(recentFeedMaxEvents)).map(\.event)
        await recentFeedStore.putRecentFeed(key: recentFeedKey, events: snapshot)
    }

    private func loadFeedSourcePreference(pubkey: String?) -> HomePrimaryFeedSource {
        let key = feedSourceStorageKey(pubkey: pubkey)
        guard let raw = feedSourceStorage.string(forKey: key),
              let source = HomePrimaryFeedSource(storageValue: raw) else {
            return .network
        }
        return source
    }

    private func storeFeedSourcePreference(_ source: HomePrimaryFeedSource, pubkey: String?) {
        let key = feedSourceStorageKey(pubkey: pubkey)
        feedSourceStorage.set(source.storageValue, forKey: key)
    }

    private func feedSourceStorageKey(pubkey: String?) -> String {
        "\(feedSourceStoragePrefix).\(pubkey ?? "anonymous")"
    }

    static func persistedFeedSourceKey(pubkey: String?) -> String {
        "homeFeedSourcePreference.\(pubkey ?? "anonymous")"
    }

    private func mutedConversationStorageKey(pubkey: String?) -> String {
        "\(mutedConversationStoragePrefix).\(pubkey ?? "anonymous")"
    }

    private func loadMutedConversationIDs(pubkey: String?) -> Set<String> {
        let key = mutedConversationStorageKey(pubkey: pubkey)
        guard let raw = feedSourceStorage.stringArray(forKey: key) else { return [] }
        return Set(
            raw
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    private func persistMutedConversationIDs(pubkey: String?) {
        let key = mutedConversationStorageKey(pubkey: pubkey)
        feedSourceStorage.set(Array(mutedConversationIDs).sorted(), forKey: key)
    }

    private func localFollowings() -> [String] {
        Array(FollowStore.shared.followedPubkeys)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .sorted()
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

    private static func normalizedFavoriteHashtags(_ hashtags: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for hashtag in hashtags {
            let normalized = HomePrimaryFeedSource.normalizeHashtag(hashtag)
            guard !normalized.isEmpty else { continue }
            guard seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }

        return ordered
    }

    private func resolvedFeedSource(_ source: HomePrimaryFeedSource) -> HomePrimaryFeedSource {
        switch source {
        case .custom(let feedID):
            return customFeedDefinition(id: feedID) == nil ? .network : .custom(feedID)
        case .hashtag(let hashtag):
            let normalizedHashtag = HomePrimaryFeedSource.normalizeHashtag(hashtag)
            guard favoriteHashtags.contains(normalizedHashtag) else {
                return .network
            }
            return .hashtag(normalizedHashtag)
        case .interests:
            return interestHashtags.isEmpty ? .network : .interests
        default:
            return source
        }
    }

    private func relayURLs(for source: HomePrimaryFeedSource) -> [URL] {
        switch source {
        case .news:
            let newsRelays = Self.normalizedRelayURLs(AppSettingsStore.shared.newsRelayURLs)
            return newsRelays.isEmpty ? [Self.newsFallbackRelayURL] : newsRelays
        case .custom:
            let combined = Self.normalizedRelayURLs(readRelayURLs + Self.customFeedSupplementalRelayURLs)
            return combined.isEmpty ? readRelayURLs : combined
        default:
            return readRelayURLs
        }
    }

    private func hydrationRelayURLs(for source: HomePrimaryFeedSource) -> [URL] {
        switch source {
        case .news:
            let combined = Self.normalizedRelayURLs(readRelayURLs + relayURLs(for: .news))
            return combined.isEmpty ? [Self.newsFallbackRelayURL] : combined
        case .custom:
            return relayURLs(for: source)
        default:
            return relayURLs(for: source)
        }
    }

    private func feedKinds(for source: HomePrimaryFeedSource) -> [Int] {
        switch source {
        case .interests:
            return FeedKindFilters.normalizedKinds(showKinds)
        case .news:
            return [1]
        case .custom:
            return FeedKindFilters.normalizedKinds(showKinds)
        default:
            return FeedKindFilters.normalizedKinds(showKinds)
        }
    }

    func customFeedDefinition(id: String) -> CustomFeedDefinition? {
        let normalizedID = HomePrimaryFeedSource.normalizeCustomFeedID(id)
        guard !normalizedID.isEmpty else { return nil }
        return customFeeds.first { $0.id == normalizedID }
    }

    private func normalizedOrderedPubkeys(_ pubkeys: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for pubkey in pubkeys {
            let normalized = pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }

        return ordered
    }

    private func configuredNewsAuthorPubkeys() -> [String] {
        normalizedOrderedPubkeys(AppSettingsStore.shared.newsAuthorPubkeys)
    }

    private func configuredNewsHashtags() -> [String] {
        Self.normalizedFavoriteHashtags(AppSettingsStore.shared.newsHashtags)
    }

    private func configuredInterestHashtags() -> [String] {
        Self.normalizedFavoriteHashtags(interestHashtags)
    }

    private func usesCompositePagination(_ source: HomePrimaryFeedSource) -> Bool {
        switch source {
        case .news, .custom:
            return true
        default:
            return false
        }
    }

    private func fetchInterestsFeedPage(
        limit: Int,
        until: Int?,
        hydrationMode: FeedItemHydrationMode = .full,
        fetchTimeout: TimeInterval = 12,
        relayFetchMode: RelayFetchMode = .allRelays,
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async throws -> NewsFeedPageResult {
        let hashtags = configuredInterestHashtags()
        guard !hashtags.isEmpty else {
            return NewsFeedPageResult(items: [], hadMoreAvailable: false)
        }

        let relayTargets = relayURLs(for: .interests)
        let kinds = feedKinds(for: .interests)
        let fetched = try await service.fetchHashtagFeed(
            relayURLs: relayTargets,
            hashtags: hashtags,
            kinds: kinds,
            limit: limit,
            until: until,
            hydrationMode: hydrationMode,
            fetchTimeout: fetchTimeout,
            relayFetchMode: relayFetchMode,
            moderationSnapshot: moderationSnapshot
        )
        return NewsFeedPageResult(
            items: fetched,
            hadMoreAvailable: fetched.count >= limit
        )
    }

    private func fetchNewsFeedPage(
        limit: Int,
        until: Int?,
        hydrationMode: FeedItemHydrationMode = .full,
        fetchTimeout: TimeInterval = 12,
        relayFetchMode: RelayFetchMode = .allRelays,
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async throws -> NewsFeedPageResult {
        let newsRelayURLs = relayURLs(for: .news)
        let hydrationRelayURLs = hydrationRelayURLs(for: .news)
        let authors = configuredNewsAuthorPubkeys()
        let hashtags = configuredNewsHashtags()
        let perHashtagLimit = hashtags.isEmpty ? 0 : max(8, min(18, limit))

        async let relayItemsTask = service.fetchFeed(
            relayURLs: newsRelayURLs,
            kinds: [1],
            limit: limit,
            until: until,
            hydrationMode: hydrationMode,
            fetchTimeout: fetchTimeout,
            relayFetchMode: relayFetchMode,
            moderationSnapshot: moderationSnapshot
        )
        async let authorItemsTask = authors.isEmpty
            ? [FeedItem]()
            : service.fetchFollowingFeed(
                relayURLs: hydrationRelayURLs,
                authors: authors,
                kinds: [1],
                limit: limit,
                until: until,
                hydrationMode: hydrationMode,
                fetchTimeout: fetchTimeout,
                relayFetchMode: relayFetchMode,
                moderationSnapshot: moderationSnapshot
            )

        let relayItems = try await relayItemsTask
        let authorItems = try await authorItemsTask

        let hashtagItems: [[FeedItem]]
        if hashtags.isEmpty {
            hashtagItems = []
        } else {
            hashtagItems = try await withThrowingTaskGroup(of: [FeedItem].self) { group in
                for hashtag in hashtags {
                    group.addTask { [self] in
                        try await self.service.fetchHashtagFeed(
                            relayURLs: hydrationRelayURLs,
                            hashtag: hashtag,
                            kinds: [1],
                            limit: perHashtagLimit,
                            until: until,
                            hydrationMode: hydrationMode,
                            fetchTimeout: fetchTimeout,
                            relayFetchMode: relayFetchMode,
                            moderationSnapshot: moderationSnapshot
                        )
                    }
                }

                var merged: [[FeedItem]] = []
                for try await items in group {
                    merged.append(items)
                }
                return merged
            }
        }

        var seenEventIDs = Set<String>()
        let mergedEvents = Array(
            (relayItems + authorItems + hashtagItems.flatMap { $0 })
                .map(\.event)
                .sorted(by: { lhs, rhs in
                    if lhs.createdAt == rhs.createdAt {
                        return lhs.id > rhs.id
                    }
                    return lhs.createdAt > rhs.createdAt
                })
                .filter { event in
                    seenEventIDs.insert(event.id).inserted
                }
        )

        let limitedEvents = Array(mergedEvents.prefix(limit))
        let hydrated = await service.buildFeedItems(
            relayURLs: hydrationRelayURLs,
            events: limitedEvents,
            hydrationMode: hydrationMode,
            moderationSnapshot: moderationSnapshot
        )

        let hadMoreAvailable =
            relayItems.count >= limit ||
            (!authors.isEmpty && authorItems.count >= limit) ||
            hashtagItems.contains(where: { $0.count >= perHashtagLimit }) ||
            mergedEvents.count > limit

        return NewsFeedPageResult(
            items: hydrated,
            hadMoreAvailable: hadMoreAvailable
        )
    }

    private func fetchCustomFeedPage(
        feed: CustomFeedDefinition,
        kinds: [Int],
        limit: Int,
        until: Int?,
        hydrationMode: FeedItemHydrationMode = .full,
        fetchTimeout: TimeInterval = 12,
        relayFetchMode: RelayFetchMode = .allRelays,
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async throws -> NewsFeedPageResult {
        guard limit > 0 else {
            return NewsFeedPageResult(items: [], hadMoreAvailable: false)
        }

        let relayTargets = relayURLs(for: .custom(feed.id))
        let authors = Array(feed.authorPubkeys.prefix(400))
        let hashtags = feed.hashtags
        let phrases = feed.phrases

        guard !authors.isEmpty || !hashtags.isEmpty || !phrases.isEmpty else {
            return NewsFeedPageResult(items: [], hadMoreAvailable: false)
        }

        let perHashtagLimit = hashtags.isEmpty ? 0 : max(8, min(18, limit))
        let perPhraseLimit = phrases.isEmpty ? 0 : max(8, min(18, limit))

        async let authorItemsTask = authors.isEmpty
            ? [FeedItem]()
            : service.fetchFollowingFeed(
                relayURLs: relayTargets,
                authors: authors,
                kinds: kinds,
                limit: limit,
                until: until,
                hydrationMode: hydrationMode,
                fetchTimeout: fetchTimeout,
                relayFetchMode: relayFetchMode,
                moderationSnapshot: moderationSnapshot
            )

        let authorItems = try await authorItemsTask

        let hashtagItems: [[FeedItem]]
        if hashtags.isEmpty {
            hashtagItems = []
        } else {
            hashtagItems = try await withThrowingTaskGroup(of: [FeedItem].self) { group in
                for hashtag in hashtags {
                    group.addTask { [self] in
                        try await self.service.fetchHashtagFeed(
                            relayURLs: relayTargets,
                            hashtag: hashtag,
                            kinds: kinds,
                            limit: perHashtagLimit,
                            until: until,
                            hydrationMode: hydrationMode,
                            fetchTimeout: fetchTimeout,
                            relayFetchMode: relayFetchMode,
                            moderationSnapshot: moderationSnapshot
                        )
                    }
                }

                var merged: [[FeedItem]] = []
                for try await items in group {
                    merged.append(items)
                }
                return merged
            }
        }

        let phraseItems: [[FeedItem]]
        if phrases.isEmpty {
            phraseItems = []
        } else {
            phraseItems = try await withThrowingTaskGroup(of: [FeedItem].self) { group in
                for phrase in phrases {
                    group.addTask { [self] in
                        try await self.service.searchNotes(
                            relayURLs: relayTargets,
                            query: phrase,
                            kinds: kinds,
                            limit: perPhraseLimit,
                            until: until,
                            hydrationMode: hydrationMode,
                            fetchTimeout: fetchTimeout,
                            relayFetchMode: relayFetchMode,
                            moderationSnapshot: moderationSnapshot
                        )
                    }
                }

                var merged: [[FeedItem]] = []
                for try await items in group {
                    merged.append(items)
                }
                return merged
            }
        }

        let mergedItems = mergeItemArrays(
            primary: authorItems + hashtagItems.flatMap { $0 } + phraseItems.flatMap { $0 },
            secondary: []
        )

        let limitedItems = Array(mergedItems.prefix(limit))
        let hadMoreAvailable =
            (!authors.isEmpty && authorItems.count >= limit) ||
            hashtagItems.contains(where: { $0.count >= perHashtagLimit }) ||
            phraseItems.contains(where: { $0.count >= perPhraseLimit }) ||
            mergedItems.count > limit

        return NewsFeedPageResult(
            items: limitedItems,
            hadMoreAvailable: hadMoreAvailable
        )
    }

    private func scheduleItemHydration(
        for sourceItems: [FeedItem],
        source: HomePrimaryFeedSource,
        userPubkey: String?
    ) {
        itemHydrationTask?.cancel()

        let events = sourceItems.map(\.event)
        guard !events.isEmpty else { return }
        let relayTargets = hydrationRelayURLs(for: source)

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
                guard self.feedSource == source, self.currentUserPubkey == userPubkey else {
                    return
                }

                self.items = self.pruneMutedItems(
                    self.mergeItemArrays(primary: hydrated, secondary: self.items)
                )
                self.scheduleAssetPrefetch(for: self.items)
                self.knownEventIDs = Set(self.items.map(\.id))
                self.knownEventIDs.formUnion(self.bufferedNewItems.map(\.id))

                Task { [weak self] in
                    guard let self else { return }
                    await self.persistRecentFeedSnapshot(from: self.items)
                }
            }
        }
    }

    private func scheduleAssetPrefetch(for sourceItems: [FeedItem]) {
        let urls = Array(
            sourceItems
                .prefix(assetPrefetchItemCount)
                .flatMap(\.prefetchImageURLs)
        )
        guard !urls.isEmpty else { return }

        Task(priority: .utility) {
            await FlowImageCache.shared.prefetch(urls: urls)
        }
    }
}

private enum HomeFeedError: Error {
    case networkRequiresLogin
    case followingRequiresLogin
}

@MainActor
final class WebOfTrustStore: ObservableObject {
    static let shared = WebOfTrustStore()

    @Published private(set) var orderedTrustedPubkeys: [String] = []
    @Published private(set) var isLoading = false

    private struct Session: Equatable {
        let accountPubkey: String
        let relayURLs: [URL]
        let hopCount: Int
    }

    private let service: NostrFeedService
    private let cache: WebOfTrustGraphCache
    private var session: Session?
    private var rebuildTask: Task<Void, Never>?

    private let maxTrustedPubkeys = 1_200
    private let expansionBatchSize = 12
    private static let cacheMaxAge: TimeInterval = 60 * 60 * 6

    init(
        service: NostrFeedService = NostrFeedService(),
        cache: WebOfTrustGraphCache = .shared
    ) {
        self.service = service
        self.cache = cache
    }

    deinit {
        rebuildTask?.cancel()
    }

    func configure(accountPubkey: String?, relayURLs: [URL], hopCount: Int) {
        let normalizedAccount = normalizePubkey(accountPubkey)
        let normalizedRelays = normalizedRelayURLs(relayURLs)
        let clampedHops = AppSettingsStore.clampedWebOfTrustHops(hopCount)

        guard !normalizedAccount.isEmpty, !normalizedRelays.isEmpty else {
            session = nil
            rebuildTask?.cancel()
            orderedTrustedPubkeys = []
            isLoading = false
            return
        }

        let nextSession = Session(
            accountPubkey: normalizedAccount,
            relayURLs: normalizedRelays,
            hopCount: clampedHops
        )

        guard nextSession != session else { return }

        session = nextSession
        orderedTrustedPubkeys = directFollowings(for: normalizedAccount)
        isLoading = true

        Task { [weak self] in
            await self?.applyCachedGraphIfAvailable(for: nextSession)
        }

        rebuildGraph(for: nextSession)
    }

    func refresh() {
        guard let session else { return }
        orderedTrustedPubkeys = directFollowings(for: session.accountPubkey)
        isLoading = true
        rebuildGraph(for: session)
    }

    private func rebuildGraph(for session: Session) {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            guard let self else { return }
            let graph = await self.buildGraph(for: session)
            guard !Task.isCancelled else { return }

            await self.cache.storePubkeys(graph, for: self.cacheKey(for: session))

            await MainActor.run {
                guard self.session == session else { return }
                self.orderedTrustedPubkeys = graph
                self.isLoading = false
            }
        }
    }

    private func applyCachedGraphIfAvailable(for session: Session) async {
        guard let cached = await cache.cachedPubkeys(
            for: cacheKey(for: session),
            maxAge: Self.cacheMaxAge
        ) else {
            return
        }

        await MainActor.run {
            guard self.session == session else { return }
            if cached.count > self.orderedTrustedPubkeys.count {
                self.orderedTrustedPubkeys = cached
            }
        }
    }

    private func buildGraph(for session: Session) async -> [String] {
        var visited: Set<String> = [session.accountPubkey]
        var trusted: [String] = []

        var frontier = directFollowings(for: session.accountPubkey)
        if frontier.isEmpty {
            frontier = await fetchFollowingsForExpansion(
                pubkey: session.accountPubkey,
                relayURLs: session.relayURLs
            )
        }

        frontier = normalizedOrderedPubkeys(frontier).filter { visited.insert($0).inserted }
        trusted.append(contentsOf: frontier)

        guard session.hopCount > 1, !frontier.isEmpty else {
            return Array(trusted.prefix(maxTrustedPubkeys))
        }

        for _ in 2...session.hopCount {
            guard !Task.isCancelled, !frontier.isEmpty, trusted.count < maxTrustedPubkeys else { break }

            var nextFrontier: [String] = []
            let batches = chunked(frontier, into: expansionBatchSize)

            for batch in batches {
                guard !Task.isCancelled, trusted.count < maxTrustedPubkeys else { break }

                let fetchedFollowings = await withTaskGroup(of: [String].self) { group in
                    for pubkey in batch {
                        group.addTask { [service] in
                            if let cached = await service.cachedFollowListSnapshot(pubkey: pubkey) {
                                return cached.followedPubkeys
                            }
                            return await self.fetchFollowingsForExpansion(pubkey: pubkey, relayURLs: session.relayURLs)
                        }
                    }

                    var aggregated: [[String]] = []
                    for await followings in group {
                        aggregated.append(followings)
                    }
                    return aggregated
                }

                for followings in fetchedFollowings {
                    for pubkey in followings {
                        let normalized = normalizePubkey(pubkey)
                        guard !normalized.isEmpty, visited.insert(normalized).inserted else { continue }
                        trusted.append(normalized)
                        nextFrontier.append(normalized)

                        if trusted.count >= maxTrustedPubkeys {
                            break
                        }
                    }

                    if trusted.count >= maxTrustedPubkeys {
                        break
                    }
                }
            }

            frontier = nextFrontier
        }

        return trusted
    }

    private func fetchFollowingsForExpansion(pubkey: String, relayURLs: [URL]) async -> [String] {
        (try? await service.fetchFollowings(relayURLs: relayURLs, pubkey: pubkey)) ?? []
    }

    private func directFollowings(for accountPubkey: String) -> [String] {
        normalizedOrderedPubkeys(Array(FollowStore.shared.followedPubkeys))
            .filter { $0 != accountPubkey }
    }

    private func cacheKey(for session: Session) -> String {
        let relaySignature = session.relayURLs
            .map { $0.absoluteString.lowercased() }
            .joined(separator: ",")
        return "\(session.accountPubkey)|\(session.hopCount)|\(relaySignature)"
    }

    private func normalizePubkey(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func normalizedOrderedPubkeys(_ pubkeys: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for pubkey in pubkeys {
            let normalized = normalizePubkey(pubkey)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }

        return ordered
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

    private func chunked(_ values: [String], into size: Int) -> [[String]] {
        guard size > 0, !values.isEmpty else { return [] }

        var result: [[String]] = []
        result.reserveCapacity((values.count + size - 1) / size)

        var index = 0
        while index < values.count {
            let nextIndex = min(index + size, values.count)
            result.append(Array(values[index..<nextIndex]))
            index = nextIndex
        }

        return result
    }
}
