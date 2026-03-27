import Foundation
import NostrSDK

struct FollowListSnapshot: Codable, Sendable {
    let content: String
    let tags: [[String]]

    var followedPubkeys: [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            guard let name = tag.first?.lowercased(), name == "p" else { return nil }
            guard tag.count > 1 else { return nil }
            let value = tag[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !value.isEmpty else { return nil }
            guard Self.isValidHexPubkey(value) else { return nil }
            guard seen.insert(value).inserted else { return nil }
            return value
        }
    }

    var nonPubkeyTags: [[String]] {
        tags.filter { tag in
            tag.first?.lowercased() != "p"
        }
    }

    var relayHintsByPubkey: [String: [URL]] {
        var hintsByPubkey: [String: [URL]] = [:]
        var seenByPubkey: [String: Set<String>] = [:]

        for tag in tags {
            guard let name = tag.first?.lowercased(), name == "p" else { continue }
            guard tag.count > 1 else { continue }

            let pubkey = tag[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard Self.isValidHexPubkey(pubkey) else { continue }

            for candidate in tag.dropFirst(2) {
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                guard trimmed.lowercased().hasPrefix("ws://") || trimmed.lowercased().hasPrefix("wss://") else {
                    continue
                }
                guard let url = URL(string: trimmed) else { continue }

                let normalizedURL = url.absoluteString.lowercased()
                if seenByPubkey[pubkey, default: []].insert(normalizedURL).inserted {
                    hintsByPubkey[pubkey, default: []].append(url)
                }
            }
        }

        return hintsByPubkey
    }

    private static func isValidHexPubkey(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }
}

struct ProfileSearchResult: Identifiable, Hashable, Sendable {
    let pubkey: String
    let profile: NostrProfile?
    let createdAt: Int

    var id: String { pubkey }
}

enum VertexProfileSearchError: LocalizedError {
    case invalidCredentials
    case queryTooShort
    case invalidRequest
    case invalidResponse
    case untrustedResponse
    case requestRejected(String)
    case serviceUnavailable(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Search requires a signed-in private key right now."
        case .queryTooShort:
            return "Search terms must be longer than three characters."
        case .invalidRequest:
            return "Couldn't prepare the search request."
        case .invalidResponse:
            return "Vertex returned an invalid search response."
        case .untrustedResponse:
            return "Vertex search response could not be trusted."
        case .requestRejected(let message):
            return message
        case .serviceUnavailable(let statusCode):
            return "Vertex search is unavailable right now (\(statusCode))."
        }
    }
}

private struct VertexProfileMatch: Codable, Sendable {
    let pubkey: String
    let rank: Double?
}

