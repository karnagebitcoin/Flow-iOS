import XCTest
import NostrSDK
@testable import Flow

final class NostrFeedServiceTests: XCTestCase {
    func testNostrProfileDecodeReadsBannerMetadataKeys() {
        let bannerJSON = """
        {
          "name": "alice",
          "banner": "https://example.com/banner.jpg"
        }
        """

        let coverJSON = """
        {
          "name": "alice",
          "cover": "https://example.com/cover.jpg"
        }
        """

        XCTAssertEqual(NostrProfile.decode(from: bannerJSON)?.banner, "https://example.com/banner.jpg")
        XCTAssertEqual(NostrProfile.decode(from: coverJSON)?.banner, "https://example.com/cover.jpg")
    }

    func testIngestLiveEventsStoresEventsLocally() async throws {
        let harness = try TestHarness()
        let event = makeEvent(
            id: hex("a"),
            pubkey: hex("b"),
            kind: 1,
            tags: [["t", "flow"]],
            content: "live event"
        )

        await harness.service.ingestLiveEvents([event])

        let resolved = await harness.seenEventStore.events(ids: [event.id])
        XCTAssertEqual(resolved[event.id.lowercased()]?.id.lowercased(), event.id.lowercased())

        let diagnostics = harness.nostrDatabase.diagnosticsSnapshot()
        XCTAssertEqual(diagnostics.sessionIngestedEventCount, 1)
        XCTAssertEqual(diagnostics.ingestCallCount, 1)
        XCTAssertEqual(diagnostics.successfulIngestCallCount, 1)
    }

    func testProfileEventServicePersistsFetchedMetadataSnapshotsLocally() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowProfileEventService-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = TestFileManager(rootURL: rootURL)
        let nostrDatabase = FlowNostrDB(fileManager: fileManager)
        let seenEventStore = SeenEventStore(fileManager: fileManager, nostrDatabase: nostrDatabase)
        let pubkey = hex("a")
        let older = makeEvent(
            id: hex("b"),
            pubkey: pubkey,
            kind: 0,
            tags: [],
            content: #"{"name":"older"}"#,
            createdAt: 1_700_000_000
        )
        let newer = makeEvent(
            id: hex("c"),
            pubkey: pubkey,
            kind: 0,
            tags: [],
            content: #"{"name":"newer"}"#,
            createdAt: 1_700_000_100
        )
        let relayClient = ProfileMetadataRelayClient(eventsByRelay: [
            relayURL: [older],
            relayURL2: [newer]
        ])
        let service = ProfileEventService(relayClient: relayClient, seenEventStore: seenEventStore)

        let snapshot = try await service.fetchProfileMetadataSnapshot(
            relayURLs: [relayURL, relayURL2],
            pubkey: pubkey
        )

