import XCTest
@testable import Flow

final class MuteFilterSnapshotTests: XCTestCase {
    func testEncodedSpamHeuristicHidesBase64LookingContentWithoutMutedWords() {
        let snapshot = MuteFilterSnapshot(
            mutedPubkeys: [],
            exactMutedWords: [],
            phraseMutedWords: []
        )
        let encodedPayload = String(
            repeating: "VGhlYm9hcmRab25lX3ByZXNlbmNlQWxwaGExMjM0NTY3ODkwKysvPQ==",
            count: 10
        )

        XCTAssertTrue(snapshot.shouldHide(makeMuteFilterEvent(content: encodedPayload)))
    }

    func testEncodedSpamHeuristicAllowsLongNaturalLanguageContent() {
        let snapshot = MuteFilterSnapshot(
            mutedPubkeys: [],
            exactMutedWords: [],
            phraseMutedWords: []
        )
        let naturalPost = String(
            repeating: "This is a normal long note with punctuation, spaces, and enough human-readable structure to avoid encoded spam filtering. ",
            count: 8
        )

        XCTAssertFalse(snapshot.shouldHide(makeMuteFilterEvent(content: naturalPost)))
    }

    func testMutedWordWithUnderscoreMatchesAsSingleToken() {
        let snapshot = MuteFilterSnapshot(
            mutedPubkeys: [],
            exactMutedWords: ["zone_presence"],
            phraseMutedWords: []
        )

        XCTAssertTrue(snapshot.shouldHide(makeMuteFilterEvent(content: "bot marker zone_presence detected")))
        XCTAssertFalse(snapshot.shouldHide(makeMuteFilterEvent(content: "zone presence should not match without underscore")))
    }

    @MainActor
    func testDefaultMutedKeywordListsExcludeBitcoinAndIncludeEditableAISpamList() {
        let suiteName = "MuteFilterSnapshotTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = MuteStore(defaults: defaults)
        let titles = store.mutedKeywordLists.map(\.title)

        XCTAssertFalse(titles.contains("Bitcoin"))

        let aiList = store.mutedKeywordLists.first { $0.id == "ai-bots-spam" }
        XCTAssertEqual(aiList?.title, "AI, Bots & Spam")
        XCTAssertEqual(aiList?.words, ["theboard", "zone_presence"])
        XCTAssertEqual(aiList?.allowsAddingWords, true)
    }
}

private func makeMuteFilterEvent(content: String) -> NostrEvent {
    NostrEvent(
        id: String(repeating: "a", count: 64),
        pubkey: String(repeating: "b", count: 64),
        createdAt: 1_700_000_000,
        kind: 1,
        tags: [],
        content: content,
        sig: String(repeating: "c", count: 128)
    )
}
