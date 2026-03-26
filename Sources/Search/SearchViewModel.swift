import Foundation
import NostrSDK

@MainActor
final class SearchViewModel: ObservableObject {
    private struct MentionMetadataDecoder: MetadataCoding {}

    private struct VisibleItemsCacheKey: Equatable {
        let trendingRevision: Int
        let searchedRevision: Int
        let isSearching: Bool
        let hideNSFW: Bool
        let filterRevision: Int
        let mutedConversationRevision: Int
    }

    struct ProfileMatch: Identifiable, Hashable {
        let pubkey: String
        let profile: NostrProfile?

        var id: String { pubkey }

        var displayName: String {
            if let displayName = normalized(profile?.displayName), !displayName.isEmpty {
                return displayName
            }
            if let name = normalized(profile?.name), !name.isEmpty {
                return name
            }
            return shortNostrIdentifier(pubkey)
        }

        var handle: String {
            if let name = normalized(profile?.name), !name.isEmpty {
                return "@\(name.replacingOccurrences(of: " ", with: "").lowercased())"
            }
            return "@\(shortNostrIdentifier(pubkey).lowercased())"
        }

        var avatarURL: URL? {
            guard let value = normalized(profile?.picture), !value.isEmpty else { return nil }
            return URL(string: value)
        }
        private func normalized(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    typealias TrendingNotesLoader = (
        _ service: NostrFeedService,
        _ relayURLs: [URL],
        _ limit: Int,
        _ until: Int?,
        _ moderationSnapshot: MuteFilterSnapshot?
    ) async throws -> [FeedItem]

    private struct FeedFetchResult {
        let items: [FeedItem]
        let failed: Bool

        static let empty = FeedFetchResult(items: [], failed: false)
    }

    private struct ProfileFetchResult {
        let items: [ProfileSearchResult]
        let failed: Bool

        static let empty = ProfileFetchResult(items: [], failed: false)
    }

    @Published var searchText = ""
    @Published private(set) var trendingNotes: [FeedItem] = [] {
        didSet {
            trendingNotesRevision &+= 1
            clearVisibleItemsCache()
        }
    }
    @Published private(set) var searchedNotes: [FeedItem] = [] {
        didSet {
            searchedNotesRevision &+= 1
            clearVisibleItemsCache()
        }
    }
    @Published private(set) var profileMatches: [ProfileMatch] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?

    private let service: NostrFeedService
    private let trendingNotesLoader: TrendingNotesLoader
    private let pageSize: Int
    private let assetPrefetchItemCount = 18

    private var mutedConversationIDs = Set<String>() {
        didSet {
            mutedConversationRevision &+= 1
            clearVisibleItemsCache()
        }
    }
    private var searchTask: Task<Void, Never>?
    private var latestSearchRequestID = UUID()
    private var trendingNotesRevision = 0
    private var searchedNotesRevision = 0
    private var mutedConversationRevision = 0
    private var visibleItemsCacheKey: VisibleItemsCacheKey?
    private var visibleItemsCache: [FeedItem] = []

    private(set) var readRelayURLs: [URL]
    private(set) var relayURL: URL

    private static let searchableRelayURLs: [URL] = [
        URL(string: "wss://search.nos.today/")
    ].compactMap { $0 }

    private static let bigRelayURLs: [URL] = [
        URL(string: "wss://relay.damus.io/"),
        URL(string: "wss://nos.lol/"),
        URL(string: "wss://relay.nostr.band/"),
        URL(string: "wss://nostr.mom/")
    ].compactMap { $0 }

    private static let searchFeedKinds = [1, 6, 20, 21, 22, 1063, 1222, 30023, 1111, 1244]
    private static let noteSearchFetchTimeout: TimeInterval = 5
    private static let profileSearchFetchTimeout: TimeInterval = 6
    private static let noteSearchRelayFetchMode: RelayFetchMode = .firstNonEmptyRelay
    private static let profileSearchRelayFetchMode: RelayFetchMode = .firstNonEmptyRelay

    init(
        relayURL: URL,
        readRelayURLs: [URL]? = nil,
        pageSize: Int = 100,
        service: NostrFeedService = NostrFeedService(),
        trendingNotesLoader: @escaping TrendingNotesLoader = SearchViewModel.defaultTrendingNotesLoader
    ) {
        let normalizedReadRelayURLs = Self.normalizedRelayURLs(readRelayURLs ?? [relayURL])
        let initialReadRelayURLs = normalizedReadRelayURLs.isEmpty ? [relayURL] : normalizedReadRelayURLs

        self.readRelayURLs = initialReadRelayURLs
        self.relayURL = initialReadRelayURLs.first ?? relayURL
        self.pageSize = pageSize
        self.service = service
        self.trendingNotesLoader = trendingNotesLoader
    }

    deinit {
        searchTask?.cancel()
    }

    var visibleItems: [FeedItem] {
        let key = VisibleItemsCacheKey(
            trendingRevision: trendingNotesRevision,
            searchedRevision: searchedNotesRevision,
            isSearching: isSearching,
            hideNSFW: AppSettingsStore.shared.hideNSFWContent,
            filterRevision: MuteStore.shared.filterRevision,
            mutedConversationRevision: mutedConversationRevision
        )

        if visibleItemsCacheKey == key {
            return visibleItemsCache
        }

        let source = isSearching ? searchedNotes : trendingNotes
        let filtered = filteredItems(source)
        visibleItemsCacheKey = key
        visibleItemsCache = filtered
        return filtered
    }

    private var muteFilterSnapshot: MuteFilterSnapshot {
        MuteStore.shared.filterSnapshot
    }

    var isSearching: Bool {
        !trimmedSearchQuery.isEmpty
    }

    var hasAnySearchResults: Bool {
        !profileMatches.isEmpty || !visibleItems.isEmpty
    }

    func handleSearchTextChanged() {
        searchTask?.cancel()

        let query = trimmedSearchQuery
        guard !query.isEmpty else {
            latestSearchRequestID = UUID()
            searchedNotes = []
            profileMatches = []
            errorMessage = nil
            isLoading = false
            return
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }
            await self?.performSearch()
        }
    }