        XCTAssertEqual(snapshot?.content, newer.content)
        XCTAssertEqual(nostrDatabase.profile(pubkey: pubkey)?.name, "newer")
        let diagnostics = nostrDatabase.diagnosticsSnapshot()
        XCTAssertEqual(diagnostics.sessionIngestedProfileCount, 1)
        XCTAssertEqual(diagnostics.successfulIngestCallCount, 1)
    }

    func testFetchProfilesBackfillsSnapshotOnlyProfilesIntoNostrDB() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowProfileBackfill-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = TestFileManager(rootURL: rootURL)
        let profileSnapshotStore = ProfileSnapshotStore(fileManager: fileManager)
        let nostrDatabase = FlowNostrDB(fileManager: fileManager)
        let followListCache = FollowListSnapshotCache(fileManager: fileManager, nostrDatabase: nostrDatabase)
        let seenEventStore = SeenEventStore(fileManager: fileManager, nostrDatabase: nostrDatabase)
        let profileCache = ProfileCache(snapshotStore: profileSnapshotStore, nostrDatabase: nostrDatabase)
        let pubkey = hex("d")
        let cachedProfile = makeProfile(name: "cached", displayName: "Cached")
        await profileSnapshotStore.putMany(entries: [
            pubkey: PersistedProfileSnapshot(profile: cachedProfile, fetchedAt: Date())
        ])

        let freshProfileEvent = makeEvent(
            id: hex("e"),
            pubkey: pubkey,
            kind: 0,
            tags: [],
            content: #"{"name":"fresh","display_name":"Fresh"}"#,
            createdAt: 1_700_000_200
        )
        let relayClient = ProfileMetadataRelayClient(eventsByRelay: [
            relayURL: [freshProfileEvent]
        ])
        let service = NostrFeedService(
            relayClient: relayClient,
            timelineCache: TimelineEventCache(),
            profileCache: profileCache,
            relayHintCache: ProfileRelayHintCache(),
            followListCache: followListCache,
            seenEventStore: seenEventStore,
            nostrDatabase: nostrDatabase
        )

        let profiles = await service.fetchProfiles(relayURLs: [relayURL], pubkeys: [pubkey])

        XCTAssertEqual(profiles[pubkey]?.name, "fresh")
        XCTAssertEqual(nostrDatabase.profile(pubkey: pubkey)?.name, "fresh")
        let diagnostics = nostrDatabase.diagnosticsSnapshot()
        XCTAssertEqual(diagnostics.sessionIngestedProfileCount, 1)
        XCTAssertEqual(diagnostics.successfulIngestCallCount, 1)
    }

    func testSearchProfilesReturnsLocalMatchWithoutRelayFetchWhenLimitSatisfied() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowLocalProfileSearch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = TestFileManager(rootURL: rootURL)
        let nostrDatabase = FlowNostrDB(fileManager: fileManager)
        let relayClient = SpyRelayClient()
        let service = NostrFeedService(
            relayClient: relayClient,
            timelineCache: TimelineEventCache(),
            profileCache: ProfileCache(
                snapshotStore: ProfileSnapshotStore(fileManager: fileManager),
                nostrDatabase: nostrDatabase
            ),
            relayHintCache: ProfileRelayHintCache(),
            followListCache: FollowListSnapshotCache(fileManager: fileManager, nostrDatabase: nostrDatabase),
            seenEventStore: SeenEventStore(fileManager: fileManager, nostrDatabase: nostrDatabase),
            nostrDatabase: nostrDatabase
        )

        let pubkey = hex("a")
        let event = makeEvent(
            id: hex("b"),
            pubkey: pubkey,
            kind: 0,
            tags: [],
            content: #"{"name":"holokat","display_name":"Holo Kat"}"#,
            createdAt: 1_700_000_300
        )

        XCTAssertTrue(nostrDatabase.ingest(events: [event]))

        let results = try await service.searchProfiles(
            relayURLs: [relayURL],
            query: "holokat",
            limit: 1,
            fetchTimeout: 0.01,
            relayFetchMode: .firstNonEmptyRelay
        )

        let fetchCount = await relayClient.fetchCount()

        XCTAssertEqual(results.map(\.pubkey), [pubkey])
        XCTAssertEqual(results.first?.profile?.name, "holokat")
        XCTAssertEqual(fetchCount, 0)
    }

    func testLocalProfileSearchScansFullLocalMetadataSetForNormalizedHandleMatches() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowFullLocalProfileSearch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = TestFileManager(rootURL: rootURL)
        let nostrDatabase = FlowNostrDB(fileManager: fileManager)
        let service = makeFeedService(
            relayClient: SpyRelayClient(),
            fileManager: fileManager,
            nostrDatabase: nostrDatabase
        )

        func paddedHex(_ value: Int) -> String {
            String(format: "%064x", value)
        }

        let targetPubkey = paddedHex(1)
        let targetEvent = makeEvent(
            id: paddedHex(10_001),
            pubkey: targetPubkey,
            kind: 0,
            tags: [],
            content: #"{"name":"Fiat Jaf","display_name":"Fiat Jaf"}"#,
            createdAt: 1_700_000_000
        )

        var metadataEvents = [targetEvent]
        metadataEvents.reserveCapacity(1_702)

        for index in 0..<1_700 {
            metadataEvents.append(
                makeEvent(
                    id: paddedHex(20_000 + index),
                    pubkey: paddedHex(30_000 + index),
                    kind: 0,
                    tags: [],
                    content: #"{"name":"user\#(index)","display_name":"User \#(index)"}"#,
                    createdAt: 1_700_000_100 + index
                )
            )
        }

        XCTAssertTrue(nostrDatabase.ingest(events: metadataEvents))

        let compactResults = await service.searchProfiles(query: "fiatjaf", limit: 8)
        let spacedResults = await service.searchProfiles(query: "fiat jaf", limit: 8)

        XCTAssertEqual(compactResults.first?.pubkey, targetPubkey)
        XCTAssertEqual(compactResults.first?.profile?.displayName, "Fiat Jaf")
        XCTAssertEqual(spacedResults.first?.pubkey, targetPubkey)
        XCTAssertEqual(spacedResults.first?.profile?.displayName, "Fiat Jaf")
    }

    func testLocalProfileSearchMatchesTokenizedDisplayNames() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowTokenizedLocalProfileSearch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = TestFileManager(rootURL: rootURL)
        let nostrDatabase = FlowNostrDB(fileManager: fileManager)
        let service = makeFeedService(
            relayClient: SpyRelayClient(),
            fileManager: fileManager,
            nostrDatabase: nostrDatabase
        )

        let targetPubkey = String(format: "%064x", 4_242)
        let targetEvent = makeEvent(
            id: String(format: "%064x", 9_999),
            pubkey: targetPubkey,
            kind: 0,
            tags: [],
            content: #"{"name":"Michael J. Saylor","display_name":"Michael J. Saylor"}"#,
            createdAt: 1_700_000_500
        )

        XCTAssertTrue(nostrDatabase.ingest(events: [targetEvent]))

        let results = await service.searchProfiles(query: "michael saylor", limit: 8)

        XCTAssertEqual(results.first?.pubkey, targetPubkey)
        XCTAssertEqual(results.first?.profile?.displayName, "Michael J. Saylor")
    }

    func testLocalProfileSearchRefreshesAfterNewMetadataIngest() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowRefreshingLocalProfileSearch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = TestFileManager(rootURL: rootURL)
        let nostrDatabase = FlowNostrDB(fileManager: fileManager)
        let service = makeFeedService(
            relayClient: SpyRelayClient(),
            fileManager: fileManager,
            nostrDatabase: nostrDatabase
        )

        let initialResults = await service.searchProfiles(query: "hal", limit: 8)
        XCTAssertTrue(initialResults.isEmpty)

        let targetPubkey = String(format: "%064x", 7_777)
        let targetEvent = makeEvent(
            id: String(format: "%064x", 8_888),
            pubkey: targetPubkey,
            kind: 0,
            tags: [],
            content: #"{"name":"hal","display_name":"Hal Finney"}"#,
            createdAt: 1_700_000_700
        )

        XCTAssertTrue(nostrDatabase.ingest(events: [targetEvent]))

        let refreshedResults = await service.searchProfiles(query: "hal", limit: 8)

        XCTAssertEqual(refreshedResults.first?.pubkey, targetPubkey)
        XCTAssertEqual(refreshedResults.first?.profile?.displayName, "Hal Finney")
    }

    func testStoreFollowListSnapshotLocallyCachesSnapshot() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowFollowSnapshotStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = TestFileManager(rootURL: rootURL)
        let nostrDatabase = FlowNostrDB(fileManager: fileManager)
        let followListCache = FollowListSnapshotCache(fileManager: fileManager, nostrDatabase: nostrDatabase)
        let service = NostrFeedService(
            relayClient: SpyRelayClient(),
            timelineCache: TimelineEventCache(),
            profileCache: ProfileCache(
                snapshotStore: ProfileSnapshotStore(fileManager: fileManager),
                nostrDatabase: nostrDatabase
            ),
            relayHintCache: ProfileRelayHintCache(),
            followListCache: followListCache,
            seenEventStore: SeenEventStore(fileManager: fileManager, nostrDatabase: nostrDatabase),
            nostrDatabase: nostrDatabase
        )

        let authorPubkey = hex("1")
        let followedPubkey = hex("2")
        let snapshot = FollowListSnapshot(
            content: "",
            tags: [["p", followedPubkey, relayURL.absoluteString]]
        )

        await service.storeFollowListSnapshotLocally(snapshot, for: authorPubkey)

        let cached = await followListCache.cachedSnapshot(pubkey: authorPubkey)
        XCTAssertEqual(cached?.followedPubkeys, [followedPubkey])
    }

    func testFetchKnownFollowersUsesPersistedFollowSnapshotsBeforeRelayFetch() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowKnownFollowers-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = TestFileManager(rootURL: rootURL)
        let nostrDatabase = FlowNostrDB(fileManager: fileManager)
        let followListCache = FollowListSnapshotCache(fileManager: fileManager, nostrDatabase: nostrDatabase)
        let relayClient = SpyRelayClient()
        let service = NostrFeedService(
            relayClient: relayClient,
            timelineCache: TimelineEventCache(),
            profileCache: ProfileCache(
                snapshotStore: ProfileSnapshotStore(fileManager: fileManager),
                nostrDatabase: nostrDatabase
            ),
            relayHintCache: ProfileRelayHintCache(),
            followListCache: followListCache,
            seenEventStore: SeenEventStore(fileManager: fileManager, nostrDatabase: nostrDatabase),
            nostrDatabase: nostrDatabase
        )

        let profilePubkey = hex("1")
        let knownFollowerPubkey = hex("2")
        let nonFollowerPubkey = hex("3")
        await followListCache.storeSnapshot(
            FollowListSnapshot(content: "", tags: [["p", profilePubkey]]),
            for: knownFollowerPubkey
        )
        await followListCache.storeSnapshot(
            FollowListSnapshot(content: "", tags: [["p", hex("4")]]),
            for: nonFollowerPubkey
        )

        let cached = await service.cachedKnownFollowers(
            profilePubkey: profilePubkey,
            candidatePubkeys: [nonFollowerPubkey, knownFollowerPubkey],
            limit: 5
        )
        XCTAssertEqual(cached, [knownFollowerPubkey])

        let fetched = await service.fetchKnownFollowers(
            relayURLs: [relayURL],
            profilePubkey: profilePubkey,
            candidatePubkeys: [knownFollowerPubkey],
            limit: 1
        )
        XCTAssertEqual(fetched, [knownFollowerPubkey])
        let fetchCount = await relayClient.fetchCount()
        XCTAssertEqual(fetchCount, 0)
    }

    @MainActor
    func testFollowStorePreservesSuccessfulPublishAcrossLogout() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowFollowStoreLogout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let defaultsSuite = "FlowFollowStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defer {
            defaults.removePersistentDomain(forName: defaultsSuite)
        }

        let fileManager = TestFileManager(rootURL: rootURL)
        let nostrDatabase = FlowNostrDB(fileManager: fileManager)
        let followListCache = FollowListSnapshotCache(fileManager: fileManager, nostrDatabase: nostrDatabase)
        let relayClient = FollowPublishRelayClient(publishDelayNanoseconds: 150_000_000)
        let service = NostrFeedService(
            relayClient: relayClient,
            timelineCache: TimelineEventCache(),
            profileCache: ProfileCache(
                snapshotStore: ProfileSnapshotStore(fileManager: fileManager),
                nostrDatabase: nostrDatabase
            ),
            relayHintCache: ProfileRelayHintCache(),
            followListCache: followListCache,
            seenEventStore: SeenEventStore(fileManager: fileManager, nostrDatabase: nostrDatabase),
            nostrDatabase: nostrDatabase
        )
        let followStore = FollowStore(
            defaults: defaults,
            authStore: AuthStore(defaults: defaults),
            feedService: service,
            relayClient: relayClient
        )

        let accountKeypair = try XCTUnwrap(Keypair())
        let targetKeypair = try XCTUnwrap(Keypair())
        let accountPubkey = accountKeypair.publicKey.hex.lowercased()
        let targetPubkey = targetKeypair.publicKey.hex.lowercased()

        followStore.configure(
            accountPubkey: accountPubkey,
            nsec: accountKeypair.privateKey.nsec,
            readRelayURLs: [relayURL],
            writeRelayURLs: [relayURL]
        )
        followStore.follow(targetPubkey)

        followStore.configure(
            accountPubkey: nil,
            nsec: nil,
            readRelayURLs: [relayURL],
            writeRelayURLs: [relayURL]
        )

        try await Task.sleep(nanoseconds: 400_000_000)

        let cachedSnapshot = await service.cachedFollowListSnapshot(pubkey: accountPubkey)
        let publishCount = await relayClient.publishCount()
        XCTAssertEqual(cachedSnapshot?.followedPubkeys, [targetPubkey])
        XCTAssertEqual(defaults.stringArray(forKey: "flow.followedPubkeys.\(accountPubkey)"), [targetPubkey])
        XCTAssertEqual(publishCount, 1)
    }

    func testReactionStatsPrefetchSkipsFreshNetworkRefetch() async throws {
        var rootURLBox: URL? = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowReactionStatsTests-\(UUID().uuidString)", isDirectory: true)
        let rootURL = try XCTUnwrap(rootURLBox)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer {
            rootURLBox = nil
            try? FileManager.default.removeItem(at: rootURL)
        }

        let relayClient = SpyRelayClient()
        let fileManager = TestFileManager(rootURL: rootURL)
        let store = NoteReactionStatsStore(fileManager: fileManager)
        let service = await MainActor.run {
            NoteReactionStatsService(relayClient: relayClient, store: store)
        }
        let note = makeEvent(
            id: hex("e"),
            pubkey: hex("f"),
            kind: 1,
            tags: [],
            content: "Hello"
        )

        await MainActor.run {
            service.prefetch(events: [note], relayURLs: [relayURL])
        }
        try await Task.sleep(nanoseconds: 350_000_000)

        await MainActor.run {
            service.prefetch(events: [note], relayURLs: [relayURL])
        }
        try await Task.sleep(nanoseconds: 350_000_000)

        let fetchCount = await relayClient.fetchCount()
        XCTAssertEqual(fetchCount, 1)
    }

    func testFetchThreadRepliesCanSkipNestedRepliesOnFastPath() async throws {
        var rootURLBox: URL? = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowThreadReplyTests-\(UUID().uuidString)", isDirectory: true)
        let rootURL = try XCTUnwrap(rootURLBox)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer {
            rootURLBox = nil
            try? FileManager.default.removeItem(at: rootURL)
        }

        let rootEventID = hex("1")
        let directReply = makeEvent(
            id: hex("2"),
            pubkey: hex("3"),
            kind: 1,
            tags: [["e", rootEventID, "", "reply"]],
            content: "Direct reply",
            createdAt: 1_700_000_001
        )
        let nestedReply = makeEvent(
            id: hex("4"),
            pubkey: hex("5"),
            kind: 1,
            tags: [
                ["e", rootEventID, "", "root"],
                ["e", directReply.id, "", "reply"]
            ],
            content: "Nested reply",
            createdAt: 1_700_000_002
        )

        let relayClient = ThreadReplyRelayClient(
            rootEventID: rootEventID,
            directReply: directReply,
            nestedReply: nestedReply
        )
        let fileManager = TestFileManager(rootURL: rootURL)
        let nostrDatabase = FlowNostrDB(fileManager: fileManager)
        let service = makeFeedService(
            relayClient: relayClient,
            fileManager: fileManager,
            nostrDatabase: nostrDatabase
        )

        let fastReplies = try await service.fetchThreadReplies(
            relayURLs: [relayURL],
            rootEventID: rootEventID,
            includeNestedReplies: false,
            hydrationMode: .cachedProfilesOnly,
            fetchTimeout: 0.01,
            relayFetchMode: .firstNonEmptyRelay
        )
        let fullReplies = try await service.fetchThreadReplies(
            relayURLs: [relayURL],
            rootEventID: rootEventID,
            includeNestedReplies: true,
            hydrationMode: .cachedProfilesOnly,
            fetchTimeout: 0.01,
            relayFetchMode: .firstNonEmptyRelay
        )

        let fetchCount = await relayClient.fetchCount()

        XCTAssertEqual(fastReplies.map(\.id), [directReply.id])
        XCTAssertEqual(fullReplies.map(\.id), [directReply.id, nestedReply.id])
        XCTAssertEqual(fetchCount, 2)
    }

    func testFeedItemMergePreservesRepostDisplayContextAcrossActorOnlyHydration() {
        let originalAuthorPubkey = hex("1")
        let repostActorPubkey = hex("2")
        let originalEvent = makeEvent(
            id: hex("a"),
            pubkey: originalAuthorPubkey,
            kind: 1,
            tags: [],
            content: "Alice note"
        )
        let repostEvent = makeEvent(
            id: hex("b"),
            pubkey: repostActorPubkey,
            kind: 6,
            tags: [["e", originalEvent.id]],
            content: originalEventJSON(for: originalEvent)
        )

        let cachedItem = FeedItem(
            event: repostEvent,
            profile: makeProfile(name: "bob", displayName: "Bob"),
            displayEventOverride: originalEvent,
            displayProfileOverride: makeProfile(name: "alice", displayName: "Alice")
        )
        let actorOnlyHydratedItem = FeedItem(
            event: repostEvent,
            profile: makeProfile(name: "bob", displayName: "Bob")
        )

        let merged = cachedItem.merged(with: actorOnlyHydratedItem)

        XCTAssertEqual(merged.actorDisplayName, "Bob")
        XCTAssertEqual(merged.displayEvent.id, originalEvent.id)
        XCTAssertEqual(merged.displayName, "Alice")
    }

    func testBuildNoteActivityRowsIncludesReactionsResharesAndQuotesForTargetNoteOnly() async throws {
        var harnessBox: TestHarness? = try TestHarness()
        let rootURL = try XCTUnwrap(harnessBox?.rootURL)
        defer {
            harnessBox = nil
            try? FileManager.default.removeItem(at: rootURL)
        }
        let harness = try XCTUnwrap(harnessBox)

        let rootEventID = hex("9")
        let rootAuthorPubkey = hex("8")
        let reactionActorPubkey = hex("1")
        let repostActorPubkey = hex("2")
        let quoteActorPubkey = hex("3")

        let rootEvent = makeEvent(
            id: rootEventID,
            pubkey: rootAuthorPubkey,
            kind: 1,
            tags: [],
            content: "Root note"
        )
        let reactionEvent = makeEvent(
            id: hex("a"),
            pubkey: reactionActorPubkey,
            kind: 7,
            tags: [["e", rootEventID, "", "reply"]],
            content: "+"
        )
        let repostEvent = makeEvent(
            id: hex("b"),
            pubkey: repostActorPubkey,
            kind: 6,
            tags: [["e", rootEventID, "", "mention"]],
            content: ""
        )
        let quoteEvent = makeEvent(
            id: hex("c"),
            pubkey: quoteActorPubkey,
            kind: 1,
            tags: [["q", rootEventID]],
            content: "Quoting this"
        )
        let unrelatedReply = makeEvent(
            id: hex("d"),
            pubkey: hex("4"),
            kind: 1,
            tags: [["e", rootEventID, "", "reply"]],
            content: "A reply should stay out of reactions"
        )

        await harness.seenEventStore.store(events: [rootEvent])

        let rows = await harness.service.buildNoteActivityRows(
            relayURLs: [relayURL],
            rootEventID: rootEventID,
            events: [reactionEvent, repostEvent, quoteEvent, unrelatedReply],
            fetchTimeout: 0.01,
            relayFetchMode: .firstNonEmptyRelay,
            profileFetchTimeout: 0.01,
            profileRelayFetchMode: .firstNonEmptyRelay
        )

        XCTAssertEqual(rows.map(\.id), [quoteEvent.id, repostEvent.id, reactionEvent.id])
        XCTAssertEqual(rows.map(\.action.title), ["Quote share", "Reshare", "Reaction"])
        XCTAssertTrue(rows.allSatisfy { $0.target.event?.id.lowercased() == rootEventID })
    }

    func testBuildActivityRowsUsesCachedActorAndTargetProfilesWithoutRelayFetch() async throws {
        var harnessBox: TestHarness? = try TestHarness()
        let rootURL = try XCTUnwrap(harnessBox?.rootURL)
        defer {
            harnessBox = nil
            try? FileManager.default.removeItem(at: rootURL)
        }
        let harness = try XCTUnwrap(harnessBox)

        let currentUserPubkey = hex("1")
        let actorPubkey = hex("2")
        let targetPubkey = hex("3")
        let targetEventID = hex("a")

        let actorProfile = makeProfile(name: "alice", displayName: "Alice")
        let targetProfile = makeProfile(name: "bob", displayName: "Bob")

        let targetEvent = makeEvent(
            id: targetEventID,
            pubkey: targetPubkey,
            kind: 1,
            tags: [["p", currentUserPubkey]],
            content: "Target note"
        )
        let reactionEvent = makeEvent(
            id: hex("b"),
            pubkey: actorPubkey,
            kind: 7,
            tags: [
                ["p", currentUserPubkey],
                ["e", targetEventID, "", "reply"]
            ],
            content: "+"
        )

        await harness.profileCache.store(
            profiles: [
                actorPubkey: actorProfile,
                targetPubkey: targetProfile
            ],
            missed: []
        )
        await harness.seenEventStore.store(events: [targetEvent])

        let rows = await harness.service.buildActivityRows(
            relayURLs: [relayURL],
            currentUserPubkey: currentUserPubkey,
            events: [reactionEvent],
            fetchTimeout: 0.01,
            relayFetchMode: RelayFetchMode.firstNonEmptyRelay,
            profileFetchTimeout: 0.01,
            profileRelayFetchMode: RelayFetchMode.firstNonEmptyRelay
        )

        let fetchCount = await harness.relayClient.fetchCount()

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.actor.displayName, "Alice")
        XCTAssertEqual(rows.first?.target.profile?.displayName, "Bob")
        XCTAssertEqual(fetchCount, 0)
    }

    func testBuildActivityRowsDoesNotFetchMissingTargetProfilesOnHotPath() async throws {
        var harnessBox: TestHarness? = try TestHarness()
        let rootURL = try XCTUnwrap(harnessBox?.rootURL)
        defer {
            harnessBox = nil
            try? FileManager.default.removeItem(at: rootURL)
        }
        let harness = try XCTUnwrap(harnessBox)

        let currentUserPubkey = hex("4")
        let actorPubkey = hex("5")
        let targetPubkey = hex("6")
        let targetEventID = hex("c")

        let actorProfile = makeProfile(name: "charlie", displayName: "Charlie")
        let targetEvent = makeEvent(
            id: targetEventID,
            pubkey: targetPubkey,
            kind: 1,
            tags: [["p", currentUserPubkey]],
            content: "Another target"
        )
        let reactionEvent = makeEvent(
            id: hex("d"),
            pubkey: actorPubkey,
            kind: 7,
            tags: [
                ["p", currentUserPubkey],
                ["e", targetEventID, "", "reply"]
            ],
            content: "+"
        )

        await harness.profileCache.store(
            profiles: [
                actorPubkey: actorProfile
            ],
            missed: []
        )
        await harness.seenEventStore.store(events: [targetEvent])

        let rows = await harness.service.buildActivityRows(
            relayURLs: [relayURL],
            currentUserPubkey: currentUserPubkey,
            events: [reactionEvent],
            fetchTimeout: 0.01,
            relayFetchMode: RelayFetchMode.firstNonEmptyRelay,
            profileFetchTimeout: 0.01,
            profileRelayFetchMode: RelayFetchMode.firstNonEmptyRelay
        )

        let fetchCount = await harness.relayClient.fetchCount()

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.actor.displayName, "Charlie")
        XCTAssertNil(rows.first?.target.profile)
        XCTAssertEqual(fetchCount, 0)
    }

    func testFetchAuthorFeedUsesNostrDBForPaginatedQueriesWithoutRelayFetch() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowAuthorFeedLocal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = TestFileManager(rootURL: rootURL)
        let database = FlowNostrDB(fileManager: fileManager)
        let relayClient = SpyRelayClient()
        let service = makeFeedService(
            relayClient: relayClient,
            fileManager: fileManager,
            nostrDatabase: database
        )
        let authorPubkey = hex("a")
        let newest = makeEvent(
            id: hex("b"),
            pubkey: authorPubkey,
            kind: 1,
            tags: [],
            content: "newest",
            createdAt: 1_700_000_300
        )
        let middle = makeEvent(
            id: hex("c"),
            pubkey: authorPubkey,
            kind: 1,
            tags: [],
            content: "middle",
            createdAt: 1_700_000_200
        )
        let oldest = makeEvent(
            id: hex("d"),
            pubkey: authorPubkey,
            kind: 1,
            tags: [],
            content: "oldest",
            createdAt: 1_700_000_100
        )

        XCTAssertTrue(database.ingest(events: [newest, middle, oldest]))

        let items = try await service.fetchAuthorFeed(
            relayURLs: [relayURL],
            authorPubkey: authorPubkey,
            kinds: [1],
            limit: 2,
            until: newest.createdAt - 1,
            hydrationMode: .cachedProfilesOnly,
            fetchTimeout: 0.01,
            relayFetchMode: .firstNonEmptyRelay
        )

        let fetchCount = await relayClient.fetchCount()

        XCTAssertEqual(items.map(\.id), [middle.id, oldest.id])
        XCTAssertEqual(fetchCount, 0)
    }

    func testFetchAuthorFeedReturnsLocalNostrDBResultsWhenRelayRefreshFails() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowAuthorFeedFallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = TestFileManager(rootURL: rootURL)
        let database = FlowNostrDB(fileManager: fileManager)
        let relayClient = FailingRelayClient()
        let service = makeFeedService(
            relayClient: relayClient,
            fileManager: fileManager,
            nostrDatabase: database
        )
        let authorPubkey = hex("e")
        let localEvent = makeEvent(
            id: hex("f"),
            pubkey: authorPubkey,
            kind: 1,
            tags: [],
            content: "local only",
            createdAt: 1_700_000_500
        )

        XCTAssertTrue(database.ingest(events: [localEvent]))

        let items = try await service.fetchAuthorFeed(
            relayURLs: [relayURL],
            authorPubkey: authorPubkey,
            kinds: [1],
            limit: 1,
            until: nil,
            hydrationMode: .cachedProfilesOnly,
            fetchTimeout: 0.01,
            relayFetchMode: .firstNonEmptyRelay
        )

        let fetchCount = await relayClient.fetchCount()

        XCTAssertEqual(items.map(\.id), [localEvent.id])
        XCTAssertEqual(fetchCount, 1)
    }

    func testReplyContextPreviewPresentationUsesParentSnippetForReplies() {
        let rootEvent = makeEvent(
            id: hex("1"),
            pubkey: hex("a"),
            kind: 1,
            tags: [],
            content: "Alice started the thread with some extra context."
        )
        let replyEvent = makeEvent(
            id: hex("2"),
            pubkey: hex("b"),
            kind: 1,
            tags: [
                ["e", rootEvent.id, "", "root"],
                ["e", rootEvent.id, "", "reply"]
            ],
            content: "Bob replied with the important middle comment."
        )
        let item = FeedItem(
            event: replyEvent,
            profile: makeProfile(name: "bob", displayName: "Bob"),
            replyTargetEvent: rootEvent,
            replyTargetProfile: makeProfile(name: "alice", displayName: "Alice")
        )

        let presentation = ReplyContextPreviewPresentation.make(for: item)

        XCTAssertNotNil(presentation)
        XCTAssertEqual(presentation?.parentItem.displayName, "Alice")
        XCTAssertEqual(presentation?.snippet, "Alice started the thread with some extra context.")
        XCTAssertEqual(presentation?.hasImageBadge, false)
    }

    func testReplyContextPreviewPresentationKeepsMediaOnlyParentsVisible() {
        let mediaURL = "https://example.com/alice.jpg"
        let rootEvent = makeEvent(
            id: hex("3"),
            pubkey: hex("c"),
            kind: 1,
            tags: [],
            content: mediaURL
        )
        let replyEvent = makeEvent(
            id: hex("4"),
            pubkey: hex("d"),
            kind: 1,
            tags: [
                ["e", rootEvent.id, "", "root"],
                ["e", rootEvent.id, "", "reply"]
            ],
            content: "Dan replied to the media post."
        )
        let item = FeedItem(
            event: replyEvent,
            profile: makeProfile(name: "dan", displayName: "Dan"),
            replyTargetEvent: rootEvent,
            replyTargetProfile: makeProfile(name: "alice", displayName: "Alice")
        )

        let presentation = ReplyContextPreviewPresentation.make(for: item)

        XCTAssertNotNil(presentation)
        XCTAssertNil(presentation?.snippet)
        XCTAssertEqual(presentation?.hasImageBadge, true)
    }
}

