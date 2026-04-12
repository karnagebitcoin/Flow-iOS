import Foundation

@MainActor
final class HomeFeedViewModel: ObservableObject {
    struct FeedRequestStrategy: Equatable {
        let fetchTimeout: TimeInterval
        let relayFetchMode: RelayFetchMode
    }

    private struct TrendingPaginationState {
        let windowStart: Int
        let windowEnd: Int
        let cursor: Int
    }

    private struct TrendingPageFetchResult {
        let page: HomeFeedPageResult
        let nextState: TrendingPaginationState?
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
    @Published private(set) var pollsFeedVisible = true
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
    private static let followingHomeFetchTimeout: TimeInterval = 8
    private static let followingPaginationFetchTimeout: TimeInterval = 12
    private static let liveCatchUpFetchTimeout: TimeInterval = 4
    private static let liveCatchUpMinimumInterval: TimeInterval = 15
    private static let liveCatchUpOverlapSeconds = 90
    private static let liveCatchUpLimit = 200
    private static let trendingWindowDuration: Int = 24 * 60 * 60
    private static let trendingBackfillWindowLimitPerPage = 7
    private static let trendingRelayURL = URL(string: "wss://trending.relays.land")!
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
    private var liveCatchUpTask: Task<Void, Never>?
    private var liveCatchUpToken = 0
    private var lastLiveCatchUpBySignature: [String: Date] = [:]
    private var resetFeedTask: Task<Void, Never>?
    private var itemHydrationTask: Task<Void, Never>?
    private var warmStartRefreshTask: Task<Void, Never>?
    private var isPrefetchingMore = false
    private var latestRefreshRequestID = 0
    private var trendingPaginationState: TrendingPaginationState?

    nonisolated static var defaultPageSizeForTesting: Int {
        HomeFeedPaginationDefaults.pageSize
    }

    init(
        relayURL: URL,
        readRelayURLs: [URL]? = nil,
        pageSize: Int = HomeFeedPaginationDefaults.pageSize,
        service: NostrFeedService = NostrFeedService(),
        liveSubscriber: NostrLiveFeedSubscriber = NostrLiveFeedSubscriber(),
        recentFeedStore: RecentFeedStore = .shared,
        filterStore: HomeFeedFilterStore = .shared
    ) {
        let defaults = filterStore.loadDefaults()

        let normalizedReadRelays = HomeFeedSourceResolver.normalizedRelayURLs(readRelayURLs ?? [relayURL])
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
        liveCatchUpTask?.cancel()
        resetFeedTask?.cancel()
        itemHydrationTask?.cancel()
        warmStartRefreshTask?.cancel()
    }

