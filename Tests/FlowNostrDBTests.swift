import XCTest
@testable import Flow

final class FlowNostrDBTests: XCTestCase {
    func testIngestedEventIsImmediatelyAvailableByID() throws {
        let rootURL = try makeRootURL(prefix: "FlowNostrDBRoundTrip")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = FlowNostrDBTestFileManager(rootURL: rootURL)
        let database = FlowNostrDB(fileManager: fileManager)
        let event = makeTestEvent(
            id: hex("a"),
            pubkey: hex("b"),
            kind: 1,
            tags: [["t", "flow"]],
            content: "hello nostrdb"
        )

        XCTAssertTrue(database.ingest(events: [event]))

        let resolved = database.events(ids: [event.id])
        XCTAssertEqual(resolved?[event.id.lowercased()]?.id.lowercased(), event.id.lowercased())
        XCTAssertEqual(resolved?[event.id.lowercased()]?.content, event.content)
    }

    func testSeenEventStoreRecentFeedUsesNostrDBBackedEvents() async throws {
        let rootURL = try makeRootURL(prefix: "FlowSeenEventStore")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = FlowNostrDBTestFileManager(rootURL: rootURL)
        let database = FlowNostrDB(fileManager: fileManager)
        let store = SeenEventStore(fileManager: fileManager, nostrDatabase: database)
        let key = "following:test"

        let first = makeTestEvent(
            id: hex("1"),
            pubkey: hex("2"),
            kind: 1,
            tags: [],
            content: "first"
        )
        let second = makeTestEvent(
            id: hex("3"),
            pubkey: hex("4"),
            kind: 1,
            tags: [["e", first.id]],
            content: "second"
        )

        await store.storeRecentFeed(key: key, events: [first, second])
        let restored = await store.recentFeed(key: key)

        XCTAssertEqual(restored?.map { $0.id.lowercased() }, [first.id.lowercased(), second.id.lowercased()])
        XCTAssertEqual(restored?.map(\.content), [first.content, second.content])
    }

    func testFollowListSnapshotUsesLatestReplaceableEvent() throws {
        let rootURL = try makeRootURL(prefix: "FlowFollowListSnapshot")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = FlowNostrDBTestFileManager(rootURL: rootURL)
        let database = FlowNostrDB(fileManager: fileManager)
        let pubkey = hex("9")
        let firstFollowedPubkey = hex("a")
        let secondFollowedPubkey = hex("b")

        let older = makeTestEvent(
            id: hex("c"),
            pubkey: pubkey,
            kind: 3,
            tags: [["p", firstFollowedPubkey]],
            content: "old",
            createdAt: 1_700_000_000
        )
        let newer = makeTestEvent(
            id: hex("d"),
            pubkey: pubkey,
            kind: 3,
            tags: [["p", secondFollowedPubkey, "wss://relay.flow.social"]],
            content: "new",
            createdAt: 1_700_000_100
        )

        XCTAssertTrue(database.ingest(events: [older, newer]))

        let snapshot = database.followListSnapshot(pubkey: pubkey)
        XCTAssertEqual(snapshot?.content, newer.content)
        XCTAssertEqual(snapshot?.followedPubkeys, [secondFollowedPubkey])
        XCTAssertEqual(snapshot?.relayHintsByPubkey[secondFollowedPubkey]?.first?.absoluteString, "wss://relay.flow.social")
    }

    func testProfileCacheResolvesProfilesFromNostrDB() async throws {
        let rootURL = try makeRootURL(prefix: "FlowProfileCache")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = FlowNostrDBTestFileManager(rootURL: rootURL)
        let database = FlowNostrDB(fileManager: fileManager)
        let snapshotStore = ProfileSnapshotStore(fileManager: fileManager)
        let cache = ProfileCache(snapshotStore: snapshotStore, nostrDatabase: database)
        let pubkey = hex("e")

        let event = makeTestEvent(
            id: hex("f"),
            pubkey: pubkey,
            kind: 0,
            tags: [],
            content: #"{"name":"nostrdb user","display_name":"NostrDB User"}"#
        )

        XCTAssertTrue(database.ingest(events: [event]))

        let resolved = await cache.cachedProfile(pubkey: pubkey)
        XCTAssertEqual(resolved?.name, "nostrdb user")
        XCTAssertEqual(resolved?.displayName, "NostrDB User")
    }

