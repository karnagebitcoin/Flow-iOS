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

        XCTAssertTrue(diagnostics.isOpen)
        XCTAssertTrue(diagnostics.databaseDirectoryExists)
        XCTAssertFalse(diagnostics.databasePath.isEmpty)
        XCTAssertNil(diagnostics.lastOpenError)
        XCTAssertEqual(diagnostics.sessionIngestedEventCount, 2)
        XCTAssertEqual(diagnostics.sessionIngestedProfileCount, 1)
        XCTAssertEqual(diagnostics.ingestCallCount, 1)
        XCTAssertEqual(diagnostics.successfulIngestCallCount, 1)
        XCTAssertGreaterThanOrEqual(diagnostics.persistedEventCount, 0)
        XCTAssertGreaterThanOrEqual(diagnostics.persistedProfileCount, 0)
        XCTAssertGreaterThanOrEqual(diagnostics.diskUsageBytes, 0)
    }

    func testDiagnosticsSnapshotTracksLocalReadUsage() throws {
        let rootURL = try makeRootURL(prefix: "FlowNostrDBUsage")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = FlowNostrDBTestFileManager(rootURL: rootURL)
        let database = FlowNostrDB(fileManager: fileManager)
        let profileEvent = makeTestEvent(
            id: hex("1"),
            pubkey: hex("2"),
            kind: 0,
            tags: [],
            content: #"{"name":"reader"}"#
        )
        let followListEvent = makeTestEvent(
            id: hex("3"),
            pubkey: hex("4"),
            kind: 3,
            tags: [["p", hex("5")]],
            content: "follows"
        )
        let noteEvent = makeTestEvent(
            id: hex("6"),
            pubkey: hex("7"),
            kind: 1,
            tags: [["t", "flow"]],
            content: "local note"
        )

        XCTAssertTrue(database.ingest(events: [profileEvent, followListEvent, noteEvent]))

        XCTAssertNotNil(database.events(ids: [noteEvent.id]))
        XCTAssertNotNil(database.profile(pubkey: profileEvent.pubkey))
        XCTAssertNotNil(database.followListSnapshot(pubkey: followListEvent.pubkey))
        XCTAssertNotNil(database.queryEvents(filter: NostrFilter(kinds: [1], limit: 10)))

        let diagnostics = database.diagnosticsSnapshot()

        XCTAssertEqual(diagnostics.eventLookupCount, 1)
        XCTAssertEqual(diagnostics.profileLookupCount, 1)
        XCTAssertEqual(diagnostics.followListLookupCount, 1)
        XCTAssertEqual(diagnostics.queryCount, 1)
    }

    func testOpenFallsBackToSmallerMapsizeWhenLargerAttemptFails() throws {
        let rootURL = try makeRootURL(prefix: "FlowNostrDBMapsizeFallback")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = FlowNostrDBTestFileManager(rootURL: rootURL)
        let attempts = FlowNostrDBAttemptLog()
        let fallbackThreshold = size_t(2) * 1024 * 1024 * 1024
        let database = FlowNostrDB(
            fileManager: fileManager,
            initialMapsize: size_t(8) * 1024 * 1024 * 1024,
            minimumMapsize: size_t(1) * 1024 * 1024 * 1024,
            openDatabase: { path, ingestThreads, mapsize, writerScratchBufferSize, flags in
                attempts.values.append(mapsize)
                guard mapsize <= fallbackThreshold else {
                    return nil
                }

                return path.withCString { rawPath in
                    flow_ndb_open(
                        rawPath,
                        ingestThreads,
                        mapsize,
                        writerScratchBufferSize,
                        flags
                    )
                }
            }
        )

        let diagnostics = database.diagnosticsSnapshot()

        XCTAssertTrue(diagnostics.isOpen)
        XCTAssertEqual(attempts.values, [
            size_t(8) * 1024 * 1024 * 1024,
            size_t(4) * 1024 * 1024 * 1024,
            size_t(2) * 1024 * 1024 * 1024,
        ])
        XCTAssertEqual(diagnostics.openMapsizeBytes, Int64(fallbackThreshold))
        XCTAssertEqual(diagnostics.lastAttemptedMapsizeBytes, Int64(fallbackThreshold))
        XCTAssertNil(diagnostics.lastOpenError)
    }

    func testRequiresRebuildWhenDiskUsageCrossesThreshold() throws {
        let rootURL = try makeRootURL(prefix: "FlowNostrDBRetentionThreshold")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = FlowNostrDBTestFileManager(rootURL: rootURL)
        let database = FlowNostrDB(
            fileManager: fileManager,
            maxMapUsageBeforeRebuild: 0.00000001
        )

        let oldest = makeTestEvent(
            id: hex("1"),
            pubkey: hex("a"),
            kind: 1,
            tags: [],
            content: "oldest",
            createdAt: 1_700_000_000
        )
        let middle = makeTestEvent(
            id: hex("2"),
            pubkey: hex("b"),
            kind: 1,
            tags: [],
            content: "middle",
            createdAt: 1_700_000_100
        )
        let newest = makeTestEvent(
            id: hex("3"),
            pubkey: hex("c"),
            kind: 1,
            tags: [],
            content: "newest",
            createdAt: 1_700_000_200
        )

        XCTAssertTrue(database.ingest(events: [oldest, middle, newest]))
        XCTAssertTrue(database.requiresRebuild())
    }

    func testRebuildRetainsNewestSeedEvents() throws {
        let rootURL = try makeRootURL(prefix: "FlowNostrDBRebuild")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = FlowNostrDBTestFileManager(rootURL: rootURL)
        let database = FlowNostrDB(fileManager: fileManager)

        let oldest = makeTestEvent(
            id: hex("4"),
            pubkey: hex("d"),
            kind: 1,
            tags: [],
            content: "oldest",
            createdAt: 1_700_000_000
        )
        let middle = makeTestEvent(
            id: hex("5"),
            pubkey: hex("e"),
            kind: 1,
            tags: [],
            content: "middle",
            createdAt: 1_700_000_100
        )
        let newest = makeTestEvent(
            id: hex("6"),
            pubkey: hex("f"),
            kind: 1,
            tags: [],
            content: "newest",
            createdAt: 1_700_000_200
        )

        XCTAssertTrue(database.ingest(events: [oldest, middle, newest]))
        XCTAssertTrue(database.rebuild(retaining: [middle, newest]))
        let retained = database.queryEvents(filter: NostrFilter(kinds: [1], limit: 10))
        XCTAssertEqual(retained?.map { $0.id.lowercased() }, [
            newest.id.lowercased(),
            middle.id.lowercased(),
        ])
        XCTAssertNil(database.events(ids: [oldest.id])?[oldest.id.lowercased()])
    }

    func testSeenEventStoreRebuildsFlowDBFromRecentMirrorWhenDiskUsageThresholdExceeded() async throws {
        let rootURL = try makeRootURL(prefix: "FlowSeenEventStoreRebuild")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileManager = FlowNostrDBTestFileManager(rootURL: rootURL)
        let database = FlowNostrDB(
            fileManager: fileManager,
            maxMapUsageBeforeRebuild: 0.00000001
        )
        let store = SeenEventStore(
            fileManager: fileManager,
            nostrDatabase: database,
            maxRetainedNostrDBEventCount: 2
        )

        let oldest = makeTestEvent(
            id: hex("7"),
            pubkey: hex("1"),
            kind: 1,
            tags: [],
            content: "oldest",
            createdAt: 1_700_000_000
        )
        let middle = makeTestEvent(
            id: hex("8"),
            pubkey: hex("2"),
            kind: 1,
            tags: [],
            content: "middle",
            createdAt: 1_700_000_100
        )
        let newest = makeTestEvent(
            id: hex("9"),
            pubkey: hex("3"),
            kind: 1,
            tags: [],
            content: "newest",
            createdAt: 1_700_000_200
        )

        await store.store(events: [oldest])
        await store.store(events: [middle])
        await store.store(events: [newest])

        let retained = database.queryEvents(filter: NostrFilter(kinds: [1], limit: 10))
        XCTAssertEqual(retained?.map { $0.id.lowercased() }, [
            newest.id.lowercased(),
            middle.id.lowercased(),
        ])
        XCTAssertNil(database.events(ids: [oldest.id])?[oldest.id.lowercased()])
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

private final class FlowNostrDBAttemptLog: @unchecked Sendable {
    var values: [size_t] = []
}