private let relayURL = URL(string: "wss://relay.example.com")!
private let relayURL2 = URL(string: "wss://relay-two.example.com")!

private actor SpyRelayClient: NostrRelayEventFetching {
    private var fetchCallCount = 0

    func fetchEvents(
        relayURL: URL,
        filter: NostrFilter,
        timeout: TimeInterval
    ) async throws -> [Flow.NostrEvent] {
        fetchCallCount += 1
        return []
    }

    func fetchCount() -> Int {
        fetchCallCount
    }
}

private actor FollowPublishRelayClient: NostrRelayEventFetching, NostrRelayEventPublishing {
    private let publishDelayNanoseconds: UInt64
    private var publishCallCount = 0

    init(publishDelayNanoseconds: UInt64) {
        self.publishDelayNanoseconds = publishDelayNanoseconds
    }

    func fetchEvents(
        relayURL: URL,
        filter: NostrFilter,
        timeout: TimeInterval
    ) async throws -> [Flow.NostrEvent] {
        []
    }

    func publishEvent(
        relayURL: URL,
        eventData: Data,
        eventID: String,
        timeout: TimeInterval
    ) async throws {
        publishCallCount += 1
        try await Task.sleep(nanoseconds: publishDelayNanoseconds)
    }

    func publishCount() -> Int {
        publishCallCount
    }
}

