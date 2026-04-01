import XCTest
import NostrSDK
@testable import Flow

final class NoteReportPublishServiceTests: XCTestCase {
    func testPublishReportEncodesNIP56TagsAndClientTag() async throws {
        let relayClient = RecordingReportRelayPublisher()
        let service = NoteReportPublishService(relayClient: relayClient)
        let nsec = try makeTestReportNsec()
        let target = Flow.NostrEvent(
            id: String(repeating: "a", count: 64),
            pubkey: String(repeating: "b", count: 64),
            createdAt: 1_700_000_000,
            kind: 1,
            tags: [],
            content: "hello",
            sig: String(repeating: "c", count: 128)
        )

        try await service.publishReport(
            for: target,
            type: .spam,
            details: "looks automated",
            currentNsec: nsec,
            writeRelayURLs: [URL(string: "wss://relay-one.example.com")!]
        )

        let capture = await relayClient.capture()
        let eventData = try XCTUnwrap(capture.eventData)
        let event = try JSONDecoder().decode(Flow.NostrEvent.self, from: eventData)

        XCTAssertEqual(event.kind, 1984)
        XCTAssertEqual(event.content, "looks automated")
        XCTAssertEqual(firstTag(named: "p", in: event), ["p", target.pubkey, "spam"])
        XCTAssertEqual(firstTag(named: "e", in: event), ["e", target.id, "spam"])
        XCTAssertEqual(firstTag(named: "client", in: event), ["client", "Flow"])
    }

    func testPublishReportRequiresPrivateKey() async throws {
        let relayClient = RecordingReportRelayPublisher()
        let service = NoteReportPublishService(relayClient: relayClient)
        let target = Flow.NostrEvent(
            id: String(repeating: "a", count: 64),
            pubkey: String(repeating: "b", count: 64),
            createdAt: 1_700_000_000,
            kind: 1,
            tags: [],
            content: "hello",
            sig: String(repeating: "c", count: 128)
        )

        do {
            try await service.publishReport(
                for: target,
                type: .other,
                details: "",
                currentNsec: nil,
                writeRelayURLs: [URL(string: "wss://relay-one.example.com")!]
            )
            XCTFail("Expected missingPrivateKey error.")
        } catch let error as NoteReportPublishError {
            guard case .missingPrivateKey = error else {
                return XCTFail("Expected missingPrivateKey, got \(error).")
            }
        }
    }
}

private actor RecordingReportRelayPublisher: NostrRelayEventPublishing {
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

    func capture() -> ReportRelayPublishCapture {
        ReportRelayPublishCapture(
            relayURLs: relayURLs,
            eventData: eventData,
            eventID: eventID
        )
    }
}

private struct ReportRelayPublishCapture: Sendable {
    let relayURLs: [URL]
    let eventData: Data?
    let eventID: String?
}

private func makeTestReportNsec() throws -> String {
    guard let keypair = Keypair() else {
        throw ReportTestFailure.failedToCreateKeypair
    }
    return keypair.privateKey.nsec
}

private func reportTags(named name: String, in event: Flow.NostrEvent) -> [[String]] {
    event.tags.filter { tag in
        tag.first?.lowercased() == name.lowercased()
    }
}

private func firstTag(named name: String, in event: Flow.NostrEvent) -> [String]? {
    reportTags(named: name, in: event).first
}

private enum ReportTestFailure: Error {
    case failedToCreateKeypair
}