actor VertexProfileSearchService {
    static let shared = VertexProfileSearchService()

    nonisolated static let relayURL = URL(string: "wss://relay.vertexlab.io")!

    private static let apiURL = URL(string: "https://relay.vertexlab.io/api/v1/dvms")!
    private static let requestKind = 5_315
    private static let responseKind = 6_315
    private static let errorKind = 7_000
    private static let trustedResponsePubkey = "b0565a0d950477811f35ff76e5981ede67a90469a97feec13dc17f36290debfe"

    private let cacheTTL: TimeInterval = 60 * 15
    private var searchCache: [String: (matches: [VertexProfileMatch], createdAt: Int, storedAt: Date)] = [:]

    func searchProfiles(
        query: String,
        limit: Int,
        nsec: String,
        relayURLs: [URL],
        feedService: NostrFeedService = NostrFeedService()
    ) async throws -> [ProfileSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.count > 3 else {
            throw VertexProfileSearchError.queryTooShort
        }

        let normalizedNsec = nsec.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let keypair = Keypair(nsec: normalizedNsec) else {
            throw VertexProfileSearchError.invalidCredentials
        }

        let clampedLimit = min(max(limit, 1), 100)
        let cacheKey = "\(normalizedQuery.lowercased())|\(clampedLimit)"

        let cached = cachedSearch(for: cacheKey)
        let rawMatches: [VertexProfileMatch]
        let createdAt: Int

        if let cached {
            rawMatches = cached.matches
            createdAt = cached.createdAt
        } else {
            let searchResult = try await performSearchRequest(
                query: normalizedQuery,
                limit: clampedLimit,
                keypair: keypair
            )
            rawMatches = searchResult.matches
            createdAt = searchResult.createdAt
            searchCache[cacheKey] = (matches: rawMatches, createdAt: createdAt, storedAt: Date())
        }

        let pubkeys = normalizedPubkeys(from: rawMatches)
        guard !pubkeys.isEmpty else { return [] }

        let profileRelayTargets = normalizedRelayURLs([Self.relayURL] + relayURLs)
        let profilesByPubkey = await feedService.fetchProfiles(
            relayURLs: profileRelayTargets,
            pubkeys: pubkeys
        )

        return pubkeys.enumerated().map { index, pubkey in
            ProfileSearchResult(
                pubkey: pubkey,
                profile: profilesByPubkey[pubkey],
                createdAt: createdAt - index
            )
        }
    }

    private func performSearchRequest(
        query: String,
        limit: Int,
        keypair: Keypair
    ) async throws -> (matches: [VertexProfileMatch], createdAt: Int) {
        let requestEvent = try makeRequestEvent(query: query, limit: limit, keypair: keypair)

        let requestData = try JSONEncoder().encode(requestEvent)
        var request = URLRequest(url: Self.apiURL)
        request.httpMethod = "POST"
        request.httpBody = requestData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VertexProfileSearchError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw VertexProfileSearchError.serviceUnavailable(statusCode: httpResponse.statusCode)
        }

        let responseEvent = try JSONDecoder().decode(NostrEvent.self, from: responseData)
        try validateResponseEvent(responseEvent, requestID: requestEvent.id, requesterPubkey: keypair.publicKey.hex)

        if responseEvent.kind == Self.errorKind {
            let message = responseStatusMessage(from: responseEvent.tags) ?? "Vertex search failed."
            throw VertexProfileSearchError.requestRejected(message)
        }

        guard responseEvent.kind == Self.responseKind else {
            throw VertexProfileSearchError.invalidResponse
        }

        guard let contentData = responseEvent.content.data(using: .utf8) else {
            throw VertexProfileSearchError.invalidResponse
        }

        let decodedMatches = try JSONDecoder().decode([VertexProfileMatch].self, from: contentData)
        return (decodedMatches, responseEvent.createdAt)
    }

    private func makeRequestEvent(
        query: String,
        limit: Int,
        keypair: Keypair
    ) throws -> NostrSDK.NostrEvent {
        let rawTags = [
            ["param", "search", query],
            ["param", "limit", "\(limit)"],
            ["param", "sort", "globalPagerank"]
        ]
        let sdkTags = rawTags.compactMap(decodeSDKTag(from:))

        let event = try NostrSDK.NostrEvent.Builder<NostrSDK.NostrEvent>(kind: .unknown(Self.requestKind))
            .content("")
            .appendTags(contentsOf: sdkTags)
            .build(signedBy: keypair)

        guard !event.id.isEmpty else {
            throw VertexProfileSearchError.invalidRequest
        }
        return event
    }

    private func validateResponseEvent(
        _ responseEvent: NostrEvent,
        requestID: String,
        requesterPubkey: String
    ) throws {
        guard responseEvent.pubkey.lowercased() == Self.trustedResponsePubkey else {
            throw VertexProfileSearchError.untrustedResponse
        }

        let normalizedRequestID = requestID.lowercased()
        let normalizedRequesterPubkey = requesterPubkey.lowercased()

        let referencesRequest = responseEvent.tags.contains { tag in
            guard let name = tag.first?.lowercased(), name == "e", tag.count > 1 else { return false }
            return tag[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedRequestID
        }
        guard referencesRequest else {
            throw VertexProfileSearchError.invalidResponse
        }

        let referencesRequester = responseEvent.tags.contains { tag in
            guard let name = tag.first?.lowercased(), name == "p", tag.count > 1 else { return false }
            return tag[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedRequesterPubkey
        }
        guard referencesRequester else {
            throw VertexProfileSearchError.invalidResponse
        }
    }

    private func cachedSearch(for key: String) -> (matches: [VertexProfileMatch], createdAt: Int)? {
        guard let cached = searchCache[key] else { return nil }
        guard Date().timeIntervalSince(cached.storedAt) <= cacheTTL else {
            searchCache.removeValue(forKey: key)
            return nil
        }
        return (cached.matches, cached.createdAt)
    }

    private func normalizedPubkeys(from matches: [VertexProfileMatch]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for match in matches {
            let normalized = match.pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard normalized.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { continue }
            guard seen.insert(normalized).inserted else { continue }
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

    private func responseStatusMessage(from tags: [[String]]) -> String? {
        for tag in tags {
            guard let name = tag.first?.lowercased(), name == "status", tag.count > 2 else { continue }
            let value = tag[2].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func decodeSDKTag(from raw: [String]) -> NostrSDK.Tag? {
        guard raw.count >= 2 else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: raw),
              let tag = try? JSONDecoder().decode(NostrSDK.Tag.self, from: data) else {
            return nil
        }
        return tag
    }
}

enum FeedItemHydrationMode: Sendable {
    case full
    case cachedProfilesOnly
}

enum RelayFetchMode: Sendable {
    case allRelays
    case firstNonEmptyRelay
}

struct NostrFeedService: Sendable {
    private let relayClient: NostrRelayClient
    private let timelineCache: TimelineEventCache
    private let profileCache: ProfileCache
    private let relayHintCache: ProfileRelayHintCache
    private let followListCache: FollowListSnapshotCache
    private let seenEventStore: SeenEventStore
    private static let trendingRelayURL = URL(string: "wss://trending.relays.land")!
    private static let followListFreshCacheAge: TimeInterval = 60 * 5
    private static let metadataFallbackRelayURLs: [URL] = [
        URL(string: "wss://relay.damus.io/")!,
        URL(string: "wss://relay.primal.net/")!,
        URL(string: "wss://relay.nostr.band/")!,
        URL(string: "wss://relay.snort.social/")!,
        URL(string: "wss://nostr.wine/")!,
        URL(string: "wss://nos.lol/")!
    ]

    init(
        relayClient: NostrRelayClient = NostrRelayClient(),
        timelineCache: TimelineEventCache = .shared,
        profileCache: ProfileCache = .shared,
        relayHintCache: ProfileRelayHintCache = .shared,
        followListCache: FollowListSnapshotCache = .shared,
        seenEventStore: SeenEventStore = .shared
    ) {
        self.relayClient = relayClient
        self.timelineCache = timelineCache
        self.profileCache = profileCache
        self.relayHintCache = relayHintCache
        self.followListCache = followListCache
        self.seenEventStore = seenEventStore
    }

    func fetchFeed(relayURL: URL, kinds: [Int], limit: Int, until: Int?) async throws -> [FeedItem] {
        try await fetchFeed(
            relayURLs: [relayURL],
            kinds: kinds,
            limit: limit,
            until: until
        )
    }

    func fetchFeed(
        relayURLs: [URL],
        kinds: [Int],
        limit: Int,
        until: Int?,
        hydrationMode: FeedItemHydrationMode = .full,
        fetchTimeout: TimeInterval = 12,
        relayFetchMode: RelayFetchMode = .allRelays,
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async throws -> [FeedItem] {
        guard limit > 0 else { return [] }
        let fetchLimit = expandedTimelineLimit(for: limit, moderationSnapshot: moderationSnapshot)
        let filter = NostrFilter(
            kinds: kinds,
            limit: fetchLimit,
            until: until
        )

        let kindsSet = Set(kinds)
        let fetchedEvents = try await fetchTimelineEvents(
            relayURLs: relayURLs,
            filter: filter,
            timeout: fetchTimeout,
            useCache: false,
            relayFetchMode: relayFetchMode
        )
            .filter { kindsSet.contains($0.kind) }
        let visibleEvents = filterVisibleEvents(fetchedEvents, moderationSnapshot: moderationSnapshot)
        let timelineEvents = Array(
            deduplicateEvents(visibleEvents)
                .sorted(by: { $0.createdAt > $1.createdAt })
                .prefix(limit)
        )
        return await buildFeedItems(
            relayURLs: relayURLs,
            events: timelineEvents,
            hydrationMode: hydrationMode,
            moderationSnapshot: moderationSnapshot
        )
    }

    func fetchFollowingFeed(
        relayURL: URL,
        authors: [String],
        kinds: [Int],
        limit: Int,
        until: Int?
    ) async throws -> [FeedItem] {
        try await fetchFollowingFeed(
            relayURLs: [relayURL],
            authors: authors,
            kinds: kinds,
            limit: limit,
            until: until
        )
    }

    func fetchFollowingFeed(
        relayURLs: [URL],
        authors: [String],
        kinds: [Int],
        limit: Int,
        until: Int?,
        hydrationMode: FeedItemHydrationMode = .full,
        fetchTimeout: TimeInterval = 12,
        relayFetchMode: RelayFetchMode = .allRelays,
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async throws -> [FeedItem] {
        guard limit > 0 else { return [] }
        let normalizedAuthors = Array(
            Set(
                authors
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
        )
        guard !normalizedAuthors.isEmpty else { return [] }

        let kindsSet = Set(kinds)
        let authorBatches = normalizedAuthors.chunked(into: 250)
        let perBatchLimit = min(
            expandedTimelineLimit(for: max(limit, 50), moderationSnapshot: moderationSnapshot),
            240
        )

        let fetchedEvents = try await withThrowingTaskGroup(of: [NostrEvent].self) { group in
            for batch in authorBatches {
                group.addTask {
                    let filter = NostrFilter(
                        authors: batch,
                        kinds: kinds,
                        limit: perBatchLimit,
                        until: until
                    )
                    return try await fetchTimelineEvents(
                        relayURLs: relayURLs,
                        filter: filter,
                        timeout: fetchTimeout,
                        useCache: false,
                        relayFetchMode: relayFetchMode
                    )
                }
            }

            var merged: [NostrEvent] = []
            for try await batchEvents in group {
                merged.append(contentsOf: batchEvents)
            }
            return merged
        }
        .filter { kindsSet.contains($0.kind) }
        let visibleEvents = filterVisibleEvents(fetchedEvents, moderationSnapshot: moderationSnapshot)
        let timelineEvents = Array(
            deduplicateEvents(visibleEvents)
                .sorted(by: { $0.createdAt > $1.createdAt })
                .prefix(limit)
        )
        return await buildFeedItems(
            relayURLs: relayURLs,
            events: timelineEvents,
            hydrationMode: hydrationMode,
            moderationSnapshot: moderationSnapshot
        )
    }

    func fetchFollowings(relayURL: URL, pubkey: String) async throws -> [String] {
        try await fetchFollowings(relayURLs: [relayURL], pubkey: pubkey)
    }

    func fetchFollowings(
        relayURLs: [URL],
        pubkey: String,
        relayFetchMode: RelayFetchMode = .allRelays
    ) async throws -> [String] {
        let snapshot = try await fetchFollowListSnapshot(
            relayURLs: relayURLs,
            pubkey: pubkey,
            relayFetchMode: relayFetchMode
        )
        return snapshot?.followedPubkeys ?? []
    }

    func cachedFollowListSnapshot(pubkey: String) async -> FollowListSnapshot? {
        let normalizedPubkey = normalizePubkey(pubkey)
        guard !normalizedPubkey.isEmpty else { return nil }
        let snapshot = await followListCache.cachedSnapshot(pubkey: normalizedPubkey)
        if let snapshot {
            await relayHintCache.storeHints(snapshot.relayHintsByPubkey)
        }
        return snapshot
    }

    func fetchFollowListSnapshot(relayURL: URL, pubkey: String) async throws -> FollowListSnapshot? {
        try await fetchFollowListSnapshot(relayURLs: [relayURL], pubkey: pubkey)
    }

    func fetchFollowListSnapshot(
        relayURLs: [URL],
        pubkey: String,
        fetchTimeout: TimeInterval = 10,
        relayFetchMode: RelayFetchMode = .allRelays
    ) async throws -> FollowListSnapshot? {
        let normalizedPubkey = normalizePubkey(pubkey)
        guard !normalizedPubkey.isEmpty else { return nil }

        let cachedSnapshot = await followListCache.cachedSnapshot(pubkey: normalizedPubkey)

        let contactsFilter = NostrFilter(
            authors: [normalizedPubkey],
            kinds: [3],
            limit: 50
        )

        do {
            let events = try await fetchTimelineEvents(
                relayURLs: relayURLs,
                filter: contactsFilter,
                timeout: fetchTimeout,
                useCache: false,
                relayFetchMode: relayFetchMode
            )

            if let snapshot = extractFollowListSnapshot(from: events) {
                await followListCache.storeSnapshot(snapshot, for: normalizedPubkey)
                await relayHintCache.storeHints(snapshot.relayHintsByPubkey)
                return snapshot
            }

            if let cachedSnapshot {
                await relayHintCache.storeHints(cachedSnapshot.relayHintsByPubkey)
            }
            return cachedSnapshot
        } catch {
            if let cachedSnapshot {
                await relayHintCache.storeHints(cachedSnapshot.relayHintsByPubkey)
                return cachedSnapshot
            }
            throw error
        }
    }

    func fetchAuthorFeed(
        relayURL: URL,
        authorPubkey: String,
        kinds: [Int],
        limit: Int,
        until: Int?
    ) async throws -> [FeedItem] {
        try await fetchAuthorFeed(
            relayURLs: [relayURL],
            authorPubkey: authorPubkey,
            kinds: kinds,
            limit: limit,
            until: until
        )
    }

    func fetchAuthorFeed(
        relayURLs: [URL],
        authorPubkey: String,
        kinds: [Int],
        limit: Int,
        until: Int?,
        hydrationMode: FeedItemHydrationMode = .full,
        fetchTimeout: TimeInterval = 12,
        relayFetchMode: RelayFetchMode = .allRelays,
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async throws -> [FeedItem] {
        guard limit > 0 else { return [] }
        let fetchLimit = expandedTimelineLimit(for: limit, moderationSnapshot: moderationSnapshot)
        let filter = NostrFilter(
            authors: [authorPubkey],
            kinds: kinds,
            limit: fetchLimit,
            until: until
        )

        let kindsSet = Set(kinds)
        let fetchedEvents = try await fetchTimelineEvents(
            relayURLs: relayURLs,
            filter: filter,
            timeout: fetchTimeout,
            useCache: false,
            relayFetchMode: relayFetchMode
        )
            .filter { kindsSet.contains($0.kind) }
        let visibleEvents = filterVisibleEvents(fetchedEvents, moderationSnapshot: moderationSnapshot)
        let timelineEvents = Array(
            deduplicateEvents(visibleEvents)
                .sorted(by: { $0.createdAt > $1.createdAt })
                .prefix(limit)
        )
        return await buildFeedItems(
            relayURLs: relayURLs,
            events: timelineEvents,
            hydrationMode: hydrationMode,
            moderationSnapshot: moderationSnapshot
        )
    }

    func searchNotes(
        relayURLs: [URL],
        query: String,
        kinds: [Int],
        limit: Int,
        until: Int? = nil,
        hydrationMode: FeedItemHydrationMode = .full,
        fetchTimeout: TimeInterval = 12,
        relayFetchMode: RelayFetchMode = .allRelays,
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async throws -> [FeedItem] {
        guard limit > 0 else { return [] }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }
        let shouldVerifyResults = shouldLocallyVerifyNIP50Results(for: normalizedQuery)
        let searchTerms = shouldVerifyResults ? normalizedSearchTerms(from: normalizedQuery) : []
        let primarySearchLimit = expandedTimelineLimit(
            for: max(limit * 2, 120),
            moderationSnapshot: moderationSnapshot
        )
        let fallbackSearchLimit = min(
            expandedTimelineLimit(
                for: min(max(limit * 8, 220), 600),
                moderationSnapshot: moderationSnapshot
            ),
            600
        )

        let kindsSet = Set(kinds)
        let searchFilter = NostrFilter(
            kinds: kinds,
            search: normalizedQuery,
            limit: primarySearchLimit,
            until: until
        )

        var firstError: Error?
        var fetchedEvents: [NostrEvent] = []

        do {
            fetchedEvents = try await fetchTimelineEvents(
                relayURLs: relayURLs,
                filter: searchFilter,
                timeout: fetchTimeout,
                useCache: false,
                relayFetchMode: relayFetchMode
            )
            .filter { event in
                guard kindsSet.contains(event.kind) else { return false }
                if let until, event.createdAt > until {
                    return false
                }
                guard shouldVerifyResults else { return true }
                return eventMatchesSearchTerms(event, terms: searchTerms)
            }
            fetchedEvents = filterVisibleEvents(fetchedEvents, moderationSnapshot: moderationSnapshot)
        } catch {
            firstError = error
        }

        if fetchedEvents.isEmpty {
            let fallbackFilter = NostrFilter(
                kinds: kinds,
                limit: fallbackSearchLimit,
                until: until
            )

            do {
                let fallbackEvents = try await fetchTimelineEvents(
                    relayURLs: relayURLs,
                    filter: fallbackFilter,
                    timeout: fetchTimeout,
                    relayFetchMode: relayFetchMode
                )
                fetchedEvents = fallbackEvents.filter { event in
                    guard kindsSet.contains(event.kind) else { return false }
                    if let until, event.createdAt > until {
                        return false
                    }
                    guard shouldVerifyResults else { return true }
                    return eventMatchesSearchTerms(event, terms: searchTerms)
                }
                fetchedEvents = filterVisibleEvents(fetchedEvents, moderationSnapshot: moderationSnapshot)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if fetchedEvents.isEmpty, let firstError {
            throw firstError
        }

        let timelineEvents = Array(
            deduplicateEvents(fetchedEvents)
                .sorted(by: { lhs, rhs in
                    if lhs.createdAt == rhs.createdAt {
                        return lhs.id > rhs.id
                    }
                    return lhs.createdAt > rhs.createdAt
                })
                .prefix(limit)
        )
        return await buildFeedItems(
            relayURLs: relayURLs,
            events: timelineEvents,
            hydrationMode: hydrationMode,
            moderationSnapshot: moderationSnapshot
        )
    }

    func searchProfiles(
        relayURLs: [URL],
        query: String,
        limit: Int,
        fetchTimeout: TimeInterval = 10,
        relayFetchMode: RelayFetchMode = .allRelays
    ) async throws -> [ProfileSearchResult] {
        guard limit > 0 else { return [] }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return [] }

        let metadataFilter = NostrFilter(
            kinds: [0],
            search: normalizedQuery,
            limit: max(limit * 4, 60)
        )

        var firstError: Error?
        var metadataEvents: [NostrEvent] = []

        do {
            metadataEvents = try await fetchTimelineEvents(
                relayURLs: relayURLs,
                filter: metadataFilter,
                timeout: fetchTimeout,
                useCache: false,
                relayFetchMode: relayFetchMode
            )
            .filter { $0.kind == 0 }
        } catch {
            firstError = error
        }

        if metadataEvents.isEmpty {
            let fallbackFilter = NostrFilter(
                kinds: [0],
                limit: min(max(limit * 20, 180), 500)
            )

            do {
                metadataEvents = try await fetchTimelineEvents(
                    relayURLs: relayURLs,
                    filter: fallbackFilter,
                    timeout: fetchTimeout,
                    relayFetchMode: relayFetchMode
                )
                .filter { $0.kind == 0 }
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if metadataEvents.isEmpty, let firstError {
            throw firstError
        }

        let sortedEvents = deduplicateEvents(metadataEvents).sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id > rhs.id
            }
            return lhs.createdAt > rhs.createdAt
        }

        var seen = Set<String>()
        var matches: [ProfileSearchResult] = []
        var fetchedProfiles: [String: NostrProfile] = [:]

        for event in sortedEvents {
            guard let profile = NostrProfile.decode(from: event.content) else { continue }
            let pubkey = normalizePubkey(event.pubkey)
            guard !pubkey.isEmpty else { continue }
            guard seen.insert(pubkey).inserted else { continue }
            guard profileMatchesQuery(profile: profile, pubkey: pubkey, query: normalizedQuery) else { continue }

            fetchedProfiles[pubkey] = profile
            matches.append(ProfileSearchResult(pubkey: pubkey, profile: profile, createdAt: event.createdAt))

            if matches.count >= limit {
                break
            }
        }

        if !fetchedProfiles.isEmpty {
            await profileCache.store(profiles: fetchedProfiles, missed: [])
        }

        return matches
    }

    func fetchTrendingNotes(
        limit: Int = 100,
        hydrationMode: FeedItemHydrationMode = .full,
        fetchTimeout: TimeInterval = 12,
        relayFetchMode: RelayFetchMode = .allRelays,
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async throws -> [FeedItem] {
        guard limit > 0 else { return [] }
        let cappedLimit = min(limit, 100)
        let fetchLimit = min(
            expandedTimelineLimit(for: cappedLimit, moderationSnapshot: moderationSnapshot),
            240
        )
        let filter = NostrFilter(
            kinds: [1],
            limit: fetchLimit
        )

        let fetchedEvents = try await fetchTimelineEvents(
            relayURLs: [Self.trendingRelayURL],
            filter: filter,
            timeout: fetchTimeout,
            relayFetchMode: relayFetchMode
        )
        .filter { $0.kind == 1 }
        let visibleEvents = filterVisibleEvents(fetchedEvents, moderationSnapshot: moderationSnapshot)
        let timelineEvents = Array(
            deduplicateEvents(visibleEvents)
                .sorted(by: { lhs, rhs in
                    if lhs.createdAt == rhs.createdAt {
                        return lhs.id > rhs.id
                    }
                    return lhs.createdAt > rhs.createdAt
                })
                .prefix(cappedLimit)
        )

        switch hydrationMode {
        case .cachedProfilesOnly:
            return await buildCachedFeedItems(
                events: timelineEvents,
                moderationSnapshot: moderationSnapshot
            )
        case .full:
            return await buildAuthorOnlyFeedItems(
                relayURLs: [Self.trendingRelayURL],
                events: timelineEvents,
                moderationSnapshot: moderationSnapshot
            )
        }
    }

    func fetchActivityRows(
        relayURL: URL,
        currentUserPubkey: String,
        filter: ActivityFilter = .all,
        limit: Int = 100
    ) async throws -> [ActivityRow] {
        try await fetchActivityRows(
            relayURLs: [relayURL],
            currentUserPubkey: currentUserPubkey,
            filter: filter,
            limit: limit
        )
    }

    func fetchActivityRows(
        relayURLs: [URL],
        currentUserPubkey: String,
        filter: ActivityFilter = .all,
        limit: Int = 100,
        fetchTimeout: TimeInterval = 12,
        relayFetchMode: RelayFetchMode = .allRelays,
        profileFetchTimeout: TimeInterval = 8,
        profileRelayFetchMode: RelayFetchMode = .allRelays
    ) async throws -> [ActivityRow] {
        guard limit > 0 else { return [] }
        let normalizedPubkey = normalizePubkey(currentUserPubkey)
        guard !normalizedPubkey.isEmpty else { return [] }

        let relayTargets = normalizedRelayURLs(relayURLs)
        guard !relayTargets.isEmpty else { return [] }

        let activityFilter = NostrFilter(
            kinds: filter.eventKinds,
            limit: limit,
            tagFilters: ["p": [normalizedPubkey]]
        )

        let activityEvents = try await fetchTimelineEvents(
            relayURLs: relayTargets,
            filter: activityFilter,
            timeout: fetchTimeout,
            relayFetchMode: relayFetchMode
        )

        let limitedEvents = Array(
            filteredActivityEvents(
                from: activityEvents,
                currentUserPubkey: normalizedPubkey
            )
            .prefix(limit)
        )

        return await buildActivityRows(
            relayURLs: relayTargets,
            currentUserPubkey: normalizedPubkey,
            events: limitedEvents,
            fetchTimeout: fetchTimeout,
            relayFetchMode: relayFetchMode,
            profileFetchTimeout: profileFetchTimeout,
            profileRelayFetchMode: profileRelayFetchMode
        )
    }

    func buildActivityRows(
        relayURLs: [URL],
        currentUserPubkey: String,
        events: [NostrEvent],
        fetchTimeout: TimeInterval = 12,
        relayFetchMode: RelayFetchMode = .allRelays,
        profileFetchTimeout: TimeInterval = 8,
        profileRelayFetchMode: RelayFetchMode = .allRelays
    ) async -> [ActivityRow] {
        let normalizedPubkey = normalizePubkey(currentUserPubkey)
        guard !normalizedPubkey.isEmpty else { return [] }

        let relayTargets = normalizedRelayURLs(relayURLs)
        guard !relayTargets.isEmpty else { return [] }

        let filteredEvents = filteredActivityEvents(
            from: events,
            currentUserPubkey: normalizedPubkey
        )
        guard !filteredEvents.isEmpty else { return [] }

        async let actorProfilesTask = hydrateActorProfiles(
            for: filteredEvents,
            relayURLs: relayTargets,
            fetchTimeout: profileFetchTimeout,
            relayFetchMode: profileRelayFetchMode
        )
        async let targetEventsTask = resolveActivityTargetEvents(
            relayURLs: relayTargets,
            sourceEvents: filteredEvents,
            fetchTimeout: fetchTimeout,
            relayFetchMode: relayFetchMode
        )

        let actorProfiles = await actorProfilesTask
        let targetEventsByReference = await targetEventsTask
        let targetPubkeys = Array(
            Set(
                targetEventsByReference.values
                    .map { normalizePubkey($0.pubkey) }
                    .filter { !$0.isEmpty }
            )
        )
        let targetProfiles = targetPubkeys.isEmpty
            ? [:]
            : await fetchProfiles(
                relayURLs: relayTargets,
                pubkeys: targetPubkeys,
                fetchTimeout: profileFetchTimeout,
                relayFetchMode: profileRelayFetchMode
            )

        return filteredEvents.compactMap { event in
            guard let action = event.activityAction else { return nil }

            let normalizedActorPubkey = normalizePubkey(event.pubkey)
            let actor = ActivityActor(pubkey: event.pubkey, profile: actorProfiles[normalizedActorPubkey])
            let targetReference = event.activityTargetReference
            let resolvedTargetEvent = targetReference.flatMap { targetEventsByReference[$0] }
            let targetProfile = resolvedTargetEvent.flatMap {
                targetProfiles[normalizePubkey($0.pubkey)]
            }
            let targetSnippet = resolvedTargetEvent?.activitySnippet()
                ?? fallbackActivitySnippet(for: event, action: action)
            let target = ActivityTargetNote(
                reference: targetReference,
                event: resolvedTargetEvent,
                profile: targetProfile,
                snippet: targetSnippet
            )

            return ActivityRow(
                event: event,
                actor: actor,
                action: action,
                target: target
            )
        }
    }

    func fetchHashtagFeed(
        relayURL: URL,
        hashtag: String,
        kinds: [Int],
        limit: Int,
        until: Int?
    ) async throws -> [FeedItem] {
        try await fetchHashtagFeed(
            relayURLs: [relayURL],
            hashtag: hashtag,
            kinds: kinds,
            limit: limit,
            until: until
        )
    }

    func fetchHashtagFeed(
        relayURLs: [URL],
        hashtag: String,
        kinds: [Int],
        limit: Int,
        until: Int?,
        hydrationMode: FeedItemHydrationMode = .full,
        fetchTimeout: TimeInterval = 12,
        relayFetchMode: RelayFetchMode = .allRelays,
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async throws -> [FeedItem] {
        guard limit > 0 else {
            return []
        }
        let fetchLimit = expandedTimelineLimit(for: limit, moderationSnapshot: moderationSnapshot)

        let normalizedHashtag = NostrEvent.normalizedHashtagValue(hashtag)
        
        guard !normalizedHashtag.isEmpty else {
            return []
        }
        
        let filter = NostrFilter(
            kinds: kinds,
            limit: fetchLimit,
            until: until,
            tagFilters: ["t": [normalizedHashtag]]
        )

        let kindsSet = Set(kinds)
        let fetchedEvents = try await fetchTimelineEvents(
            relayURLs: relayURLs,
            filter: filter,
            timeout: fetchTimeout,
            useCache: false,
            relayFetchMode: relayFetchMode
        )
            .filter { kindsSet.contains($0.kind) }
        let visibleEvents = filterVisibleEvents(fetchedEvents, moderationSnapshot: moderationSnapshot)
        let timelineEvents = Array(
            deduplicateEvents(visibleEvents)
                .sorted(by: { $0.createdAt > $1.createdAt })
                .prefix(limit)
        )
        return await buildFeedItems(
            relayURLs: relayURLs,
            events: timelineEvents,
            hydrationMode: hydrationMode,
            moderationSnapshot: moderationSnapshot
        )
    }

    func fetchHashtagFeed(
        relayURLs: [URL],
        hashtags: [String],
        kinds: [Int],
        limit: Int,
        until: Int?,
        hydrationMode: FeedItemHydrationMode = .full,
        fetchTimeout: TimeInterval = 12,
        relayFetchMode: RelayFetchMode = .allRelays,
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async throws -> [FeedItem] {
        guard limit > 0 else { return [] }
        let fetchLimit = expandedTimelineLimit(for: limit, moderationSnapshot: moderationSnapshot)

        let normalizedHashtags = Array(
            Set(
                hashtags
                    .map(NostrEvent.normalizedHashtagValue)
                    .filter { !$0.isEmpty }
            )
        )
        guard !normalizedHashtags.isEmpty else { return [] }

        let filter = NostrFilter(
            kinds: kinds,
            limit: fetchLimit,
            until: until,
            tagFilters: ["t": normalizedHashtags]
        )

        let kindsSet = Set(kinds)
        let fetchedEvents = try await fetchTimelineEvents(
            relayURLs: relayURLs,
            filter: filter,
            timeout: fetchTimeout,
            useCache: false,
            relayFetchMode: relayFetchMode
        )
        .filter { event in
            guard kindsSet.contains(event.kind) else { return false }
            let eventHashtags = Set<String>(
                event.tags.compactMap { tag in
                    guard let name = tag.first?.lowercased(), name == "t", tag.count > 1 else { return nil }
                    return tag[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }
            )
            return !eventHashtags.isDisjoint(with: normalizedHashtags)
        }
        let visibleEvents = filterVisibleEvents(fetchedEvents, moderationSnapshot: moderationSnapshot)

        let timelineEvents = Array(
            deduplicateEvents(visibleEvents)
                .sorted(by: { lhs, rhs in
                    if lhs.createdAt == rhs.createdAt {
                        return lhs.id > rhs.id
                    }
                    return lhs.createdAt > rhs.createdAt
                })
                .prefix(limit)
        )
        return await buildFeedItems(
            relayURLs: relayURLs,
            events: timelineEvents,
            hydrationMode: hydrationMode,
            moderationSnapshot: moderationSnapshot
        )
    }

    func fetchThreadReplies(
        relayURL: URL,
        rootEventID: String,
        limit: Int = 150
    ) async throws -> [FeedItem] {
        try await fetchThreadReplies(relayURLs: [relayURL], rootEventID: rootEventID, limit: limit)
    }

    func fetchThreadReplies(
        relayURLs: [URL],
        rootEventID: String,
        limit: Int = 150,
        hydrationMode: FeedItemHydrationMode = .full,
        fetchTimeout: TimeInterval = 12,
        relayFetchMode: RelayFetchMode = .allRelays,
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async throws -> [FeedItem] {
        let fetchLimit = expandedTimelineLimit(for: limit, moderationSnapshot: moderationSnapshot)
        let directFilter = NostrFilter(
            kinds: [1, 1111, 1244],
            limit: fetchLimit,
            tagFilters: ["e": [rootEventID]]
        )

        let directReplies = try await fetchTimelineEvents(
            relayURLs: relayURLs,
            filter: directFilter,
            timeout: fetchTimeout,
            relayFetchMode: relayFetchMode
        )
            .filter { $0.id != rootEventID }
            .filter { $0.references(eventID: rootEventID) }
        let directReplyIDs = Set(directReplies.map(\.id))

        var allReplies = directReplies
        if !directReplyIDs.isEmpty {
            let nestedFilter = NostrFilter(
                kinds: [1, 1111, 1244],
                limit: fetchLimit,
                tagFilters: ["e": Array(directReplyIDs.prefix(60))]
            )
            let nestedReplies = (try? await fetchTimelineEvents(
                relayURLs: relayURLs,
                filter: nestedFilter,
                timeout: fetchTimeout,
                relayFetchMode: relayFetchMode
            )) ?? []
            let relevantNested = nestedReplies
                .filter { $0.id != rootEventID }
                .filter { event in
                    event.references(eventID: rootEventID) ||
                    event.eventReferenceIDs.contains(where: { directReplyIDs.contains($0) })
                }
            allReplies.append(contentsOf: relevantNested)
        }

        let uniqueEvents = deduplicateEvents(
            filterVisibleEvents(allReplies, moderationSnapshot: moderationSnapshot)
                .sorted(by: { $0.createdAt < $1.createdAt })
        )
        return await buildFeedItems(
            relayURLs: relayURLs,
            events: uniqueEvents,
            hydrationMode: hydrationMode,
            moderationSnapshot: moderationSnapshot
        )
    }

    func fetchProfile(relayURL: URL, pubkey: String) async -> NostrProfile? {
        await fetchProfile(relayURLs: [relayURL], pubkey: pubkey)
    }

    func cachedProfile(pubkey: String) async -> NostrProfile? {
        await profileCache.cachedProfile(pubkey: normalizePubkey(pubkey))
    }

    func cachedProfiles(pubkeys: [String]) async -> [String: NostrProfile] {
        await profileCache.cachedProfiles(pubkeys: pubkeys)
    }

    func prewarmProfiles(
        relayURLs: [URL],
        pubkeys: [String],
        relayHintsByPubkey: [String: [URL]] = [:]
    ) async {
        guard !relayHintsByPubkey.isEmpty else {
            _ = await fetchProfiles(relayURLs: relayURLs, pubkeys: pubkeys)
            return
        }

        await relayHintCache.storeHints(relayHintsByPubkey)
        _ = await fetchProfiles(relayURLs: relayURLs, pubkeys: pubkeys)
    }

    func fetchProfile(
        relayURLs: [URL],
        pubkey: String,
        fetchTimeout: TimeInterval = 8,
        relayFetchMode: RelayFetchMode = .allRelays
    ) async -> NostrProfile? {
        let profiles = await fetchProfiles(
            relayURLs: relayURLs,
            pubkeys: [pubkey],
            fetchTimeout: fetchTimeout,
            relayFetchMode: relayFetchMode
        )
        return profiles[normalizePubkey(pubkey)]
    }

    func fetchFollowingCount(relayURL: URL, pubkey: String) async -> Int {
        await fetchFollowingCount(relayURLs: [relayURL], pubkey: pubkey)
    }

    func cachedFollowingCount(pubkey: String) async -> Int? {
        let normalizedPubkey = normalizePubkey(pubkey)
        guard !normalizedPubkey.isEmpty else { return nil }
        guard let cachedSnapshot = await followListCache.cachedSnapshot(pubkey: normalizedPubkey) else {
            return nil
        }
        return cachedSnapshot.followedPubkeys.count
    }

    func fetchFollowingCount(
        relayURLs: [URL],
        pubkey: String,
        fetchTimeout: TimeInterval = 10,
        relayFetchMode: RelayFetchMode = .allRelays
    ) async -> Int {
        let normalizedPubkey = normalizePubkey(pubkey)
        guard !normalizedPubkey.isEmpty else { return 0 }
        if let cachedSnapshot = await followListCache.cachedSnapshot(
            pubkey: normalizedPubkey,
            maxAge: Self.followListFreshCacheAge
        ) {
            return cachedSnapshot.followedPubkeys.count
        }

        guard let snapshot = try? await fetchFollowListSnapshot(
            relayURLs: relayURLs,
            pubkey: pubkey,
            fetchTimeout: fetchTimeout,
            relayFetchMode: relayFetchMode
        ) else {
            return 0
        }
        return snapshot.followedPubkeys.count
    }

    func fetchProfiles(relayURL: URL, pubkeys: [String]) async -> [String: NostrProfile] {
        await fetchProfiles(relayURLs: [relayURL], pubkeys: pubkeys)
    }

    func fetchProfiles(
        relayURLs: [URL],
        pubkeys: [String],
        fetchTimeout: TimeInterval = 8,
        relayFetchMode: RelayFetchMode = .allRelays
    ) async -> [String: NostrProfile] {
        let normalizedPubkeys = Array(
            Set(
                pubkeys
                    .map { normalizePubkey($0) }
                    .filter { !$0.isEmpty }
            )
        )
        guard !normalizedPubkeys.isEmpty else { return [:] }

        let resolved = await profileCache.resolve(
            pubkeys: normalizedPubkeys,
            ignoringKnownMisses: true
        )
        var profilesByPubkey = resolved.hits
        var unresolvedPubkeys = Set(resolved.missing)
        guard !unresolvedPubkeys.isEmpty else { return profilesByPubkey }

        let primaryRelayTargets = normalizedRelayURLs(relayURLs)
        let prioritizedRelayTargets = await relayHintCache.prioritizedRelayURLs(
            for: Array(unresolvedPubkeys),
            baseRelayURLs: primaryRelayTargets
        )
        var fetchedProfiles = await fetchProfilesForPubkeys(
            relayURLs: prioritizedRelayTargets,
            pubkeys: Array(unresolvedPubkeys),
            timeout: fetchTimeout,
            relayFetchMode: relayFetchMode
        )
        unresolvedPubkeys.subtract(fetchedProfiles.keys.map(normalizePubkey))

        if !unresolvedPubkeys.isEmpty {
            let metadataRelayTargets = metadataRelayURLs(primaryRelayURLs: prioritizedRelayTargets)
            let fallbackProfiles = await fetchProfilesForPubkeys(
                relayURLs: metadataRelayTargets,
                pubkeys: Array(unresolvedPubkeys),
                timeout: fetchTimeout,
                relayFetchMode: relayFetchMode
            )
            if !fallbackProfiles.isEmpty {
                fetchedProfiles.merge(fallbackProfiles, uniquingKeysWith: { existing, _ in existing })
                unresolvedPubkeys.subtract(fallbackProfiles.keys.map(normalizePubkey))
            }
        }

        if !fetchedProfiles.isEmpty || !unresolvedPubkeys.isEmpty {
            profilesByPubkey.merge(fetchedProfiles, uniquingKeysWith: { existing, _ in existing })
            await profileCache.store(
                profiles: fetchedProfiles,
                missed: Array(unresolvedPubkeys)
            )
        }

        return profilesByPubkey
    }

    func buildFeedItems(
        relayURL: URL,
        events: [NostrEvent],
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async -> [FeedItem] {
        await buildFeedItems(
            relayURLs: [relayURL],
            events: events,
            moderationSnapshot: moderationSnapshot
        )
    }

    func buildFeedItems(
        relayURLs: [URL],
        events: [NostrEvent],
        hydrationMode: FeedItemHydrationMode = .full,
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async -> [FeedItem] {
        let uniqueEvents = deduplicateEvents(
            filterVisibleEvents(events, moderationSnapshot: moderationSnapshot)
        )

        switch hydrationMode {
        case .cachedProfilesOnly:
            return await buildCachedFeedItems(
                events: uniqueEvents,
                moderationSnapshot: moderationSnapshot
            )
        case .full:
            break
        }

        async let actorProfilesTask = hydrateActorProfiles(for: uniqueEvents, relayURLs: relayURLs)
        async let displayEventsTask = resolveDisplayEvents(for: uniqueEvents, relayURLs: relayURLs)

        let profilesByPubkey = await actorProfilesTask
        let displayEventsBySourceID = await displayEventsTask
        async let replyTargetEventsTask = resolveReplyTargetEvents(
            for: uniqueEvents,
            displayEventsBySourceID: displayEventsBySourceID,
            relayURLs: relayURLs
        )
        let displayPubkeys = Array(
            Set(
                displayEventsBySourceID.values
                    .map { normalizePubkey($0.pubkey) }
                    .filter { !$0.isEmpty }
            )
        )

        var displayProfilesByPubkey = profilesByPubkey
        if !displayPubkeys.isEmpty {
            let fetchedDisplayProfiles = await fetchProfiles(relayURLs: relayURLs, pubkeys: displayPubkeys)
            displayProfilesByPubkey.merge(fetchedDisplayProfiles, uniquingKeysWith: { existing, _ in existing })
        }

        let replyTargetEventsBySourceID = await replyTargetEventsTask
        let replyTargetPubkeys = Array(
            Set(
                replyTargetEventsBySourceID.values
                    .map { normalizePubkey($0.pubkey) }
                    .filter { !$0.isEmpty }
            )
        )
        var replyTargetProfilesByPubkey = displayProfilesByPubkey
        if !replyTargetPubkeys.isEmpty {
            let fetchedReplyTargetProfiles = await fetchProfiles(relayURLs: relayURLs, pubkeys: replyTargetPubkeys)
            replyTargetProfilesByPubkey.merge(
                fetchedReplyTargetProfiles,
                uniquingKeysWith: { existing, _ in existing }
            )
        }

        let items = uniqueEvents.map { event in
            let normalizedPubkey = normalizePubkey(event.pubkey)
            let displayEvent = displayEventsBySourceID[event.id.lowercased()]
            let displayProfile = displayEvent.flatMap { displayProfilesByPubkey[normalizePubkey($0.pubkey)] }
            let replyTargetEvent = replyTargetEventsBySourceID[event.id.lowercased()]
            let replyTargetProfile = replyTargetEvent.flatMap {
                replyTargetProfilesByPubkey[normalizePubkey($0.pubkey)]
            }

            return FeedItem(
                event: event,
                profile: profilesByPubkey[normalizedPubkey],
                displayEventOverride: displayEvent,
                displayProfileOverride: displayProfile,
                replyTargetEvent: replyTargetEvent,
                replyTargetProfile: replyTargetProfile
            )
        }
        return filterVisibleFeedItems(items, moderationSnapshot: moderationSnapshot)
    }

    func buildAuthorHydratedFeedItems(
        relayURLs: [URL],
        events: [NostrEvent],
        fetchTimeout: TimeInterval = 8,
        relayFetchMode: RelayFetchMode = .allRelays,
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async -> [FeedItem] {
        await buildAuthorOnlyFeedItems(
            relayURLs: relayURLs,
            events: events,
            fetchTimeout: fetchTimeout,
            relayFetchMode: relayFetchMode,
            moderationSnapshot: moderationSnapshot
        )
    }

    private func buildCachedFeedItems(
        events: [NostrEvent],
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async -> [FeedItem] {
        let actorPubkeys = Array(
            Set(
                events
                    .map { normalizePubkey($0.pubkey) }
                    .filter { !$0.isEmpty }
            )
        )
        let actorProfilesByPubkey = await profileCache.cachedProfiles(pubkeys: actorPubkeys)

        let displayEventsBySourceID = await resolveCachedDisplayEvents(for: events)
        let displayPubkeys = Array(
            Set(
                displayEventsBySourceID.values
                    .map { normalizePubkey($0.pubkey) }
                    .filter { !$0.isEmpty }
            )
        )
        let displayProfilesByPubkey = await profileCache.cachedProfiles(pubkeys: displayPubkeys)
        let replyTargetEventsBySourceID = await resolveCachedReplyTargetEvents(
            for: events,
            displayEventsBySourceID: displayEventsBySourceID
        )
        let replyTargetPubkeys = Array(
            Set(
                replyTargetEventsBySourceID.values
                    .map { normalizePubkey($0.pubkey) }
                    .filter { !$0.isEmpty }
            )
        )
        let replyTargetProfilesByPubkey = await profileCache.cachedProfiles(pubkeys: replyTargetPubkeys)

        let items = events.map { event in
            let normalizedPubkey = normalizePubkey(event.pubkey)
            let displayEvent = displayEventsBySourceID[event.id.lowercased()]
            let displayProfile = displayEvent.flatMap { displayProfilesByPubkey[normalizePubkey($0.pubkey)] }
            let replyTargetEvent = replyTargetEventsBySourceID[event.id.lowercased()]
            let replyTargetProfile = replyTargetEvent.flatMap {
                replyTargetProfilesByPubkey[normalizePubkey($0.pubkey)]
            }

            return FeedItem(
                event: event,
                profile: actorProfilesByPubkey[normalizedPubkey],
                displayEventOverride: displayEvent,
                displayProfileOverride: displayProfile,
                replyTargetEvent: replyTargetEvent,
                replyTargetProfile: replyTargetProfile
            )
        }
        return filterVisibleFeedItems(items, moderationSnapshot: moderationSnapshot)
    }

    private func buildAuthorOnlyFeedItems(
        relayURLs: [URL],
        events: [NostrEvent],
        fetchTimeout: TimeInterval = 8,
        relayFetchMode: RelayFetchMode = .allRelays,
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async -> [FeedItem] {
        let uniqueEvents = deduplicateEvents(
            filterVisibleEvents(events, moderationSnapshot: moderationSnapshot)
        )
        let profilesByPubkey = await hydrateActorProfiles(
            for: uniqueEvents,
            relayURLs: relayURLs,
            fetchTimeout: fetchTimeout,
            relayFetchMode: relayFetchMode
        )
        let items = uniqueEvents.map { event in
            let normalizedPubkey = normalizePubkey(event.pubkey)
            return FeedItem(event: event, profile: profilesByPubkey[normalizedPubkey])
        }
        return filterVisibleFeedItems(items, moderationSnapshot: moderationSnapshot)
    }

    private func expandedTimelineLimit(
        for limit: Int,
        moderationSnapshot: MuteFilterSnapshot?
    ) -> Int {
        guard moderationSnapshot?.hasAnyRules == true else { return limit }
        return min(max(limit * 4, limit), 240)
    }

    private func filterVisibleEvents(
        _ events: [NostrEvent],
        moderationSnapshot: MuteFilterSnapshot?
    ) -> [NostrEvent] {
        guard let moderationSnapshot, moderationSnapshot.hasAnyRules else {
            return events
        }
        return events.filter { !moderationSnapshot.shouldHide($0) }
    }

    private func filterVisibleFeedItems(
        _ items: [FeedItem],
        moderationSnapshot: MuteFilterSnapshot?
    ) -> [FeedItem] {
        guard let moderationSnapshot, moderationSnapshot.hasAnyRules else {
            return items
        }
        return items.filter { !moderationSnapshot.shouldHideAny(in: $0.moderationEvents) }
    }

    private func hydrateActorProfiles(
        for events: [NostrEvent],
        relayURLs: [URL],
        fetchTimeout: TimeInterval = 8,
        relayFetchMode: RelayFetchMode = .allRelays
    ) async -> [String: NostrProfile] {
        let pubkeysToResolve = Array(
            Set(events.map { normalizePubkey($0.pubkey) })
                .filter { !$0.isEmpty }
        )
        guard !pubkeysToResolve.isEmpty else { return [:] }
        return await fetchProfiles(
            relayURLs: relayURLs,
            pubkeys: pubkeysToResolve,
            fetchTimeout: fetchTimeout,
            relayFetchMode: relayFetchMode
        )
    }

    private func resolveDisplayEvents(
        for events: [NostrEvent],
        relayURLs: [URL]
    ) async -> [String: NostrEvent] {
        let eventsByID = Dictionary(uniqueKeysWithValues: events.map { ($0.id.lowercased(), $0) })
        var displayEventsBySourceID: [String: NostrEvent] = [:]
        var missingSourceToTargetIDs: [String: String] = [:]
        var missingTargetIDs = Set<String>()

        for event in events where event.isRepost {
            let sourceID = event.id.lowercased()

            if let embeddedEvent = event.resolvedRepostContentEvent {
                displayEventsBySourceID[sourceID] = embeddedEvent
                continue
            }

            guard let targetID = event.repostTargetEventID else { continue }
            if let localTarget = eventsByID[targetID] {
                displayEventsBySourceID[sourceID] = localTarget.resolvedRepostContentEvent ?? localTarget
                continue
            }

            missingSourceToTargetIDs[sourceID] = targetID
            missingTargetIDs.insert(targetID)
        }

        guard !missingTargetIDs.isEmpty else { return displayEventsBySourceID }

        let cachedByID = await seenEventStore.events(ids: Array(missingTargetIDs))
        if !cachedByID.isEmpty {
            var remainingSourceToTargetIDs: [String: String] = [:]
            for (sourceID, targetID) in missingSourceToTargetIDs {
                if let targetEvent = cachedByID[targetID] {
                    displayEventsBySourceID[sourceID] = targetEvent.resolvedRepostContentEvent ?? targetEvent
                } else {
                    remainingSourceToTargetIDs[sourceID] = targetID
                }
            }

            missingSourceToTargetIDs = remainingSourceToTargetIDs
            missingTargetIDs = Set(remainingSourceToTargetIDs.values)
        }

        guard !missingTargetIDs.isEmpty else { return displayEventsBySourceID }

        let idsFilter = NostrFilter(
            ids: Array(missingTargetIDs),
            limit: max(missingTargetIDs.count * 2, missingTargetIDs.count)
        )

        guard let fetched = try? await fetchTimelineEvents(
            relayURLs: relayURLs,
            filter: idsFilter,
            useCache: false
        ) else {
            return displayEventsBySourceID
        }

        let fetchedByID = Dictionary(
            uniqueKeysWithValues: deduplicateEvents(fetched).map { ($0.id.lowercased(), $0) }
        )

        for (sourceID, targetID) in missingSourceToTargetIDs {
            guard let targetEvent = fetchedByID[targetID] else { continue }
            displayEventsBySourceID[sourceID] = targetEvent.resolvedRepostContentEvent ?? targetEvent
        }

        return displayEventsBySourceID
    }

    private func resolveCachedDisplayEvents(
        for events: [NostrEvent]
    ) async -> [String: NostrEvent] {
        let eventsByID = Dictionary(uniqueKeysWithValues: events.map { ($0.id.lowercased(), $0) })
        var displayEventsBySourceID: [String: NostrEvent] = [:]
        var missingSourceToTargetIDs: [String: String] = [:]
        var missingTargetIDs = Set<String>()

        for event in events where event.isRepost {
            let sourceID = event.id.lowercased()

            if let embeddedEvent = event.resolvedRepostContentEvent {
                displayEventsBySourceID[sourceID] = embeddedEvent
                continue
            }

            guard let targetID = event.repostTargetEventID else { continue }
            if let localTarget = eventsByID[targetID] {
                displayEventsBySourceID[sourceID] = localTarget.resolvedRepostContentEvent ?? localTarget
                continue
            }

            missingSourceToTargetIDs[sourceID] = targetID
            missingTargetIDs.insert(targetID)
        }

        guard !missingTargetIDs.isEmpty else { return displayEventsBySourceID }

        let cachedByID = await seenEventStore.events(ids: Array(missingTargetIDs))
        for (sourceID, targetID) in missingSourceToTargetIDs {
            guard let targetEvent = cachedByID[targetID] else { continue }
            displayEventsBySourceID[sourceID] = targetEvent.resolvedRepostContentEvent ?? targetEvent
        }

        return displayEventsBySourceID
    }

    private func resolveCachedReplyTargetEvents(
        for events: [NostrEvent],
        displayEventsBySourceID: [String: NostrEvent]
    ) async -> [String: NostrEvent] {
        let availableEvents = deduplicateEvents(events + Array(displayEventsBySourceID.values))
        let availableEventsByID = Dictionary(
            uniqueKeysWithValues: availableEvents.map { ($0.id.lowercased(), $0) }
        )

        var resolvedBySourceID: [String: NostrEvent] = [:]
        var missingSourceToTargetIDs: [String: String] = [:]
        var missingTargetIDs = Set<String>()

        for event in events {
            let sourceID = event.id.lowercased()
            let replySourceEvent = displayEventsBySourceID[sourceID] ?? event
            guard replySourceEvent.isReplyNote else { continue }
            guard let targetID = normalizedEventID(replySourceEvent.directReplyEventReferenceID) else { continue }

            if let targetEvent = availableEventsByID[targetID] {
                resolvedBySourceID[sourceID] = targetEvent.resolvedRepostContentEvent ?? targetEvent
            } else {
                missingSourceToTargetIDs[sourceID] = targetID
                missingTargetIDs.insert(targetID)
            }
        }

        guard !missingTargetIDs.isEmpty else { return resolvedBySourceID }

        let cachedByID = await seenEventStore.events(ids: Array(missingTargetIDs))
        for (sourceID, targetID) in missingSourceToTargetIDs {
            guard let targetEvent = cachedByID[targetID] else { continue }
            resolvedBySourceID[sourceID] = targetEvent.resolvedRepostContentEvent ?? targetEvent
        }

        return resolvedBySourceID
    }

    private func resolveReplyTargetEvents(
        for events: [NostrEvent],
        displayEventsBySourceID: [String: NostrEvent],
        relayURLs: [URL]
    ) async -> [String: NostrEvent] {
        let availableEvents = deduplicateEvents(events + Array(displayEventsBySourceID.values))
        let availableEventsByID = Dictionary(
            uniqueKeysWithValues: availableEvents.map { ($0.id.lowercased(), $0) }
        )

        var resolvedBySourceID: [String: NostrEvent] = [:]
        var missingSourceToTargetIDs: [String: String] = [:]
        var missingTargetIDs = Set<String>()

        for event in events {
            let sourceID = event.id.lowercased()
            let replySourceEvent = displayEventsBySourceID[sourceID] ?? event
            guard replySourceEvent.isReplyNote else { continue }
            guard let targetID = normalizedEventID(replySourceEvent.directReplyEventReferenceID) else { continue }

            if let localTarget = availableEventsByID[targetID] {
                resolvedBySourceID[sourceID] = localTarget.resolvedRepostContentEvent ?? localTarget
                continue
            }

            missingSourceToTargetIDs[sourceID] = targetID
            missingTargetIDs.insert(targetID)
        }

        guard !missingTargetIDs.isEmpty else { return resolvedBySourceID }

        let cachedByID = await seenEventStore.events(ids: Array(missingTargetIDs))
        if !cachedByID.isEmpty {
            var remainingSourceToTargetIDs: [String: String] = [:]
            for (sourceID, targetID) in missingSourceToTargetIDs {
                if let targetEvent = cachedByID[targetID] {
                    resolvedBySourceID[sourceID] = targetEvent.resolvedRepostContentEvent ?? targetEvent
                } else {
                    remainingSourceToTargetIDs[sourceID] = targetID
                }
            }

            missingSourceToTargetIDs = remainingSourceToTargetIDs
            missingTargetIDs = Set(remainingSourceToTargetIDs.values)
        }

        guard !missingTargetIDs.isEmpty else { return resolvedBySourceID }

        let idsFilter = NostrFilter(
            ids: Array(missingTargetIDs),
            limit: max(missingTargetIDs.count * 2, missingTargetIDs.count)
        )

        guard let fetched = try? await fetchTimelineEvents(
            relayURLs: relayURLs,
            filter: idsFilter,
            useCache: false
        ) else {
            return resolvedBySourceID
        }

        let fetchedByID = Dictionary(
            uniqueKeysWithValues: deduplicateEvents(fetched).map { ($0.id.lowercased(), $0) }
        )

        for (sourceID, targetID) in missingSourceToTargetIDs {
            guard let targetEvent = fetchedByID[targetID] else { continue }
            resolvedBySourceID[sourceID] = targetEvent.resolvedRepostContentEvent ?? targetEvent
        }

        return resolvedBySourceID
    }

    private func resolveActivityTargetEvents(
        relayURLs: [URL],
        sourceEvents: [NostrEvent],
        fetchTimeout: TimeInterval = 12,
        relayFetchMode: RelayFetchMode = .allRelays
    ) async -> [ActivityTargetReference: NostrEvent] {
        let eventsByID = Dictionary(uniqueKeysWithValues: sourceEvents.map { ($0.id.lowercased(), $0) })

        var resolved: [ActivityTargetReference: NostrEvent] = [:]
        let uniqueReferences = Array(Set(sourceEvents.compactMap { $0.activityTargetReference }))
        guard !uniqueReferences.isEmpty else { return resolved }

        var missingEventIDs = Set<String>()
        var missingAddresses = Set<ActivityAddress>()

        for reference in uniqueReferences {
            switch reference {
            case .eventID(let eventID):
                let normalizedEventID = eventID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalizedEventID.isEmpty else { continue }
                if let event = eventsByID[normalizedEventID] {
                    resolved[reference] = event
                } else {
                    missingEventIDs.insert(normalizedEventID)
                }

            case .address(let address):
                missingAddresses.insert(address)
            }
        }

        if !missingEventIDs.isEmpty {
            let cachedByID = await seenEventStore.events(ids: Array(missingEventIDs))
            if !cachedByID.isEmpty {
                for eventID in Array(missingEventIDs) {
                    if let event = cachedByID[eventID] {
                        resolved[.eventID(eventID)] = event
                        missingEventIDs.remove(eventID)
                    }
                }
            }
        }

        if !missingEventIDs.isEmpty {
            let idsFilter = NostrFilter(
                ids: Array(missingEventIDs),
                limit: missingEventIDs.count
            )
            if let fetched = try? await fetchTimelineEvents(
                relayURLs: relayURLs,
                filter: idsFilter,
                timeout: fetchTimeout,
                relayFetchMode: relayFetchMode
            ) {
                for event in deduplicateEvents(fetched).sorted(by: { lhs, rhs in
                    if lhs.createdAt == rhs.createdAt {
                        return lhs.id > rhs.id
                    }
                    return lhs.createdAt > rhs.createdAt
                }) {
                    resolved[.eventID(event.id.lowercased())] = event
                }
            }
        }

        if !missingAddresses.isEmpty {
            let groupedAddresses = Dictionary(grouping: Array(missingAddresses), by: { "\($0.kind)|\($0.pubkey)" })

            for (_, addresses) in groupedAddresses {
                guard let sample = addresses.first else { continue }
                let identifiers = Array(Set(addresses.map(\.identifier)))
                let addressFilter = NostrFilter(
                    authors: [sample.pubkey],
                    kinds: [sample.kind],
                    limit: max(identifiers.count * 4, 20),
                    tagFilters: ["d": identifiers]
                )

                guard let fetched = try? await fetchTimelineEvents(
                    relayURLs: relayURLs,
                    filter: addressFilter,
                    timeout: fetchTimeout,
                    relayFetchMode: relayFetchMode
                ) else {
                    continue
                }

                let newestByAddress = newestAddressEvents(from: fetched, addresses: Set(addresses))
                for (address, event) in newestByAddress {
                    resolved[.address(address)] = event
                }
            }
        }

        return resolved
    }

    private func newestAddressEvents(
        from events: [NostrEvent],
        addresses: Set<ActivityAddress>
    ) -> [ActivityAddress: NostrEvent] {
        guard !addresses.isEmpty else { return [:] }

        var newestByAddress: [ActivityAddress: NostrEvent] = [:]
        let sorted = deduplicateEvents(events).sorted(by: { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id > rhs.id
            }
            return lhs.createdAt > rhs.createdAt
        })

        for event in sorted {
            let normalizedPubkey = event.pubkey.lowercased()
            guard let identifier = firstReplaceableIdentifier(in: event) else { continue }
            let address = ActivityAddress(kind: event.kind, pubkey: normalizedPubkey, identifier: identifier)
            guard addresses.contains(address) else { continue }
            if newestByAddress[address] == nil {
                newestByAddress[address] = event
            }
        }

        return newestByAddress
    }

    private func firstReplaceableIdentifier(in event: NostrEvent) -> String? {
        for tag in event.tags {
            guard let name = tag.first?.lowercased(), name == "d" else { continue }
            guard tag.count > 1 else { continue }
            let identifier = tag[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !identifier.isEmpty {
                return identifier
            }
        }
        return nil
    }

    private func fallbackActivitySnippet(for event: NostrEvent, action: ActivityAction) -> String {
        switch action {
        case .mention, .reply, .quoteShare:
            return event.activitySnippet()
        case .reaction(let reaction):
            return reaction.displayValue
        case .reshare:
            return "Re-shared your note"
        }
    }

    private func filteredActivityEvents(
        from events: [NostrEvent],
        currentUserPubkey: String
    ) -> [NostrEvent] {
        deduplicateEvents(
            events
                .filter { $0.activityAction != nil }
                .filter { $0.mentionedPubkeys.contains(where: { $0.lowercased() == currentUserPubkey }) }
                .filter { normalizePubkey($0.pubkey) != currentUserPubkey }
                .sorted(by: { lhs, rhs in
                    if lhs.createdAt == rhs.createdAt {
                        return lhs.id > rhs.id
                    }
                    return lhs.createdAt > rhs.createdAt
                })
        )
    }

    private func normalizedEventID(_ value: String?) -> String? {
        let normalized = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizedSearchTerms(from query: String) -> [String] {
        query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func shouldLocallyVerifyNIP50Results(for query: String) -> Bool {
        !query.contains(":") && !query.contains("\"")
    }

    private func eventMatchesSearchTerms(_ event: NostrEvent, terms: [String]) -> Bool {
        guard !terms.isEmpty else { return true }
        let tagText = event.tags.flatMap { $0 }.joined(separator: " ")
        let haystack = "\(event.content) \(event.pubkey) \(event.id) \(tagText)"
            .lowercased()

        return terms.allSatisfy { haystack.contains($0) }
    }

    private func profileMatchesQuery(profile: NostrProfile, pubkey: String, query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return false }

        if pubkey.contains(normalizedQuery) {
            return true
        }

        let fields: [String] = [
            profile.displayName ?? "",
            profile.name ?? "",
            profile.nip05 ?? "",
            profile.website ?? "",
            profile.about ?? "",
            profile.lud16 ?? "",
            profile.lud06 ?? ""
        ]

        let haystack = fields.joined(separator: " ").lowercased()
        let terms = normalizedSearchTerms(from: normalizedQuery)
        guard !terms.isEmpty else { return false }
        return terms.allSatisfy { haystack.contains($0) || pubkey.contains($0) }
    }

    private func deduplicateEvents(_ events: [NostrEvent]) -> [NostrEvent] {
        var uniqueEvents: [NostrEvent] = []
        var seen = Set<String>()
        for event in events where !seen.contains(event.id) {
            uniqueEvents.append(event)
            seen.insert(event.id)
        }
        return uniqueEvents
    }

    private func fetchProfilesForPubkeys(
        relayURLs: [URL],
        pubkeys: [String],
        timeout: TimeInterval,
        relayFetchMode: RelayFetchMode = .allRelays
    ) async -> [String: NostrProfile] {
        let normalizedTargets = Array(
            Set(
                pubkeys
                    .map { normalizePubkey($0) }
                    .filter { !$0.isEmpty }
            )
        )
        guard !normalizedTargets.isEmpty else { return [:] }
        let targetRelayURLs = normalizedRelayURLs(relayURLs)
        guard !targetRelayURLs.isEmpty else { return [:] }

        var collectedProfiles: [String: NostrProfile] = [:]

        for chunk in normalizedTargets.chunked(into: 100) {
            let metadataFilter = NostrFilter(
                authors: chunk,
                kinds: [0],
                limit: max(chunk.count * 2, 100)
            )

            guard let metadataEvents = try? await fetchTimelineEvents(
                relayURLs: targetRelayURLs,
                filter: metadataFilter,
                timeout: timeout,
                useCache: false,
                relayFetchMode: relayFetchMode
            ) else {
                continue
            }

            let decoded = decodeNewestProfiles(from: metadataEvents)
            guard !decoded.isEmpty else { continue }
            collectedProfiles.merge(decoded, uniquingKeysWith: { existing, _ in existing })
        }

        return collectedProfiles
    }

    private func decodeNewestProfiles(from events: [NostrEvent]) -> [String: NostrProfile] {
        let newestFirst = deduplicateEvents(events)
            .filter { $0.kind == 0 }
            .sorted(by: { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id > rhs.id
                }
                return lhs.createdAt > rhs.createdAt
            })

        var decodedByPubkey: [String: NostrProfile] = [:]
        for event in newestFirst {
            let normalizedPubkey = normalizePubkey(event.pubkey)
            guard !normalizedPubkey.isEmpty else { continue }
            guard decodedByPubkey[normalizedPubkey] == nil else { continue }
            guard let profile = NostrProfile.decode(from: event.content) else { continue }
            decodedByPubkey[normalizedPubkey] = profile
        }
        return decodedByPubkey
    }

    private func fetchTimelineEvents(
        relayURL: URL,
        filter: NostrFilter,
        timeout: TimeInterval = 12,
        useCache: Bool = true
    ) async throws -> [NostrEvent] {
        let events: [NostrEvent]
        if !useCache {
            events = try await relayClient.fetchEvents(relayURL: relayURL, filter: filter, timeout: timeout)
        } else {
            let cacheKey = generateTimelineKey(relayURL: relayURL, filter: filter)
            events = try await timelineCache.events(for: cacheKey) {
                try await relayClient.fetchEvents(relayURL: relayURL, filter: filter, timeout: timeout)
            }
        }

        if !events.isEmpty {
            await seenEventStore.store(events: events)
        }
        return events
    }

    private func fetchTimelineEvents(
        relayURLs: [URL],
        filter: NostrFilter,
        timeout: TimeInterval = 12,
        useCache: Bool = true,
        relayFetchMode: RelayFetchMode = .allRelays
    ) async throws -> [NostrEvent] {
        let targets = normalizedRelayURLs(relayURLs)
        guard !targets.isEmpty else { return [] }
        if targets.count == 1, let onlyRelay = targets.first {
            return try await fetchTimelineEvents(
                relayURL: onlyRelay,
                filter: filter,
                timeout: timeout,
                useCache: useCache
            )
        }

        let result: (mergedEvents: [NostrEvent], successfulFetches: Int, firstError: Error?) = await withTaskGroup(
            of: (events: [NostrEvent]?, error: Error?).self,
            returning: (mergedEvents: [NostrEvent], successfulFetches: Int, firstError: Error?).self
        ) { group in
            for relayURL in targets {
                group.addTask {
                    do {
                        let events = try await fetchTimelineEvents(
                            relayURL: relayURL,
                            filter: filter,
                            timeout: timeout,
                            useCache: useCache
                        )
                        return (events: events, error: nil)
                    } catch {
                        return (events: nil, error: error)
                    }
                }
            }

            var mergedEvents: [NostrEvent] = []
            var firstError: Error?
            var successfulFetches = 0

            for await item in group {
                if let events = item.events {
                    successfulFetches += 1

                    switch relayFetchMode {
                    case .allRelays:
                        mergedEvents.append(contentsOf: events)
                    case .firstNonEmptyRelay:
                        if !events.isEmpty {
                            group.cancelAll()
                            return (events, successfulFetches, firstError)
                        }
                    }
                } else if firstError == nil, let error = item.error {
                    firstError = error
                }
            }

            return (mergedEvents, successfulFetches, firstError)
        }

        if result.successfulFetches == 0, let firstError = result.firstError {
            throw firstError
        }
        return result.mergedEvents
    }

    private func extractFollowListSnapshot(from events: [NostrEvent]) -> FollowListSnapshot? {
        guard let newest = events
            .filter({ $0.kind == 3 })
            .sorted(by: { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id > rhs.id
                }
                return lhs.createdAt > rhs.createdAt
            })
            .first else {
            return nil
        }

        return FollowListSnapshot(
            content: newest.content,
            tags: newest.tags
        )
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

    private func metadataRelayURLs(primaryRelayURLs: [URL]) -> [URL] {
        normalizedRelayURLs(primaryRelayURLs + Self.metadataFallbackRelayURLs)
    }

    private func normalizePubkey(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return [] }
        var result: [[Element]] = []
        result.reserveCapacity((count + size - 1) / size)

        var index = startIndex
        while index < endIndex {
            let nextIndex = Swift.min(index + size, endIndex)
            result.append(Array(self[index..<nextIndex]))
            index = nextIndex
        }

        return result
    }
}
