import XCTest
@testable import Flow

final class NostrFeedServiceTests: XCTestCase {
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
        let profileSnapshotStore = ProfileSnapshotStore(fileManager: fileManager)
        let service = NostrFeedService(
            relayClient: relayClient,
            timelineCache: TimelineEventCache(),
            profileCache: ProfileCache(snapshotStore: profileSnapshotStore),
            relayHintCache: ProfileRelayHintCache(),
            followListCache: FollowListSnapshotCache(fileManager: fileManager),
            seenEventStore: SeenEventStore(fileManager: fileManager)
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
}

private let relayURL = URL(string: "wss://relay.example.com")!

private actor SpyRelayClient: NostrRelayEventFetching {
    private var fetchCallCount = 0

    func fetchEvents(
        relayURL: URL,
        filter: NostrFilter,
        timeout: TimeInterval
    ) async throws -> [NostrEvent] {
        fetchCallCount += 1
        return []
    }

    func fetchCount() -> Int {
        fetchCallCount
    }
}

private actor ThreadReplyRelayClient: NostrRelayEventFetching {
    private let rootEventID: String
    private let directReply: NostrEvent
    private let nestedReply: NostrEvent
    private var fetchCallCount = 0

    init(rootEventID: String, directReply: NostrEvent, nestedReply: NostrEvent) {
        self.rootEventID = rootEventID
        self.directReply = directReply
        self.nestedReply = nestedReply
    }

    func fetchEvents(
        relayURL: URL,
        filter: NostrFilter,
        timeout: TimeInterval
    ) async throws -> [NostrEvent] {
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

private final class TestHarness {
    let rootURL: URL
    let relayClient: SpyRelayClient
    let profileCache: ProfileCache
    let seenEventStore: SeenEventStore
    let service: NostrFeedService

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let fileManager = TestFileManager(rootURL: rootURL)
        let profileSnapshotStore = ProfileSnapshotStore(fileManager: fileManager)
        let relayHintCache = ProfileRelayHintCache()
        let followListCache = FollowListSnapshotCache(fileManager: fileManager)

        relayClient = SpyRelayClient()
        profileCache = ProfileCache(snapshotStore: profileSnapshotStore)
        seenEventStore = SeenEventStore(fileManager: fileManager)
        service = NostrFeedService(
            relayClient: relayClient,
            timelineCache: TimelineEventCache(),
            profileCache: profileCache,
            relayHintCache: relayHintCache,
            followListCache: followListCache,
            seenEventStore: seenEventStore
        )
    }
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
) -> NostrEvent {
    NostrEvent(
        id: id,
        pubkey: pubkey,
        createdAt: createdAt,
        kind: kind,
        tags: tags,
        content: content,
        sig: String(repeating: "f", count: 128)
    )
}

private func originalEventJSON(for event: NostrEvent) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try? encoder.encode(event)
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
}

private func hex(_ character: Character) -> String {
    String(repeating: String(character), count: 64)
}