private actor ProfileMetadataRelayClient: NostrRelayEventFetching {
    private let eventsByRelay: [URL: [Flow.NostrEvent]]
    private var fetchCallCount = 0

    init(eventsByRelay: [URL: [Flow.NostrEvent]]) {
        self.eventsByRelay = eventsByRelay
    }

    func fetchEvents(
        relayURL: URL,
        filter: NostrFilter,
        timeout: TimeInterval
    ) async throws -> [Flow.NostrEvent] {
        fetchCallCount += 1

        let authors = Set(filter.authors ?? [])
        let kinds = Set(filter.kinds ?? [])
        let events = eventsByRelay[relayURL] ?? []
        return events.filter { event in
            (authors.isEmpty || authors.contains(event.pubkey)) &&
            (kinds.isEmpty || kinds.contains(event.kind))
        }
    }

    func fetchCount() -> Int {
        fetchCallCount
    }
}

private actor ThreadReplyRelayClient: NostrRelayEventFetching {
    private let rootEventID: String
    private let directReply: Flow.NostrEvent
    private let nestedReply: Flow.NostrEvent
    private var fetchCallCount = 0

    init(rootEventID: String, directReply: Flow.NostrEvent, nestedReply: Flow.NostrEvent) {
        self.rootEventID = rootEventID
        self.directReply = directReply
        self.nestedReply = nestedReply
    }

    func fetchEvents(
        relayURL: URL,
        filter: NostrFilter,
        timeout: TimeInterval
    ) async throws -> [Flow.NostrEvent] {
        fetchCallCount += 1

        let referencedEventIDs = Set(filter.tagFilters?["e"] ?? [])
        if referencedEventIDs.contains(rootEventID) {
            return [directReply]
        }
        if referencedEventIDs.contains(directReply.id) {
            return [nestedReply]
        }

        return []
    }

    func fetchCount() -> Int {
        fetchCallCount
    }
}

