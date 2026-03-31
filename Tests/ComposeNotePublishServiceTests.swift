import XCTest
import NostrSDK
@testable import Flow

final class ComposeNotePublishServiceTests: XCTestCase {
    func testPublishNoteAddsClientTag() async throws {
        let relayClient = RecordingRelayPublisher()
        let service = ComposeNotePublishService(relayClient: relayClient)
        let nsec = try makeTestNsec()

        let publishedCount = try await service.publishNote(
            content: "Hello Flow",
            currentNsec: nsec,
            writeRelayURLs: [URL(string: "wss://relay-one.example.com")!]
        )

        XCTAssertEqual(publishedCount, 1)

        let capture = await relayClient.capture()
        let eventData = try XCTUnwrap(capture.eventData)
        let event = try JSONDecoder().decode(Flow.NostrEvent.self, from: eventData)

        XCTAssertEqual(firstTag(named: "client", in: event), ["client", "Flow"])
        XCTAssertEqual(event.clientName, "Flow")
    }

    func testPublishPollEncodesOptionsPollTypeAndRelayTags() async throws {
        let relayClient = RecordingRelayPublisher()
        let service = ComposeNotePublishService(relayClient: relayClient)
        let nsec = try makeTestNsec()
        let relayURLs = [
            URL(string: "wss://relay-one.example.com")!,
            URL(string: "wss://relay-two.example.com")!,
            URL(string: "wss://relay-one.example.com")!,
            URL(string: "wss://relay-three.example.com")!,
            URL(string: "wss://relay-four.example.com")!,
            URL(string: "wss://relay-five.example.com")!
        ]
        let endsAt = Date(timeIntervalSince1970: 1_710_000_123)
        let poll = ComposePollDraft(
            allowsMultipleChoice: true,
            options: [
                ComposePollOption(id: "tea", text: " Tea "),
                ComposePollOption(id: "coffee", text: "Coffee"),
                ComposePollOption(id: "blank", text: " ")
            ],
            endsAt: endsAt
        )

        let publishedCount = try await service.publishPoll(
            content: " Favorite drink? ",
            poll: poll,
            currentNsec: nsec,
            writeRelayURLs: relayURLs
        )

        XCTAssertEqual(publishedCount, 1)

        let capture = await relayClient.capture()
        let eventData = try XCTUnwrap(capture.eventData)
        let eventID = try XCTUnwrap(capture.eventID)
        let event = try JSONDecoder().decode(Flow.NostrEvent.self, from: eventData)

        XCTAssertEqual(eventID, event.id)
        XCTAssertEqual(event.kind, NostrPollKind.poll)
        XCTAssertEqual(event.content, "Favorite drink?")
        XCTAssertFalse(capture.relayURLs.isEmpty)
        XCTAssertTrue(capture.relayURLs.count <= 5)
        XCTAssertTrue(
            Set(capture.relayURLs.map { $0.absoluteString.lowercased() }).isSubset(of: Set([
                "wss://relay-one.example.com",
                "wss://relay-two.example.com",
                "wss://relay-three.example.com",
                "wss://relay-four.example.com",
                "wss://relay-five.example.com"
            ]))
        )
        XCTAssertEqual(tags(named: "option", in: event), [
            ["option", "tea", "Tea"],
            ["option", "coffee", "Coffee"]
        ])
        XCTAssertEqual(firstTag(named: "polltype", in: event)?[1], NostrPollType.multipleChoice.rawValue)
        XCTAssertEqual(
            firstTag(named: "endsAt", in: event)?[1],
            String(Int(ComposePollDraft.roundToMinute(endsAt).timeIntervalSince1970))
        )
        XCTAssertEqual(tags(named: "relay", in: event).compactMap { $0.count > 1 ? $0[1] : nil }, [
            "wss://relay-one.example.com",
            "wss://relay-two.example.com",
            "wss://relay-three.example.com",
            "wss://relay-four.example.com"
        ])
        XCTAssertEqual(firstTag(named: "client", in: event), ["client", "Flow"])
    }

    func testPublishPollRejectsDraftWithoutTwoOptions() async throws {
        let relayClient = RecordingRelayPublisher()
        let service = ComposeNotePublishService(relayClient: relayClient)
        let nsec = try makeTestNsec()
        let poll = ComposePollDraft(
            options: [ComposePollOption(id: "tea", text: "Tea")]
        )

        do {
            _ = try await service.publishPoll(
                content: "Favorite drink?",
                poll: poll,
                currentNsec: nsec,
                writeRelayURLs: [URL(string: "wss://relay-one.example.com")!]
            )
            XCTFail("Expected publishPoll to reject invalid poll drafts.")
        } catch let error as ComposeNotePublishError {
            guard case .invalidPoll = error else {
                return XCTFail("Expected invalidPoll error, got \(error).")
            }
        }

        let capture = await relayClient.capture()
        XCTAssertTrue(capture.relayURLs.isEmpty)
        XCTAssertNil(capture.eventData)
        XCTAssertNil(capture.eventID)
    }
}

private actor RecordingRelayPublisher: NostrRelayEventPublishing {
    private var relayURLs: [URL] = []
    private var eventData: Data?
    private var eventID: String?

    func publishEvent(
        relayURL: URL,
        eventData: Data,
        eventID: String,
        timeout: TimeInterval
    ) async throws {
        relayURLs.append(relayURL)
        self.eventData = eventData
        self.eventID = eventID
    }

    func capture() -> RelayPublishCapture {
        RelayPublishCapture(
            relayURLs: relayURLs,
            eventData: eventData,
            eventID: eventID
        )
    }
}

private struct RelayPublishCapture: Sendable {
    let relayURLs: [URL]
    let eventData: Data?
    let eventID: String?
}

private func makeTestNsec() throws -> String {
    guard let keypair = Keypair() else {
        throw TestFailure.failedToCreateKeypair
    }
    return keypair.privateKey.nsec
}

private func tags(named name: String, in event: Flow.NostrEvent) -> [[String]] {
    event.tags.filter { tag in
        tag.first?.lowercased() == name.lowercased()
    }
}

private func firstTag(named name: String, in event: Flow.NostrEvent) -> [String]? {
    tags(named: name, in: event).first
}

private enum TestFailure: Error {
    case failedToCreateKeypair
}
