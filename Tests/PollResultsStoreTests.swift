import Combine
import XCTest
@testable import Flow

final class PollResultsStoreTests: XCTestCase {
    func testLoadResultsIfNeededRefreshesWhenCachedResultsAreStale() async throws {
        let pollEvent = makePollResultsEvent(
            id: String(repeating: "a", count: 64),
            pubkey: String(repeating: "b", count: 64),
            kind: NostrPollKind.poll,
            tags: [
                ["option", "tea", "Tea"],
                ["option", "coffee", "Coffee"]
            ],
            content: "Favorite drink?"
        )
        let poll = try XCTUnwrap(NostrPollMetadata(event: pollEvent))

        let voteEvent = makePollResultsEvent(
            id: String(repeating: "c", count: 64),
            pubkey: String(repeating: "d", count: 64),
            kind: NostrPollKind.response,
            tags: [
                ["e", pollEvent.id],
                ["response", "tea"]
            ],
            content: "",
            createdAt: 1_710_000_100
        )

        let relayClient = PollResultsSpyRelayClient(
            responsesByFetch: [
                [],
                [voteEvent]
            ]
        )
        let store = await MainActor.run {
            PollResultsStore(
                relayClient: relayClient,
                automaticRefreshInterval: 0
            )
        }
        let relayURL = try XCTUnwrap(URL(string: "wss://relay.example.com"))

        await store.loadResultsIfNeeded(for: pollEvent, poll: poll, relayURLs: [relayURL])
        let initialResults = await MainActor.run { store.results(for: pollEvent.id) }
        XCTAssertEqual(initialResults?.totalVotes, 0)

        await store.loadResultsIfNeeded(for: pollEvent, poll: poll, relayURLs: [relayURL])
        let refreshedResults = await MainActor.run { store.results(for: pollEvent.id) }
        XCTAssertEqual(refreshedResults?.totalVotes, 1)
        XCTAssertEqual(refreshedResults?.voteCount(for: "tea"), 1)
        let fetchCount = await relayClient.fetchCount()
        XCTAssertEqual(fetchCount, 2)
    }

    func testRefreshResultsQueriesOriginalAndLowercasedPollIDs() async throws {
        let mixedCasePollID = String(repeating: "Ab", count: 32)
        let pollEvent = makePollResultsEvent(
            id: mixedCasePollID,
            pubkey: String(repeating: "b", count: 64),
            kind: NostrPollKind.poll,
            tags: [
                ["option", "tea", "Tea"]
            ],
            content: "Favorite drink?"
        )
        let poll = try XCTUnwrap(NostrPollMetadata(event: pollEvent))

        let relayClient = PollResultsSpyRelayClient(responsesByFetch: [[]])
        let store = await MainActor.run {
            PollResultsStore(relayClient: relayClient)
        }
        let relayURL = try XCTUnwrap(URL(string: "wss://relay.example.com"))

        _ = try await store.refreshResults(for: pollEvent, poll: poll, relayURLs: [relayURL])

        let recordedFilters = await relayClient.recordedFilters()
        let eventFilters = try XCTUnwrap(recordedFilters.first?.tagFilters?["e"])
        XCTAssertEqual(eventFilters, [mixedCasePollID, mixedCasePollID.lowercased()])
    }

    @MainActor
    func testPublisherEmitsUpdatedResultsForMatchingPoll() async throws {
        let pollEvent = makePollResultsEvent(
            id: String(repeating: "a", count: 64),
            pubkey: String(repeating: "b", count: 64),
            kind: NostrPollKind.poll,
            tags: [
                ["option", "tea", "Tea"],
                ["option", "coffee", "Coffee"]
            ],
            content: "Favorite drink?"
        )
        let poll = try XCTUnwrap(NostrPollMetadata(event: pollEvent))

        let voteEvent = makePollResultsEvent(
            id: String(repeating: "c", count: 64),
            pubkey: String(repeating: "d", count: 64),
            kind: NostrPollKind.response,
            tags: [
                ["e", pollEvent.id],
                ["response", "tea"]
            ],
            content: "",
            createdAt: 1_710_000_100
        )

        let relayClient = PollResultsSpyRelayClient(responsesByFetch: [[voteEvent]])
        let store = PollResultsStore(relayClient: relayClient)
        let relayURL = try XCTUnwrap(URL(string: "wss://relay.example.com"))
        let updated = expectation(description: "matching poll publisher receives refreshed results")

        let cancellable = store.publisher(for: pollEvent.id)
            .dropFirst()
            .filter { snapshot in
                snapshot.results?.totalVotes == 1
            }
            .first()
            .sink { _ in
                updated.fulfill()
            }
        defer { cancellable.cancel() }

        _ = try await store.refreshResults(for: pollEvent, poll: poll, relayURLs: [relayURL])
        await fulfillment(of: [updated], timeout: 1.0)
    }

    @MainActor
    func testPublisherDoesNotEmitForDifferentPollRefresh() async throws {
        let firstPollEvent = makePollResultsEvent(
            id: String(repeating: "a", count: 64),
            pubkey: String(repeating: "b", count: 64),
            kind: NostrPollKind.poll,
            tags: [
                ["option", "tea", "Tea"]
            ],
            content: "First poll"
        )
        let secondPollEvent = makePollResultsEvent(
            id: String(repeating: "c", count: 64),
            pubkey: String(repeating: "d", count: 64),
            kind: NostrPollKind.poll,
            tags: [
                ["option", "coffee", "Coffee"]
            ],
            content: "Second poll"
        )
        let secondPoll = try XCTUnwrap(NostrPollMetadata(event: secondPollEvent))

        let secondPollVoteEvent = makePollResultsEvent(
            id: String(repeating: "e", count: 64),
            pubkey: String(repeating: "f", count: 64),
            kind: NostrPollKind.response,
            tags: [
                ["e", secondPollEvent.id],
                ["response", "coffee"]
            ],
            content: "",
            createdAt: 1_710_000_200
        )

        let relayClient = PollResultsSpyRelayClient(responsesByFetch: [[secondPollVoteEvent]])
        let store = PollResultsStore(relayClient: relayClient)
        let relayURL = try XCTUnwrap(URL(string: "wss://relay.example.com"))
        let unrelatedEmission = expectation(description: "unrelated poll publisher should stay quiet")
        unrelatedEmission.isInverted = true

        let cancellable = store.publisher(for: firstPollEvent.id)
            .dropFirst()
            .sink { _ in
                unrelatedEmission.fulfill()
            }
        defer { cancellable.cancel() }

        _ = try await store.refreshResults(for: secondPollEvent, poll: secondPoll, relayURLs: [relayURL])
        await fulfillment(of: [unrelatedEmission], timeout: 0.3)
    }
}

private actor PollResultsSpyRelayClient: NostrRelayEventFetching {
    private var responsesByFetch: [[NostrEvent]]
    private var filters: [NostrFilter] = []

    init(responsesByFetch: [[NostrEvent]]) {
        self.responsesByFetch = responsesByFetch
    }

    func fetchEvents(
        relayURL: URL,
        filter: NostrFilter,
        timeout: TimeInterval
    ) async throws -> [NostrEvent] {
        filters.append(filter)

        if responsesByFetch.isEmpty {
            return []
        }

        return responsesByFetch.removeFirst()
    }

    func fetchCount() -> Int {
        filters.count
    }

    func recordedFilters() -> [NostrFilter] {
        filters
    }
}

private func makePollResultsEvent(
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