    func testFollowListSnapshotCacheReadsFromNostrDBWhenNoPersistedSnapshotExists() async throws {
        let rootURL = try makeRootURL(prefix: "FlowFollowListCache")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = FlowNostrDBTestFileManager(rootURL: rootURL)
        let database = FlowNostrDB(fileManager: fileManager)
        let cache = FollowListSnapshotCache(fileManager: fileManager, nostrDatabase: database)
        let pubkey = hex("1")
        let followedPubkey = hex("2")

        let event = makeTestEvent(
            id: hex("3"),
            pubkey: pubkey,
            kind: 3,
            tags: [["p", followedPubkey]],
            content: "cached in nostrdb"
        )

        XCTAssertTrue(database.ingest(events: [event]))

        let snapshot = await cache.cachedSnapshot(pubkey: pubkey)
        XCTAssertEqual(snapshot?.followedPubkeys, [followedPubkey])
        XCTAssertEqual(snapshot?.content, event.content)
    }

    func testQueryEventsSupportsTagFiltersAndUntilPagination() throws {
        let rootURL = try makeRootURL(prefix: "FlowNostrDBTagQuery")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = FlowNostrDBTestFileManager(rootURL: rootURL)
        let database = FlowNostrDB(fileManager: fileManager)
        let newest = makeTestEvent(
            id: hex("4"),
            pubkey: hex("5"),
            kind: 1,
            tags: [["t", "sakura"]],
            content: "newest",
            createdAt: 1_700_000_300
        )
        let middle = makeTestEvent(
            id: hex("6"),
            pubkey: hex("7"),
            kind: 1,
            tags: [["t", "sakura"]],
            content: "middle",
            createdAt: 1_700_000_200
        )
        let otherTag = makeTestEvent(
            id: hex("8"),
            pubkey: hex("9"),
            kind: 1,
            tags: [["t", "other"]],
            content: "other",
            createdAt: 1_700_000_100
        )

        XCTAssertTrue(database.ingest(events: [newest, middle, otherTag]))

        let resolved = database.queryEvents(
            filter: NostrFilter(
                kinds: [1],
                limit: 2,
                until: newest.createdAt - 1,
                tagFilters: ["t": ["sakura"]]
            )
        )

        XCTAssertEqual(resolved?.map { $0.id.lowercased() }, [middle.id.lowercased()])
        XCTAssertEqual(resolved?.map(\.content), [middle.content])
    }

    func testDiagnosticsSnapshotReportsStoredEventAndProfileCounts() throws {
        let rootURL = try makeRootURL(prefix: "FlowNostrDBDiagnostics")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = FlowNostrDBTestFileManager(rootURL: rootURL)
        let database = FlowNostrDB(fileManager: fileManager)
        let profileEvent = makeTestEvent(
            id: hex("a"),
            pubkey: hex("b"),
            kind: 0,
            tags: [],
            content: #"{"name":"flow"}"#
        )
        let noteEvent = makeTestEvent(
            id: hex("c"),
            pubkey: hex("d"),
            kind: 1,
            tags: [["t", "flow"]],
            content: "hello"
        )

        XCTAssertTrue(database.ingest(events: [profileEvent, noteEvent]))

        let diagnostics = database.diagnosticsSnapshot()

        XCTAssertEqual(diagnostics.sessionIngestedEventCount, 2)
        XCTAssertEqual(diagnostics.sessionIngestedProfileCount, 1)
        XCTAssertGreaterThanOrEqual(diagnostics.persistedEventCount, 0)
        XCTAssertGreaterThanOrEqual(diagnostics.persistedProfileCount, 0)
        XCTAssertGreaterThanOrEqual(diagnostics.diskUsageBytes, 0)
    }

    private func makeRootURL(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTestEvent(
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

    private func hex(_ character: Character) -> String {
        String(repeating: String(character), count: 64)
    }
}

private final class FlowNostrDBTestFileManager: FileManager, @unchecked Sendable {
    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
        super.init()
    }

    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] {
        [rootURL]
    }
}