private actor FailingRelayClient: NostrRelayEventFetching {
    private var fetchCallCount = 0

    func fetchEvents(
        relayURL: URL,
        filter: NostrFilter,
        timeout: TimeInterval
    ) async throws -> [Flow.NostrEvent] {
        fetchCallCount += 1
        throw RelayClientError.closed("test failure")
    }

    func fetchCount() -> Int {
        fetchCallCount
    }
}

private final class TestHarness {
    let rootURL: URL
    let relayClient: SpyRelayClient
    let profileCache: ProfileCache
    let seenEventStore: SeenEventStore
    let nostrDatabase: FlowNostrDB
    let service: NostrFeedService

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let fileManager = TestFileManager(rootURL: rootURL)
        let profileSnapshotStore = ProfileSnapshotStore(fileManager: fileManager)
        let relayHintCache = ProfileRelayHintCache()
        nostrDatabase = FlowNostrDB(fileManager: fileManager)
        let followListCache = FollowListSnapshotCache(fileManager: fileManager, nostrDatabase: nostrDatabase)

        relayClient = SpyRelayClient()
        profileCache = ProfileCache(snapshotStore: profileSnapshotStore, nostrDatabase: nostrDatabase)
        seenEventStore = SeenEventStore(fileManager: fileManager, nostrDatabase: nostrDatabase)
        service = NostrFeedService(
            relayClient: relayClient,
            timelineCache: TimelineEventCache(),
            profileCache: profileCache,
            relayHintCache: relayHintCache,
            followListCache: followListCache,
            seenEventStore: seenEventStore,
            nostrDatabase: nostrDatabase
        )
    }
}

