import XCTest
@testable import Flow

final class NostrRelayClientTests: XCTestCase {
    func testFetchEventsRejectsNonWebSocketURL() async {
        let client = NostrRelayClient(session: .shared)
        let filter = NostrFilter(limit: 1)

        do {
            _ = try await client.fetchEvents(
                relayURL: URL(string: "https://example.com")!,
                filter: filter,
                timeout: 0.01
            )
            XCTFail("Expected invalid relay URL error")
        } catch let error as RelayClientError {
            guard case .invalidRelayURL(let value) = error else {
                return XCTFail("Unexpected relay client error: \(error)")
            }
            XCTAssertEqual(value, "https://example.com")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchEventsRespectsRelayCooldownBeforeOpeningSocket() async {
        let relayURL = URL(string: "wss://relay.nostr.band")!
        let backoff = RelayEndpointBackoff()
        let client = NostrRelayClient(session: .shared, endpointBackoff: backoff)
        let filter = NostrFilter(limit: 1)

        await backoff.recordFailure(for: relayURL)

        do {
            _ = try await client.fetchEvents(
                relayURL: relayURL,
                filter: filter,
                timeout: 0.01
            )
            XCTFail("Expected cooldown error")
        } catch let error as RelayClientError {
            guard case .coolingDown(let value) = error else {
                return XCTFail("Unexpected relay client error: \(error)")
            }
            XCTAssertEqual(value, relayURL.absoluteString)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPublishEventToSourcesPublishesConcurrently() async {
        let firstSource = URL(string: "wss://source-one.example.com")!
        let secondSource = URL(string: "wss://source-two.example.com")!
        let publisher = StubRelayPublisher(
            delays: [
                firstSource: 200_000_000,
                secondSource: 200_000_000
            ]
        )

        let startedAt = Date()
        let outcome = await publisher.publishEvent(
            to: [firstSource, secondSource],
            eventData: Data("{}".utf8),
            eventID: "event-id"
        )
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertEqual(outcome.successfulSourceCount, 2)
        XCTAssertNil(outcome.firstFailureMessage)
        XCTAssertLessThan(elapsed, 0.35)
    }

    func testPublishEventToSourcesCapturesFailuresWithoutBlockingSuccesses() async {
        let firstSource = URL(string: "wss://source-one.example.com")!
        let secondSource = URL(string: "wss://source-two.example.com")!
        let publisher = StubRelayPublisher(
            delays: [
                secondSource: 120_000_000
            ],
            failureMessages: [
                firstSource: "Source publish timed out."
            ]
        )

        let outcome = await publisher.publishEvent(
            to: [firstSource, secondSource],
            eventData: Data("{}".utf8),
            eventID: "event-id"
        )

        XCTAssertEqual(outcome.successfulSourceCount, 1)
        XCTAssertEqual(outcome.firstFailureMessage, "Source publish timed out.")
    }
}

private actor StubRelayPublisher: NostrRelayEventPublishing {
    let delays: [URL: UInt64]
    let failureMessages: [URL: String]

    init(
        delays: [URL: UInt64] = [:],
        failureMessages: [URL: String] = [:]
    ) {
        self.delays = delays
        self.failureMessages = failureMessages
    }

    func publishEvent(
        relayURL: URL,
        eventData: Data,
        eventID: String,
        timeout: TimeInterval
    ) async throws {
        if let delay = delays[relayURL] {
            try await Task.sleep(nanoseconds: delay)
        }

        if let failureMessage = failureMessages[relayURL] {
            throw SourcePublishTransportError(message: failureMessage)
        }
    }
}