    var feedSourceOptions: [HomePrimaryFeedSource] {
        let hashtagSources = favoriteHashtags.map { HomePrimaryFeedSource.hashtag($0) }
        let interestSources: [HomePrimaryFeedSource] = interestHashtags.isEmpty ? [] : [.interests]
        let customSources = customFeeds.map { HomePrimaryFeedSource.custom($0.id) }
        let pollsSources: [HomePrimaryFeedSource] = pollsFeedVisible ? [.polls] : []
        return [.network, .following] + pollsSources + [.trending] + interestSources + [.news] + customSources + hashtagSources
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

    var visibleBufferedNewItems: [FeedItem] {
        filterVisibleItems(bufferedNewItems)
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
        (feedSource == .following || feedSource == .polls) && !isLoading && followingPubkeys.isEmpty && errorMessage == nil
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

    // Following history should be fetched exhaustively so older notes are not
    // truncated just because the first responding relay has no more results.
    static func requestStrategy(
        for source: HomePrimaryFeedSource,
        isPagination: Bool
    ) -> FeedRequestStrategy {
        switch source {
        case .following, .polls:
            return FeedRequestStrategy(
                fetchTimeout: isPagination ? Self.followingPaginationFetchTimeout : Self.followingHomeFetchTimeout,
                relayFetchMode: .allRelays
            )
        default:
            return FeedRequestStrategy(
                fetchTimeout: Self.fastHomeFetchTimeout,
                relayFetchMode: Self.fastHomeRelayFetchMode
            )
        }
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
        case .polls:
            sourceDescriptor = "polls:\(currentUserPubkey ?? "anonymous")"
        case .trending:
            sourceDescriptor = "trending"
        case .interests:
            sourceDescriptor = "interests"
        case .news:
            let newsAuthorsSignature = configuredNewsAuthorPubkeys().joined(separator: ",")
            let newsHashtagsSignature = configuredNewsHashtags().joined(separator: ",")
            sourceDescriptor = "news:v2:\(newsAuthorsSignature):\(newsHashtagsSignature)"
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
        let normalized = HomeFeedSourceResolver.normalizedFavoriteHashtags(hashtags)
        guard favoriteHashtags != normalized else { return }

        favoriteHashtags = normalized

        if case .hashtag(let selectedHashtag) = feedSource,
           !normalized.contains(HomePrimaryFeedSource.normalizeHashtag(selectedHashtag)) {
            feedSource = .network
            storeFeedSourcePreference(feedSource, pubkey: currentUserPubkey)
            resetFeedStateAndReload()
        }
    }

    func updatePollsFeedVisibility(_ isVisible: Bool) {
        guard pollsFeedVisible != isVisible else { return }

        pollsFeedVisible = isVisible

        if feedSource == .polls && !isVisible {
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
        let normalized = HomeFeedSourceResolver.normalizedFavoriteHashtags(hashtags)
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
        let normalized = HomeFeedSourceResolver.normalizedRelayURLs(newReadRelayURLs)
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
                scheduleWarmStartRefresh()
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
        trendingPaginationState = nil
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
            var sourcePageResult: HomeFeedPageResult?
            let requestRelayURLs = relayURLs(for: requestSource)
            let requestKinds = feedKinds(for: requestSource)
            let requestHydrationMode: FeedItemHydrationMode = .cachedProfilesOnly
            let requestStrategy = Self.requestStrategy(for: requestSource, isPagination: false)
            let requestFetchTimeout = requestStrategy.fetchTimeout
            let requestRelayFetchMode = requestStrategy.relayFetchMode

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
                sourcePageResult = interestPage

            case .trending:
                followingPubkeys = []
                let trendingPage = try await fetchTrendingFeedPage(
                    limit: pageSize,
                    paginationState: nil,
                    hydrationMode: requestHydrationMode,
                    fetchTimeout: requestFetchTimeout,
                    relayFetchMode: requestRelayFetchMode,
                    moderationSnapshot: muteFilterSnapshot
                )
                fetched = trendingPage.page.items
                sourcePageResult = trendingPage.page
                trendingPaginationState = trendingPage.nextState

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
                sourcePageResult = newsPage

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
                sourcePageResult = customPage

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
                let followingFeedAuthors = Self.followingAuthorPubkeys(
                    followingPubkeys: followings,
                    currentUserPubkey: requestUserPubkey
                )

                if followingFeedAuthors.isEmpty {
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

                let followingPage = try await fetchFollowingFeedPage(
                    relayURLs: requestRelayURLs,
                    authors: followingFeedAuthors,
                    kinds: requestKinds,
                    limit: pageSize,
                    until: nil,
                    hydrationMode: requestHydrationMode,
                    fetchTimeout: requestFetchTimeout,
                    relayFetchMode: requestRelayFetchMode,
                    moderationSnapshot: muteFilterSnapshot
                )
                fetched = followingPage.items

            case .polls:
                guard let requestUserPubkey else {
                    throw HomeFeedError.pollsRequiresLogin
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
                let pollAuthors = Self.followingAuthorPubkeys(
                    followingPubkeys: followings,
                    currentUserPubkey: requestUserPubkey
                )

                if pollAuthors.isEmpty {
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

                let pollsPage = try await fetchFollowingFeedPage(
                    relayURLs: requestRelayURLs,
                    authors: pollAuthors,
                    kinds: FeedKindFilters.pollKinds,
                    limit: pageSize,
                    until: nil,
                    hydrationMode: requestHydrationMode,
                    fetchTimeout: requestFetchTimeout,
                    relayFetchMode: requestRelayFetchMode,
                    moderationSnapshot: muteFilterSnapshot
                )
                fetched = pollsPage.items
            }

            if requestSource != feedSource || requestUserPubkey != currentUserPubkey {
                guard latestRefreshRequestID == refreshRequestID else { return }
                needsRefreshAfterCurrentRequest = true
                return
            }

            if requestSource != .news,
               requestSource != .trending,
               requestSource != .polls,
               !FeedKindFilters.isSameSelection(requestKinds, showKinds) {
                guard latestRefreshRequestID == refreshRequestID else { return }
                needsRefreshAfterCurrentRequest = true
                return
            }

            guard latestRefreshRequestID == refreshRequestID else { return }

            let mergedItems = pruneItemsForSource(
                pruneMutedItems(
                    startedWithEmptyItems
                        ? mergeItemArrays(primary: bufferedNewItems, secondary: fetched)
                        : fetched
                ),
                feedSource: requestSource,
                followingPubkeys: requestSource == .following ? self.followingPubkeys : nil
            )

            items = mergedItems
            bufferedNewItems = []
            knownEventIDs = Set(mergedItems.map(\.id))
            oldestCreatedAt = mergedItems.last?.event.createdAt ?? fetched.last?.event.createdAt
            if let sourcePageResult {
                hasReachedEnd = !sourcePageResult.hadMoreAvailable
            } else {
                hasReachedEnd = FeedPaginationHeuristic.shouldStopPaging(afterFetchedCount: fetched.count)
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
            case HomeFeedError.pollsRequiresLogin:
                errorMessage = "Sign in to view the Polls feed."
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
        guard !isLoading, !hasReachedEnd else { return }

        let currentVisibleItems = visibleItems
        guard let currentIndex = currentVisibleItems.firstIndex(where: { $0.id == currentItem.id }) else { return }
        guard Self.shouldPrefetchMore(
            visibleItemCount: currentVisibleItems.count,
            currentIndex: currentIndex
        ) else {
            return
        }

        let shouldShowLoadingIndicator = Self.shouldShowPaginationSpinner(
            visibleItemCount: currentVisibleItems.count,
            currentIndex: currentIndex
        )

        if isPrefetchingMore {
            if shouldShowLoadingIndicator {
                isLoadingMore = true
            }
            return
        }
        guard !isLoadingMore else { return }

        let until = max((oldestCreatedAt ?? Int(Date().timeIntervalSince1970)) - 1, 0)
        guard until > 0 else { return }

        let requestSource = feedSource
        let requestUserPubkey = currentUserPubkey
        let requestRefreshID = latestRefreshRequestID
        let requestHydrationMode: FeedItemHydrationMode = .cachedProfilesOnly
        let requestStrategy = Self.requestStrategy(for: requestSource, isPagination: true)
        let requestFetchTimeout = requestStrategy.fetchTimeout
        let requestRelayFetchMode = requestStrategy.relayFetchMode

        isPrefetchingMore = true
        if shouldShowLoadingIndicator {
            isLoadingMore = true
        }
        itemHydrationTask?.cancel()
        itemHydrationTask = nil
        defer {
            isPrefetchingMore = false
            isLoadingMore = false
        }

        do {
            var fetched: [FeedItem]
            var sourcePageResult: HomeFeedPageResult?
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
                sourcePageResult = interestPage

            case .trending:
                let trendingPage = try await fetchTrendingFeedPage(
                    limit: pageSize,
                    paginationState: trendingPaginationState,
                    hydrationMode: requestHydrationMode,
                    fetchTimeout: requestFetchTimeout,
                    relayFetchMode: requestRelayFetchMode,
                    moderationSnapshot: muteFilterSnapshot
                )
                fetched = trendingPage.page.items
                sourcePageResult = trendingPage.page
                trendingPaginationState = trendingPage.nextState

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
                sourcePageResult = newsPage

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
                sourcePageResult = customPage

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
                let followingFeedAuthors = Self.followingAuthorPubkeys(
                    followingPubkeys: followingPubkeys,
                    currentUserPubkey: currentUserPubkey
                )
                guard !followingFeedAuthors.isEmpty else {
                    hasReachedEnd = true
                    return
                }

                let followingPage = try await fetchFollowingFeedPage(
                    relayURLs: requestRelayURLs,
                    authors: followingFeedAuthors,
                    kinds: requestKinds,
                    limit: pageSize,
                    until: until,
                    hydrationMode: requestHydrationMode,
                    fetchTimeout: requestFetchTimeout,
                    relayFetchMode: requestRelayFetchMode,
                    moderationSnapshot: muteFilterSnapshot
                )
                fetched = followingPage.items

            case .polls:
                let pollAuthors = Self.followingAuthorPubkeys(
                    followingPubkeys: followingPubkeys,
                    currentUserPubkey: currentUserPubkey
                )
                guard !pollAuthors.isEmpty else {
                    hasReachedEnd = true
                    return
                }

                let pollsPage = try await fetchFollowingFeedPage(
                    relayURLs: requestRelayURLs,
                    authors: pollAuthors,
                    kinds: FeedKindFilters.pollKinds,
                    limit: pageSize,
                    until: until,
                    hydrationMode: requestHydrationMode,
                    fetchTimeout: requestFetchTimeout,
                    relayFetchMode: requestRelayFetchMode,
                    moderationSnapshot: muteFilterSnapshot
                )
                fetched = pollsPage.items
            }

            if requestRefreshID != latestRefreshRequestID || requestSource != feedSource {
                return
            }

            if requestSource != .news,
               requestSource != .trending,
               requestSource != .polls,
               !FeedKindFilters.isSameSelection(requestKinds, showKinds) {
                return
            }

            if fetched.isEmpty {
                hasReachedEnd = !(sourcePageResult?.hadMoreAvailable ?? false)
                return
            }

            oldestCreatedAt = fetched.last?.event.createdAt
            if let sourcePageResult {
                hasReachedEnd = !sourcePageResult.hadMoreAvailable
            } else {
                hasReachedEnd = FeedPaginationHeuristic.shouldStopPaging(afterFetchedCount: fetched.count)
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

    nonisolated static func shouldPrefetchMore(
        visibleItemCount: Int,
        currentIndex: Int
    ) -> Bool {
        guard visibleItemCount > 0 else { return false }
        guard currentIndex >= 0, currentIndex < visibleItemCount else { return false }
        let remainingItemCount = visibleItemCount - currentIndex - 1
        return remainingItemCount <= HomeFeedPaginationDefaults.prefetchTriggerDistance
    }

    nonisolated static func shouldShowPaginationSpinner(
        visibleItemCount: Int,
        currentIndex: Int
    ) -> Bool {
        guard visibleItemCount > 0 else { return false }
        guard currentIndex >= 0, currentIndex < visibleItemCount else { return false }
        let remainingItemCount = visibleItemCount - currentIndex - 1
        return remainingItemCount <= HomeFeedPaginationDefaults.spinnerTriggerDistance
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
            self.liveCatchUpTask?.cancel()
            self.liveCatchUpTask = nil
            self.lastLiveCatchUpBySignature.removeAll()
            self.liveSubscriptionKinds = []
            self.liveSubscriptionSource = nil
            self.liveSubscriptionConfigurationSignature = nil

            Task { [weak self] in
                guard let self else { return }
                let loadedFromCache = await self.loadRecentFeedSnapshot()
                if loadedFromCache {
                    self.scheduleWarmStartRefresh(force: false, restartLiveUpdates: true)
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
        trendingPaginationState = nil
        followingPubkeys = []
        errorMessage = nil

        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil
        liveCatchUpTask?.cancel()
        liveCatchUpTask = nil
        lastLiveCatchUpBySignature.removeAll()
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
            if loadedFromCache {
                self.isBootstrappingFeed = false
                self.scheduleWarmStartRefresh(force: true, restartLiveUpdates: true)
            } else {
                await self.refresh(force: true)
            }
        }
    }

    private func scheduleWarmStartRefresh(
        force: Bool = false,
        restartLiveUpdates: Bool = false
    ) {
        warmStartRefreshTask?.cancel()
        warmStartRefreshTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            if restartLiveUpdates {
                self.startLiveUpdatesIfNeeded(forceRestart: true)
            }
            await self.refresh(silent: true, force: force)
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
            liveCatchUpTask?.cancel()
            liveCatchUpTask = nil
            lastLiveCatchUpBySignature.removeAll()
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
        liveCatchUpTask?.cancel()
        liveCatchUpTask = nil
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
                                await self.handleLiveStatus(target: target)
                            }
                        )
                    }
                }
                await group.waitForAll()
            }
        }

        scheduleLiveCatchUp(for: targets, force: true)
    }

    private func handleLiveStatus(target: HomeFeedLiveSubscriptionTarget) async {
        scheduleLiveCatchUp(for: [target])
    }

    private func scheduleLiveCatchUp(
        for targets: [HomeFeedLiveSubscriptionTarget],
        force: Bool = false
    ) {
        guard liveCatchUpTask == nil else { return }
        guard !targets.isEmpty else { return }

        let now = Date()
        let dueTargets = targets.filter { target in
            guard !force else { return true }
            guard let lastFetch = lastLiveCatchUpBySignature[target.signature] else { return true }
            return now.timeIntervalSince(lastFetch) >= Self.liveCatchUpMinimumInterval
        }
        guard !dueTargets.isEmpty else { return }

        dueTargets.forEach { lastLiveCatchUpBySignature[$0.signature] = now }
        liveCatchUpToken &+= 1
        let token = liveCatchUpToken
        liveCatchUpTask = Task(priority: .utility) { [weak self, dueTargets] in
            guard let self else { return }
            await self.performLiveCatchUp(for: dueTargets)
            await MainActor.run { [weak self] in
                guard let self, self.liveCatchUpToken == token else { return }
                self.liveCatchUpTask = nil
            }
        }
    }

    private func performLiveCatchUp(for targets: [HomeFeedLiveSubscriptionTarget]) async {
        let catchUpSince = max(Int(Date().timeIntervalSince1970) - Self.liveCatchUpOverlapSeconds, 0)
        let catchUpLimit = Self.liveCatchUpLimit
        let catchUpTimeout = Self.liveCatchUpFetchTimeout
        let service = service

        await withTaskGroup(of: [NostrEvent].self) { group in
            for target in targets {
                group.addTask {
                    await service.fetchLiveCatchUpEvents(
                        relayURL: target.relayURL,
                        filter: target.filter,
                        since: catchUpSince,
                        limit: catchUpLimit,
                        timeout: catchUpTimeout
                    )
                }
            }

            for await events in group {
                guard !Task.isCancelled else { return }
                for event in events {
                    await handleLiveEvent(event)
                }
            }
        }
    }

    private func handleLiveEvent(_ event: NostrEvent) async {
        let normalizedEventID = event.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard feedKinds(for: feedSource).contains(event.kind) else { return }
        guard !normalizedEventID.isEmpty, !knownEventIDs.contains(normalizedEventID) else { return }

        await service.ingestLiveEvents([event])

        let hydrated = await service.buildFeedItems(
            relayURLs: hydrationRelayURLs(for: feedSource),
            events: [event],
            moderationSnapshot: muteFilterSnapshot
        )
        guard let item = hydrated.first else { return }
        guard !knownEventIDs.contains(item.id) else { return }
        guard itemIsAllowedForCurrentSource(item) else { return }

        knownEventIDs.insert(item.id)
        bufferedNewItems = mergeItemArrays(
            primary: [item],
            secondary: bufferedNewItems
        )
        scheduleAssetPrefetch(for: [item])
    }

    private func mergeKeepingNewest(itemsToMerge: [FeedItem]) {
        items = pruneItemsForSource(
            pruneMutedItems(mergeItemArrays(primary: itemsToMerge, secondary: items))
        )
        scheduleAssetPrefetch(for: items)

        let currentlyVisibleIDs = Set(items.map(\.id))
        bufferedNewItems.removeAll { currentlyVisibleIDs.contains($0.id) }

        knownEventIDs = currentlyVisibleIDs
        knownEventIDs.formUnion(bufferedNewItems.map(\.id))
    }

    private func liveSubscriptionTargets(
        for source: HomePrimaryFeedSource,
        kinds: [Int]
    ) -> [HomeFeedLiveSubscriptionTarget] {
        switch source {
        case .network:
            return subscriptionTargets(
                relayURLs: relayURLs(for: .network),
                filter: NostrFilter(kinds: kinds, limit: 100),
                scopeSignature: "network"
            )

        case .trending:
            return []

        case .interests:
            let hashtags = configuredInterestHashtags()
            guard !hashtags.isEmpty else { return [] }
            return subscriptionTargets(
                relayURLs: relayURLs(for: .interests),
                filter: NostrFilter(kinds: kinds, limit: 100, tagFilters: ["t": hashtags]),
                scopeSignature: "interests:\(hashtags.joined(separator: ","))"
            )

        case .news:
            var targets: [HomeFeedLiveSubscriptionTarget] = []

            let newsRelayTargets = relayURLs(for: .news)
            targets.append(contentsOf: subscriptionTargets(
                relayURLs: newsRelayTargets,
                filter: NostrFilter(kinds: [1], limit: 100),
                scopeSignature: "news-relays"
            ))

            let authors = Array(configuredNewsAuthorPubkeys().prefix(400))
            if !authors.isEmpty {
                targets.append(contentsOf: subscriptionTargets(
                    relayURLs: newsRelayTargets,
                    filter: NostrFilter(authors: authors, kinds: [1], limit: 100),
                    scopeSignature: "news-authors:\(authors.joined(separator: ","))"
                ))
            }

            let hashtags = configuredNewsHashtags()
            if !hashtags.isEmpty {
                targets.append(contentsOf: subscriptionTargets(
                    relayURLs: newsRelayTargets,
                    filter: NostrFilter(kinds: [1], limit: 100, tagFilters: ["t": hashtags]),
                    scopeSignature: "news-hashtags:\(hashtags.joined(separator: ","))"
                ))
            }

            return deduplicatedSubscriptionTargets(targets)

        case .custom(let feedID):
            guard let feed = customFeedDefinition(id: feedID) else { return [] }

            var targets: [HomeFeedLiveSubscriptionTarget] = []
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
            let liveAuthors = Array(
                Self.followingAuthorPubkeys(
                    followingPubkeys: followingPubkeys,
                    currentUserPubkey: currentUserPubkey
                )
                .prefix(400)
            )
            .sorted()
            guard !liveAuthors.isEmpty else { return [] }
            return subscriptionTargets(
                relayURLs: relayURLs(for: .following),
                filter: NostrFilter(authors: liveAuthors, kinds: kinds, limit: 100),
                scopeSignature: "following:\(liveAuthors.joined(separator: ","))"
            )

        case .polls:
            let liveAuthors = Array(
                Self.followingAuthorPubkeys(
                    followingPubkeys: followingPubkeys,
                    currentUserPubkey: currentUserPubkey
                )
                .prefix(400)
            )
            .sorted()
            guard !liveAuthors.isEmpty else { return [] }
            return subscriptionTargets(
                relayURLs: relayURLs(for: .polls),
                filter: NostrFilter(authors: liveAuthors, kinds: FeedKindFilters.pollKinds, limit: 100),
                scopeSignature: "polls:\(liveAuthors.joined(separator: ","))"
            )
        }
    }

    private func subscriptionTargets(
        relayURLs: [URL],
        filter: NostrFilter,
        scopeSignature: String
    ) -> [HomeFeedLiveSubscriptionTarget] {
        Self.normalizedRelayURLs(relayURLs).map { relayURL in
            HomeFeedLiveSubscriptionTarget(
                relayURL: relayURL,
                filter: filter,
                signature: "\(scopeSignature)|\(relayURL.absoluteString.lowercased())"
            )
        }
    }

    private func deduplicatedSubscriptionTargets(_ targets: [HomeFeedLiveSubscriptionTarget]) -> [HomeFeedLiveSubscriptionTarget] {
        var seen = Set<String>()
        var ordered: [HomeFeedLiveSubscriptionTarget] = []

        for target in targets {
            guard seen.insert(target.signature).inserted else { continue }
            ordered.append(target)
        }

        return ordered
    }

    private func mergeItemArrays(primary: [FeedItem], secondary: [FeedItem]) -> [FeedItem] {
        var byID: [String: FeedItem] = Dictionary(uniqueKeysWithValues: secondary.map { ($0.id, $0) })

        for item in primary {
            if let existing = byID[item.id] {
                byID[item.id] = existing.merged(with: item)
            } else {
                byID[item.id] = item
            }
        }

        return byID.values.sorted {
            if $0.event.createdAt == $1.event.createdAt {
                return $0.id > $1.id
            }
            return $0.event.createdAt > $1.event.createdAt
        }
    }

    private func filterVisibleItems(_ source: [FeedItem], ignoreMediaOnly: Bool = false) -> [FeedItem] {
        let allowedKinds = Set(feedSource == .polls ? FeedKindFilters.pollKinds : showKinds)
        let hideNSFW = AppSettingsStore.shared.hideNSFWContent

        return source.filter { item in
            if !itemIsAllowedForCurrentSource(item) {
                return false
            }

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

            if feedSource != .polls {
                switch mode {
                case .posts where item.displayEvent.isReplyNote:
                    return false
                default:
                    break
                }
            }

            if feedSource != .polls && !ignoreMediaOnly && mediaOnly && !item.displayEvent.hasMedia {
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

    private func pruneItemsForSource(
        _ source: [FeedItem],
        feedSource: HomePrimaryFeedSource? = nil,
        followingPubkeys: [String]? = nil
    ) -> [FeedItem] {
        let resolvedSource = feedSource ?? self.feedSource
        switch resolvedSource {
        case .following, .polls:
            let allowedAuthors = allowedFollowingAuthors(followingPubkeys: followingPubkeys)
            guard !allowedAuthors.isEmpty else { return [] }
            return source.filter { item in
                let isAllowedAuthor = allowedAuthors.contains(self.normalizePubkey(item.displayAuthorPubkey))
                guard isAllowedAuthor else { return false }
                if resolvedSource == .polls {
                    return item.displayEvent.pollMetadata != nil
                }
                return true
            }
        default:
            return source
        }
    }

    private func itemIsAllowedForCurrentSource(_ item: FeedItem) -> Bool {
        switch feedSource {
        case .following:
            let allowedAuthors = allowedFollowingAuthors()
            guard !allowedAuthors.isEmpty else { return false }
            return allowedAuthors.contains(self.normalizePubkey(item.displayAuthorPubkey))
        case .polls:
            let allowedAuthors = allowedFollowingAuthors()
            guard !allowedAuthors.isEmpty else { return false }
            guard allowedAuthors.contains(self.normalizePubkey(item.displayAuthorPubkey)) else { return false }
            return item.displayEvent.pollMetadata != nil
        default:
            return true
        }
    }

    private func allowedFollowingAuthors(followingPubkeys: [String]? = nil) -> Set<String> {
        let followings = followingPubkeys ?? (self.followingPubkeys.isEmpty ? localFollowings() : self.followingPubkeys)
        return Set(
            Self.followingAuthorPubkeys(
                followingPubkeys: followings,
                currentUserPubkey: currentUserPubkey
            )
        )
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
        let prunedHydrated = pruneItemsForSource(pruneMutedItems(hydrated))
        guard !prunedHydrated.isEmpty else { return false }

        items = prunedHydrated
        bufferedNewItems = []
        knownEventIDs = Set(prunedHydrated.map(\.id))
        oldestCreatedAt = prunedHydrated.last?.event.createdAt
        hasReachedEnd = false
        trendingPaginationState = nil
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
            .map(normalizePubkey)
            .filter { !$0.isEmpty }
            .sorted()
    }

    private func normalizePubkey(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func followingAuthorPubkeys(
        followingPubkeys: [String],
        currentUserPubkey: String?
    ) -> [String] {
        var ordered: [String] = []
        if let currentUserPubkey {
            ordered.append(currentUserPubkey)
        }
        ordered.append(contentsOf: followingPubkeys)

        var seen = Set<String>()
        return ordered.compactMap { rawPubkey in
            let normalized = rawPubkey
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
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
        case .polls:
            return pollsFeedVisible ? .polls : .network
        case .interests:
            return interestHashtags.isEmpty ? .network : .interests
        default:
            return source
        }
    }

    private func relayURLs(for source: HomePrimaryFeedSource) -> [URL] {
        switch source {
        case .trending:
            return [Self.trendingRelayURL]
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
        case .trending:
            let combined = Self.normalizedRelayURLs(readRelayURLs + relayURLs(for: .trending))
            return combined.isEmpty ? [Self.trendingRelayURL] : combined
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
        case .polls:
            return FeedKindFilters.pollKinds
        case .trending:
            return [1]
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

    private static func initialTrendingPaginationState(referenceTime: Int) -> TrendingPaginationState {
        let safeReferenceTime = max(referenceTime, 1)
        let windowEnd = safeReferenceTime
        let windowStart = max(windowEnd - Self.trendingWindowDuration, 0)
        return TrendingPaginationState(
            windowStart: windowStart,
            windowEnd: windowEnd,
            cursor: windowEnd
        )
    }

    private static func previousTrendingPaginationState(
        before state: TrendingPaginationState
    ) -> TrendingPaginationState? {
        guard state.windowStart > 0 else { return nil }

        let nextWindowEnd = max(state.windowStart - 1, 0)
        let nextWindowStart = max(nextWindowEnd - Self.trendingWindowDuration, 0)
        return TrendingPaginationState(
            windowStart: nextWindowStart,
            windowEnd: nextWindowEnd,
            cursor: nextWindowEnd
        )
    }

    private func fetchTrendingFeedPage(
        limit: Int,
        paginationState: TrendingPaginationState?,
        hydrationMode: FeedItemHydrationMode = .full,
        fetchTimeout: TimeInterval = 12,
        relayFetchMode: RelayFetchMode = .allRelays,
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async throws -> TrendingPageFetchResult {
        guard limit > 0 else {
            return TrendingPageFetchResult(
                page: HomeFeedPageResult(items: [], hadMoreAvailable: false),
                nextState: nil
            )
        }

        let initialState = paginationState
            ?? Self.initialTrendingPaginationState(
                referenceTime: Int(Date().timeIntervalSince1970)
            )
        var state: TrendingPaginationState? = initialState
        var collected: [FeedItem] = []
        var traversedWindows = 0

        while let currentState = state, collected.count < limit {
            let remaining = max(limit - collected.count, 1)
            let fetched = try await service.fetchTrendingNotes(
                limit: remaining,
                since: currentState.windowStart,
                until: currentState.cursor,
                hydrationMode: hydrationMode,
                fetchTimeout: fetchTimeout,
                relayFetchMode: relayFetchMode,
                moderationSnapshot: moderationSnapshot
            )

            collected = mergeItemArrays(primary: collected, secondary: fetched)

            if fetched.count >= remaining,
               let oldestFetchedCreatedAt = fetched.last?.event.createdAt {
                let nextCursor = max(oldestFetchedCreatedAt - 1, 0)
                if nextCursor >= currentState.windowStart, nextCursor < currentState.cursor {
                    state = TrendingPaginationState(
                        windowStart: currentState.windowStart,
                        windowEnd: currentState.windowEnd,
                        cursor: nextCursor
                    )
                    continue
                }
            }

            guard let previousWindow = Self.previousTrendingPaginationState(before: currentState) else {
                state = nil
                break
            }

            traversedWindows += 1
            state = previousWindow

            if traversedWindows >= Self.trendingBackfillWindowLimitPerPage, collected.isEmpty {
                return TrendingPageFetchResult(
                    page: HomeFeedPageResult(items: [], hadMoreAvailable: true),
                    nextState: state
                )
            }
        }

        let pageItems = Array(collected.prefix(limit))
        return TrendingPageFetchResult(
            page: HomeFeedPageResult(
                items: pageItems,
                hadMoreAvailable: state != nil
            ),
            nextState: state
        )
    }

    private func fetchFollowingFeedPage(
        relayURLs: [URL],
        authors: [String],
        kinds: [Int],
        limit: Int,
        until: Int?,
        hydrationMode: FeedItemHydrationMode = .full,
        fetchTimeout: TimeInterval = 12,
        relayFetchMode: RelayFetchMode = .allRelays,
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async throws -> HomeFeedPageResult {
        guard limit > 0, !authors.isEmpty else {
            return HomeFeedPageResult(items: [], hadMoreAvailable: false)
        }

        let probeLimit = min(max(limit * 4, 120), 240)
        let maxBackfillRounds = 6
        var collected: [FeedItem] = []
        var cursor = until
        var exhausted = false
        var lastBatchCount = 0
        var roundsCompleted = 0

        while roundsCompleted < maxBackfillRounds && collected.count < limit {
            let fetched = try await service.fetchFollowingFeed(
                relayURLs: relayURLs,
                authors: authors,
                kinds: kinds,
                limit: probeLimit,
                until: cursor,
                hydrationMode: hydrationMode,
                fetchTimeout: fetchTimeout,
                relayFetchMode: relayFetchMode,
                moderationSnapshot: moderationSnapshot
            )
            lastBatchCount = fetched.count

            guard !fetched.isEmpty else {
                exhausted = true
                break
            }

            collected = mergeItemArrays(primary: collected, secondary: fetched)

            if collected.count > limit || fetched.count >= probeLimit {
                break
            }

            guard let oldestFetchedCreatedAt = fetched.last?.event.createdAt else {
                exhausted = true
                break
            }

            let nextCursor = max(oldestFetchedCreatedAt - 1, 0)
            guard nextCursor > 0, nextCursor != cursor else {
                exhausted = true
                break
            }

            cursor = nextCursor
            roundsCompleted += 1
        }

        let pageItems = Array(collected.prefix(limit))
        let hadMoreAvailable =
            collected.count > limit ||
            lastBatchCount >= probeLimit ||
            (!exhausted && !pageItems.isEmpty)

        return HomeFeedPageResult(
            items: pageItems,
            hadMoreAvailable: hadMoreAvailable
        )
    }

    private func fetchInterestsFeedPage(
        limit: Int,
        until: Int?,
        hydrationMode: FeedItemHydrationMode = .full,
        fetchTimeout: TimeInterval = 12,
        relayFetchMode: RelayFetchMode = .allRelays,
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async throws -> HomeFeedPageResult {
        let hashtags = configuredInterestHashtags()
        guard !hashtags.isEmpty else {
            return HomeFeedPageResult(items: [], hadMoreAvailable: false)
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
        return HomeFeedPageResult(
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
    ) async throws -> HomeFeedPageResult {
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
                relayURLs: newsRelayURLs,
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
                            relayURLs: newsRelayURLs,
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
                    seenEventIDs.insert(event.id.lowercased()).inserted
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

        return HomeFeedPageResult(
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
    ) async throws -> HomeFeedPageResult {
        guard limit > 0 else {
            return HomeFeedPageResult(items: [], hadMoreAvailable: false)
        }

        let relayTargets = relayURLs(for: .custom(feed.id))
        let authors = Array(feed.authorPubkeys.prefix(400))
        let hashtags = feed.hashtags
        let phrases = feed.phrases

        guard !authors.isEmpty || !hashtags.isEmpty || !phrases.isEmpty else {
            return HomeFeedPageResult(items: [], hadMoreAvailable: false)
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
        async let hashtagItemsTask = fetchCustomFeedHashtagItems(
            hashtags: hashtags,
            relayTargets: relayTargets,
            kinds: kinds,
            limit: perHashtagLimit,
            until: until,
            hydrationMode: hydrationMode,
            fetchTimeout: fetchTimeout,
            relayFetchMode: relayFetchMode,
            moderationSnapshot: moderationSnapshot
        )
        async let phraseItemsTask = fetchCustomFeedPhraseItems(
            phrases: phrases,
            relayTargets: relayTargets,
            kinds: kinds,
            limit: perPhraseLimit,
            until: until,
            hydrationMode: hydrationMode,
            fetchTimeout: fetchTimeout,
            relayFetchMode: relayFetchMode,
            moderationSnapshot: moderationSnapshot
        )

        let authorItems = try await authorItemsTask
        let hashtagItems = try await hashtagItemsTask
        let phraseItems = try await phraseItemsTask

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

        return HomeFeedPageResult(
            items: limitedItems,
            hadMoreAvailable: hadMoreAvailable
        )
    }

    private func fetchCustomFeedHashtagItems(
        hashtags: [String],
        relayTargets: [URL],
        kinds: [Int],
        limit: Int,
        until: Int?,
        hydrationMode: FeedItemHydrationMode,
        fetchTimeout: TimeInterval,
        relayFetchMode: RelayFetchMode,
        moderationSnapshot: MuteFilterSnapshot?
    ) async throws -> [[FeedItem]] {
        guard !hashtags.isEmpty, limit > 0 else { return [] }

        return try await withThrowingTaskGroup(of: [FeedItem].self) { group in
            for hashtag in hashtags {
                group.addTask { [self] in
                    try await self.service.fetchHashtagFeed(
                        relayURLs: relayTargets,
                        hashtag: hashtag,
                        kinds: kinds,
                        limit: limit,
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

    private func fetchCustomFeedPhraseItems(
        phrases: [String],
        relayTargets: [URL],
        kinds: [Int],
        limit: Int,
        until: Int?,
        hydrationMode: FeedItemHydrationMode,
        fetchTimeout: TimeInterval,
        relayFetchMode: RelayFetchMode,
        moderationSnapshot: MuteFilterSnapshot?
    ) async throws -> [[FeedItem]] {
        guard !phrases.isEmpty, limit > 0 else { return [] }

        return try await withThrowingTaskGroup(of: [FeedItem].self) { group in
            for phrase in phrases {
                group.addTask { [self] in
                    let localItems = await self.service.searchLocalNotes(
                        query: phrase,
                        kinds: kinds,
                        limit: limit,
                        until: until,
                        hydrationMode: hydrationMode,
                        moderationSnapshot: moderationSnapshot
                    )

                    let remoteItems: [FeedItem]
                    do {
                        remoteItems = try await self.service.searchNotes(
                            relayURLs: relayTargets,
                            query: phrase,
                            kinds: kinds,
                            limit: limit,
                            until: until,
                            hydrationMode: hydrationMode,
                            fetchTimeout: fetchTimeout,
                            relayFetchMode: relayFetchMode,
                            moderationSnapshot: moderationSnapshot
                        )
                    } catch {
                        remoteItems = []
                    }

                    var byID: [String: FeedItem] = Dictionary(
                        uniqueKeysWithValues: remoteItems.map { ($0.id, $0) }
                    )

                    for item in localItems {
                        if let existing = byID[item.id] {
                            byID[item.id] = existing.merged(with: item)
                        } else {
                            byID[item.id] = item
                        }
                    }

                    return byID.values.sorted {
                        if $0.event.createdAt == $1.event.createdAt {
                            return $0.id > $1.id
                        }
                        return $0.event.createdAt > $1.event.createdAt
                    }
                }
            }

            var merged: [[FeedItem]] = []
            for try await items in group {
                merged.append(items)
            }
            return merged
        }
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

            let authorHydrated = await self.service.buildAuthorHydratedFeedItems(
                relayURLs: relayTargets,
                events: events,
                fetchTimeout: Self.fastHomeFetchTimeout,
                relayFetchMode: Self.fastHomeRelayFetchMode,
                moderationSnapshot: self.muteFilterSnapshot
            )
            guard !Task.isCancelled else { return }
            if !authorHydrated.isEmpty {
                await MainActor.run {
                    guard self.feedSource == source, self.currentUserPubkey == userPubkey else {
                        return
                    }

                    self.items = self.pruneItemsForSource(
                        self.pruneMutedItems(
                            self.mergeItemArrays(primary: authorHydrated, secondary: self.items)
                        ),
                        feedSource: source
                    )
                    self.scheduleAssetPrefetch(for: self.items)
                    self.knownEventIDs = Set(self.items.map(\.id))
                    self.knownEventIDs.formUnion(self.bufferedNewItems.map(\.id))
                }
            }

            let fullyHydrated = await self.service.buildFeedItems(
                relayURLs: relayTargets,
                events: events,
                hydrationMode: .full,
                moderationSnapshot: self.muteFilterSnapshot
            )
            guard !Task.isCancelled else { return }
            guard !fullyHydrated.isEmpty else { return }

            await MainActor.run {
                guard self.feedSource == source, self.currentUserPubkey == userPubkey else {
                    return
                }

                self.items = self.pruneItemsForSource(
                    self.pruneMutedItems(
                        self.mergeItemArrays(primary: fullyHydrated, secondary: self.items)
                    ),
                    feedSource: source
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