    func updateReadRelayURLs(_ newReadRelayURLs: [URL]) {
        let normalized = Self.normalizedRelayURLs(newReadRelayURLs)
        guard !normalized.isEmpty else { return }

        let current = readRelayURLs.map { $0.absoluteString.lowercased() }
        let next = normalized.map { $0.absoluteString.lowercased() }
        guard current != next else { return }

        readRelayURLs = normalized
        relayURL = normalized[0]

        if isSearching {
            handleSearchTextChanged()
        } else {
            trendingNotes.removeAll()
            errorMessage = nil
        }
    }

    func loadIfNeeded() async {
        if isSearching {
            await performSearch()
            return
        }

        if trendingNotes.isEmpty {
            await refreshTrending()
        }
    }

    func refresh() async {
        if isSearching {
            await performSearch()
            return
        }

        await refreshTrending()
    }

    func loadMoreIfNeeded(currentItem: FeedItem) async {
        // Search and trending are currently loaded in one window.
        _ = currentItem
    }

    func muteConversation(_ conversationID: String) {
        let normalized = conversationID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return }
        guard mutedConversationIDs.insert(normalized).inserted else { return }

        trendingNotes.removeAll { $0.event.conversationID == normalized }
        searchedNotes.removeAll { $0.event.conversationID == normalized }
    }

    private func refreshTrending() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        let requestRelayURLs = readRelayURLs

        defer {
            isLoading = false
        }

