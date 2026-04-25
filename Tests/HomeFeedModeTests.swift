import XCTest
@testable import Flow

final class HomeFeedModeTests: XCTestCase {
    func testHomeFeedModesExcludeArticles() {
        XCTAssertEqual(HomeFeedMode.allCases, [.posts, .postsAndReplies])
    }

    func testReplyModeShowsOnlyReplies() {
        let author = hex("a")
        let note = FeedItem(
            event: makeEvent(id: hex("1"), pubkey: author, kind: FeedKindFilters.shortTextNote, tags: []),
            profile: nil
        )
        let reply = FeedItem(
            event: makeEvent(
                id: hex("2"),
                pubkey: author,
                kind: FeedKindFilters.shortTextNote,
                tags: [["e", hex("3"), "", "reply"]]
            ),
            profile: nil
        )

        XCTAssertTrue(HomeFeedMode.posts.includes(note))
        XCTAssertFalse(HomeFeedMode.posts.includes(reply))
        XCTAssertFalse(HomeFeedMode.postsAndReplies.includes(note))
        XCTAssertTrue(HomeFeedMode.postsAndReplies.includes(reply))
    }

    func testFollowingPageSliceKeepsEnoughRawItemsForSelectedMode() {
        let author = hex("a")
        let items = [
            FeedItem(event: makeEvent(id: hex("1"), pubkey: author, kind: FeedKindFilters.shortTextNote, tags: []), profile: nil),
            FeedItem(event: makeEvent(id: hex("2"), pubkey: author, kind: FeedKindFilters.shortTextNote, tags: [["e", hex("9"), "", "reply"]]), profile: nil),
            FeedItem(event: makeEvent(id: hex("3"), pubkey: author, kind: FeedKindFilters.shortTextNote, tags: []), profile: nil),
            FeedItem(event: makeEvent(id: hex("4"), pubkey: author, kind: FeedKindFilters.shortTextNote, tags: [["e", hex("8"), "", "reply"]]), profile: nil)
        ]

        let notesSlice = HomeFeedViewModel.prefixForVisibleModeLimitForTesting(
            items,
            mode: .posts,
            visibleLimit: 2
        )
        let repliesSlice = HomeFeedViewModel.prefixForVisibleModeLimitForTesting(
            items,
            mode: .postsAndReplies,
            visibleLimit: 2
        )

        XCTAssertEqual(notesSlice.map(\.id), [hex("1"), hex("2"), hex("3")])
        XCTAssertEqual(repliesSlice.map(\.id), [hex("1"), hex("2"), hex("3"), hex("4")])
    }
}

private func hex(_ character: Character) -> String {
    String(repeating: String(character), count: 64)
}

private func makeEvent(id: String, pubkey: String, kind: Int, tags: [[String]]) -> NostrEvent {
    NostrEvent(
        id: id,
        pubkey: pubkey,
        createdAt: 1_700_000_000,
        kind: kind,
        tags: tags,
        content: "hello",
        sig: String(repeating: "f", count: 128)
    )
}