private func makeFeedService(
    relayClient: any NostrRelayEventFetching,
    fileManager: TestFileManager,
    nostrDatabase: FlowNostrDB
) -> NostrFeedService {
    let profileSnapshotStore = ProfileSnapshotStore(fileManager: fileManager)
    let profileCache = ProfileCache(snapshotStore: profileSnapshotStore, nostrDatabase: nostrDatabase)
    let followListCache = FollowListSnapshotCache(fileManager: fileManager, nostrDatabase: nostrDatabase)
    let seenEventStore = SeenEventStore(fileManager: fileManager, nostrDatabase: nostrDatabase)

    return NostrFeedService(
        relayClient: relayClient,
        timelineCache: TimelineEventCache(),
        profileCache: profileCache,
        relayHintCache: ProfileRelayHintCache(),
        followListCache: followListCache,
        seenEventStore: seenEventStore,
        nostrDatabase: nostrDatabase
    )
}

private final class TestFileManager: FileManager, @unchecked Sendable {
    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
        super.init()
    }

    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] {
        [rootURL]
    }
}

private func makeProfile(name: String, displayName: String) -> NostrProfile {
    NostrProfile(
        name: name,
        displayName: displayName,
        picture: nil,
        banner: nil,
        about: nil,
        nip05: nil,
        website: nil,
        lud06: nil,
        lud16: nil
    )
}

private func makeEvent(
    id: String,
    pubkey: String,
    kind: Int,
    tags: [[String]],
    content: String,
    createdAt: Int = 1_700_000_000
) -> Flow.NostrEvent {
    Flow.NostrEvent(
        id: id,
        pubkey: pubkey,
        createdAt: createdAt,
        kind: kind,
        tags: tags,
        content: content,
        sig: String(Array(repeating: "f", count: 128))
    )
}

private func originalEventJSON(for event: Flow.NostrEvent) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try? encoder.encode(event)
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
}

private func hex(_ character: Character) -> String {
    String(Array(repeating: character, count: 64))
}
