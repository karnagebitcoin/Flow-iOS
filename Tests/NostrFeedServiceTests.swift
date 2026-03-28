import XCTest
@testable import Flow

final class NostrFeedServiceTests: XCTestCase {
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

private func hex(_ character: Character) -> String {
    String(repeating: String(character), count: 64)
}
