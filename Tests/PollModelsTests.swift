import XCTest
@testable import Flow

final class PollModelsTests: XCTestCase {
    func testMetadataParsesStandardPollTags() throws {
        let event = makeEvent(
            id: hex("1"),
            pubkey: hex("a"),
            kind: NostrPollKind.poll,
            tags: [
                ["option", "tea", "Tea"],
                ["option", "coffee", "Coffee"],
                ["option_image", "coffee", "https://cdn.example.com/coffee.png"],
                ["relay", "wss://relay-one.example.com"],
                ["relay", "wss://relay-one.example.com"],
                ["relay", "https://not-a-relay.example.com"],
                ["polltype", "multiplechoice"],
                ["endsAt", "1710000123"]
            ],
            content: "Favorite drink?"
        )

        let metadata = try XCTUnwrap(NostrPollMetadata(event: event))

        XCTAssertEqual(metadata.format, .nip88)
        XCTAssertEqual(metadata.pollType, .multipleChoice)
        XCTAssertEqual(metadata.endsAt, 1_710_000_123)
        XCTAssertEqual(metadata.relayURLs.map(\.absoluteString), ["wss://relay-one.example.com"])
        XCTAssertEqual(metadata.options.map(\.id), ["tea", "coffee"])
        XCTAssertEqual(metadata.options.map(\.label), ["Tea", "Coffee"])
        XCTAssertNil(metadata.options[0].imageURL)
        XCTAssertEqual(
            metadata.options[1].imageURL?.absoluteString,
            "https://cdn.example.com/coffee.png"
        )
    }

    func testResultsKeepNewestResponsePerVoter() throws {
        let pollEvent = makeEvent(
            id: hex("2"),
            pubkey: hex("b"),
            kind: NostrPollKind.poll,
            tags: [
                ["option", "tea", "Tea"],
                ["option", "coffee", "Coffee"]
            ],
            content: "Favorite drink?"
        )
        let metadata = try XCTUnwrap(NostrPollMetadata(event: pollEvent))

        let responses = [
            makeEvent(
                id: hex("3"),
                pubkey: hex("c"),
                kind: NostrPollKind.response,
                tags: [["response", "tea"]],
                content: "",
                createdAt: 100
            ),
            makeEvent(
                id: hex("4"),
                pubkey: hex("c"),
                kind: NostrPollKind.response,
                tags: [["response", "coffee"]],
                content: "",
                createdAt: 200
            ),
            makeEvent(
                id: hex("5"),
                pubkey: hex("d"),
                kind: NostrPollKind.response,
                tags: [["response", "tea"]],
                content: "",
                createdAt: 150
            ),
            makeEvent(
                id: hex("6"),
                pubkey: hex("e"),
                kind: NostrPollKind.response,
                tags: [["response", "tea"], ["response", "coffee"]],
                content: "",
                createdAt: 160
            )
        ].compactMap {
            NostrPollResponse(
                event: $0,
                validOptionIDs: metadata.validOptionIDs,
                allowsMultipleChoices: metadata.pollType.allowsMultipleChoices
            )
        }

        let results = NostrPollResults.build(for: metadata, responses: responses)

        XCTAssertEqual(results.totalVotes, 2)
        XCTAssertEqual(results.voters, Set([hex("c"), hex("d")]))
        XCTAssertEqual(results.optionVoters["tea"], Set([hex("d")]))
        XCTAssertEqual(results.optionVoters["coffee"], Set([hex("c")]))
    }

    func testPollPlacementInsertsTextOnlyPollOnceAfterTrailingInlineContent() {
        let placements = NoteContentPollPlacement.insertionOffsets(
            partCount: 1,
            insertionIndex: 1,
            includesPoll: true
        )

        XCTAssertEqual(placements, [1])
    }

    func testPollPlacementInsertsPollAtStartWhenNoRenderablePartsExist() {
        let placements = NoteContentPollPlacement.insertionOffsets(
            partCount: 0,
            insertionIndex: 0,
            includesPoll: true
        )

        XCTAssertEqual(placements, [0])
    }
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