        do {
            let fetched = try await trendingNotesLoader(
                service,
                requestRelayURLs,
                pageSize,
                nil,
                muteFilterSnapshot
            )

            guard requestRelayURLs == readRelayURLs else { return }
            let merged = deduplicateAndSort([fetched])
            trendingNotes = merged
            scheduleAssetPrefetch(for: merged)
        } catch {
            errorMessage = "Couldn't load trending notes. Pull to refresh and try again."
        }
    }

    private func performSearch() async {
        let query = trimmedSearchQuery
        guard !query.isEmpty else {
            searchedNotes = []
            profileMatches = []
            errorMessage = nil
            isLoading = false
            return
        }

        let requestID = UUID()
        latestSearchRequestID = requestID
        isLoading = true
        errorMessage = nil
        searchedNotes = []
        profileMatches = []

        let keywordRelayURLs = keywordSearchRelayTargets()
        let keywordFallbackRelayURLs = fallbackKeywordSearchRelayTargets()
        let hashtagRelayURLs = hashtagSearchRelayTargets()
        let profileRelayURLs = profileSearchRelayTargets()
        let hashtag = normalizedHashtag(from: query)
        let normalizedProfileQuery = normalizedProfileQuery(from: query)
        let exactPubkey = resolvedProfilePubkey(from: query)

        async let keywordNotesResult = fetchKeywordNotes(
            query: query,
            primaryRelayURLs: keywordRelayURLs,
            fallbackRelayURLs: keywordFallbackRelayURLs
        )
        async let hashtagNotesResult = fetchHashtagNotes(hashtag: hashtag, relayURLs: hashtagRelayURLs)
        async let profileMatchesResult = fetchProfileMatches(
            query: normalizedProfileQuery,
            relayURLs: profileRelayURLs
        )
        async let exactAuthorNotesResult = fetchExactAuthorNotes(
            pubkey: exactPubkey,
            relayURLs: profileRelayURLs
        )
        async let exactProfileResult = fetchExactProfile(
            pubkey: exactPubkey,
            relayURLs: profileRelayURLs
        )

        let keywordNotes = await keywordNotesResult
        let hashtagNotes = await hashtagNotesResult
        let exactAuthorNotes = await exactAuthorNotesResult

        guard latestSearchRequestID == requestID else { return }
        guard trimmedSearchQuery == query else { return }

        let initialNotes = deduplicateAndSort([
            keywordNotes.items,
            hashtagNotes.items,
            exactAuthorNotes.items
        ])
        let initialPrefetchedNotes = Array(initialNotes.prefix(pageSize))
        self.searchedNotes = initialPrefetchedNotes
        scheduleAssetPrefetch(for: initialPrefetchedNotes)

        var profileMatches = await profileMatchesResult
        let exactProfile = await exactProfileResult

        if let exactProfile {
            let normalizedExactPubkey = exactProfile.pubkey.lowercased()
            if !profileMatches.items.contains(where: { $0.pubkey.lowercased() == normalizedExactPubkey }) {
                profileMatches = ProfileFetchResult(
                    items: [exactProfile] + profileMatches.items,
                    failed: profileMatches.failed
                )
            }
        }

        var profileAuthoredNotes = FeedFetchResult.empty
        let profileAuthorPubkeys = Array(
            Set(profileMatches.items.map { $0.pubkey.lowercased() }).prefix(12)
        )
        if !profileAuthorPubkeys.isEmpty {
            profileAuthoredNotes = await fetchProfileAuthoredNotes(
                pubkeys: profileAuthorPubkeys,
                relayURLs: profileRelayURLs
            )
        }

        guard latestSearchRequestID == requestID else { return }
        guard trimmedSearchQuery == query else { return }

        let mergedProfiles = deduplicateProfiles(profileMatches.items)
        let mergedNotes = deduplicateAndSort([
            keywordNotes.items,
            hashtagNotes.items,
            exactAuthorNotes.items,
            profileAuthoredNotes.items
        ])

        self.profileMatches = mergedProfiles.map {
            ProfileMatch(pubkey: $0.pubkey, profile: $0.profile)
        }
        let mergedPrefetchedNotes = Array(mergedNotes.prefix(pageSize))
        self.searchedNotes = mergedPrefetchedNotes
        scheduleAssetPrefetch(for: mergedPrefetchedNotes)

        let hadNetworkFailures =
            keywordNotes.failed ||
            hashtagNotes.failed ||
            exactAuthorNotes.failed ||
            profileMatches.failed ||
            profileAuthoredNotes.failed

        if self.profileMatches.isEmpty && self.searchedNotes.isEmpty && hadNetworkFailures {
            errorMessage = "Couldn't search right now. Pull to refresh and try again."
        } else {
            errorMessage = nil
        }

        isLoading = false
    }

    private func fetchKeywordNotes(
        query: String,
        primaryRelayURLs: [URL],
        fallbackRelayURLs: [URL]
    ) async -> FeedFetchResult {
        let primary = await performKeywordNoteSearch(query: query, relayURLs: primaryRelayURLs)
        if !primary.items.isEmpty {
            return primary
        }

        let normalizedFallback = Self.normalizedRelayURLs(fallbackRelayURLs)
        let normalizedPrimary = Self.normalizedRelayURLs(primaryRelayURLs)
        let fallbackKeys = normalizedFallback.map { $0.absoluteString.lowercased() }
        let primaryKeys = normalizedPrimary.map { $0.absoluteString.lowercased() }
        guard fallbackKeys != primaryKeys else {
            return primary
        }

        let fallback = await performKeywordNoteSearch(query: query, relayURLs: normalizedFallback)
        if !fallback.items.isEmpty {
            return fallback
        }

        return FeedFetchResult(
            items: [],
            failed: primary.failed || fallback.failed
        )
    }

    private func performKeywordNoteSearch(query: String, relayURLs: [URL]) async -> FeedFetchResult {
        guard !relayURLs.isEmpty else { return .empty }
        do {
            let items = try await service.searchNotes(
                relayURLs: relayURLs,
                query: query,
                kinds: Self.searchFeedKinds,
                limit: pageSize,
                hydrationMode: .cachedProfilesOnly,
                fetchTimeout: Self.noteSearchFetchTimeout,
                relayFetchMode: Self.noteSearchRelayFetchMode,
                moderationSnapshot: muteFilterSnapshot
            )
            return FeedFetchResult(items: items, failed: false)
        } catch {
            return FeedFetchResult(items: [], failed: true)
        }
    }

    private func fetchHashtagNotes(hashtag: String?, relayURLs: [URL]) async -> FeedFetchResult {
        guard let hashtag, !hashtag.isEmpty else { return .empty }
        do {
            let hashtagRelayURLs = Self.normalizedRelayURLs(relayURLs + Self.bigRelayURLs)
            let items = try await service.fetchHashtagFeed(
                relayURLs: hashtagRelayURLs,
                hashtag: hashtag,
                kinds: Self.searchFeedKinds,
                limit: pageSize,
                until: nil,
                hydrationMode: .cachedProfilesOnly,
                fetchTimeout: Self.noteSearchFetchTimeout,
                relayFetchMode: Self.noteSearchRelayFetchMode,
                moderationSnapshot: muteFilterSnapshot
            )
            return FeedFetchResult(items: items, failed: false)
        } catch {
            return FeedFetchResult(items: [], failed: true)
        }
    }

    private func fetchProfileMatches(query: String, relayURLs: [URL]) async -> ProfileFetchResult {
        guard !query.isEmpty else { return .empty }
        do {
            let matches = try await service.searchProfiles(
                relayURLs: relayURLs,
                query: query,
                limit: 12,
                fetchTimeout: Self.profileSearchFetchTimeout,
                relayFetchMode: Self.profileSearchRelayFetchMode
            )
            return ProfileFetchResult(items: matches, failed: false)
        } catch {
            return ProfileFetchResult(items: [], failed: true)
        }
    }

    private func fetchExactAuthorNotes(pubkey: String?, relayURLs: [URL]) async -> FeedFetchResult {
        guard let pubkey, !pubkey.isEmpty else { return .empty }
        do {
            let items = try await service.fetchFollowingFeed(
                relayURLs: relayURLs,
                authors: [pubkey],
                kinds: Self.searchFeedKinds,
                limit: pageSize,
                until: nil,
                hydrationMode: .cachedProfilesOnly,
                fetchTimeout: Self.noteSearchFetchTimeout,
                relayFetchMode: Self.noteSearchRelayFetchMode,
                moderationSnapshot: muteFilterSnapshot
            )
            return FeedFetchResult(items: items, failed: false)
        } catch {
            return FeedFetchResult(items: [], failed: true)
        }
    }

    private func fetchProfileAuthoredNotes(pubkeys: [String], relayURLs: [URL]) async -> FeedFetchResult {
        guard !pubkeys.isEmpty else { return .empty }
        do {
            let items = try await service.fetchFollowingFeed(
                relayURLs: relayURLs,
                authors: pubkeys,
                kinds: Self.searchFeedKinds,
                limit: pageSize,
                until: nil,
                hydrationMode: .cachedProfilesOnly,
                fetchTimeout: Self.noteSearchFetchTimeout,
                relayFetchMode: Self.noteSearchRelayFetchMode,
                moderationSnapshot: muteFilterSnapshot
            )
            return FeedFetchResult(items: items, failed: false)
        } catch {
            return FeedFetchResult(items: [], failed: true)
        }
    }

    private func fetchExactProfile(pubkey: String?, relayURLs: [URL]) async -> ProfileSearchResult? {
        guard let pubkey, !pubkey.isEmpty else { return nil }
        let profile = await service.fetchProfile(
            relayURLs: relayURLs,
            pubkey: pubkey,
            fetchTimeout: Self.profileSearchFetchTimeout,
            relayFetchMode: Self.profileSearchRelayFetchMode
        )
        return ProfileSearchResult(pubkey: pubkey, profile: profile, createdAt: Int(Date().timeIntervalSince1970))
    }

    private func filteredItems(_ items: [FeedItem]) -> [FeedItem] {
        let hideNSFW = AppSettingsStore.shared.hideNSFWContent
        return items.filter { item in
            if mutedConversationIDs.contains(item.displayEvent.conversationID) {
                return false
            }
            if MuteStore.shared.shouldHideAny(item.moderationEvents) {
                return false
            }
            if hideNSFW && item.moderationEvents.contains(where: { $0.containsNSFWHashtag }) {
                return false
            }
            return true
        }
    }

    private func pruneMutedItems(
        _ items: [FeedItem],
        snapshot: MuteFilterSnapshot? = nil
    ) -> [FeedItem] {
        let snapshot = snapshot ?? muteFilterSnapshot
        guard snapshot.hasAnyRules else { return items }

        return items.filter { item in
            !snapshot.shouldHideAny(in: item.moderationEvents)
        }
    }

    private func scheduleAssetPrefetch(for items: [FeedItem]) {
        let urls = Array(
            items
                .prefix(assetPrefetchItemCount)
                .flatMap(\.prefetchImageURLs)
        )
        guard !urls.isEmpty else { return }

        Task(priority: .utility) {
            await FlowImageCache.shared.prefetch(urls: urls)
        }
    }

    private func clearVisibleItemsCache() {
        visibleItemsCacheKey = nil
        visibleItemsCache = []
    }

    private func deduplicateAndSort(_ groups: [[FeedItem]]) -> [FeedItem] {
        var byID: [String: FeedItem] = [:]

        for group in groups {
            for item in group {
                byID[item.id.lowercased()] = item
            }
        }

        return pruneMutedItems(byID.values.sorted {
            if $0.event.createdAt == $1.event.createdAt {
                return $0.id > $1.id
            }
            return $0.event.createdAt > $1.event.createdAt
        })
    }

    private func deduplicateProfiles(_ profiles: [ProfileSearchResult]) -> [ProfileSearchResult] {
        var byPubkey: [String: ProfileSearchResult] = [:]

        for profile in profiles {
            let normalizedPubkey = profile.pubkey.lowercased()
            if let existing = byPubkey[normalizedPubkey], existing.createdAt > profile.createdAt {
                continue
            }
            byPubkey[normalizedPubkey] = profile
        }

        return byPubkey.values.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.pubkey < $1.pubkey
            }
            return $0.createdAt > $1.createdAt
        }
    }

    private var trimmedSearchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedProfileQuery(from query: String) -> String {
        var value = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("@") {
            value.removeFirst()
        }
        return value
    }

    private func normalizedHashtag(from query: String) -> String? {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.hasPrefix("#") else { return nil }

        let raw = value
            .drop(while: { $0 == "#" })
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init) ?? ""
        let hashtag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return hashtag.isEmpty ? nil : hashtag
    }

    private func resolvedProfilePubkey(from query: String) -> String? {
        let normalized = normalizedIdentifier(from: query)
        guard !normalized.isEmpty else { return nil }

        if normalized.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil {
            return normalized
        }

        if normalized.hasPrefix("npub1") {
            return PublicKey(npub: normalized)?.hex.lowercased()
        }

        if normalized.hasPrefix("nprofile1") {
            let decoder = MentionMetadataDecoder()
            let metadata = try? decoder.decodedMetadata(from: normalized)
            return metadata?.pubkey?.lowercased()
        }

        return nil
    }

    private func normalizedIdentifier(from raw: String) -> String {
        let lowered = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if lowered.hasPrefix("nostr:") {
            return String(lowered.dropFirst("nostr:".count))
        }
        return lowered
    }

    private func keywordSearchRelayTargets() -> [URL] {
        Self.normalizedRelayURLs(Self.searchableRelayURLs)
    }

    private func fallbackKeywordSearchRelayTargets() -> [URL] {
        Self.normalizedRelayURLs(Self.bigRelayURLs + readRelayURLs)
    }

    private func hashtagSearchRelayTargets() -> [URL] {
        Self.normalizedRelayURLs(readRelayURLs + Self.bigRelayURLs)
    }

    private func profileSearchRelayTargets() -> [URL] {
        Self.normalizedRelayURLs(Self.searchableRelayURLs + Self.bigRelayURLs + readRelayURLs)
    }

    private static func defaultTrendingNotesLoader(
        service: NostrFeedService,
        relayURLs: [URL],
        limit: Int,
        until: Int?,
        moderationSnapshot: MuteFilterSnapshot?
    ) async throws -> [FeedItem] {
        _ = relayURLs
        _ = until
        return try await service.fetchTrendingNotes(
            limit: min(limit, 100),
            moderationSnapshot: moderationSnapshot
        )
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
