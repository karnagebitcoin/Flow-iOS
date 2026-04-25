import XCTest
@testable import Flow

@MainActor
final class FeedVisibilityTests: XCTestCase {
    func testFollowingAuthorPubkeysIncludeCurrentUserLikeX21() {
        let currentUserPubkey = hex("a")
        let followings = [hex("b"), currentUserPubkey.uppercased(), hex("c"), hex("b")]

        let authors = HomeFeedViewModel.followingAuthorPubkeys(
            followingPubkeys: followings,
            currentUserPubkey: currentUserPubkey
        )

        XCTAssertEqual(authors, [currentUserPubkey, hex("b"), hex("c")])
    }

    func testProfileFeedRequestedKindsIncludeStandardPollsAndHideZapPolls() {
        XCTAssertTrue(ProfileViewModel.requestedFeedKinds.contains(FeedKindFilters.poll))
        XCTAssertTrue(ProfileViewModel.requestedFeedKinds.contains(FeedKindFilters.longFormArticle))
        XCTAssertFalse(ProfileViewModel.requestedFeedKinds.contains(FeedKindFilters.legacyZapPoll))
        XCTAssertEqual(FeedKindFilters.pollKinds, [FeedKindFilters.poll])
        XCTAssertFalse(FeedKindFilters.supportedKinds.contains(FeedKindFilters.legacyZapPoll))
        XCTAssertFalse(FeedKindFilters.normalizedKinds([FeedKindFilters.poll, FeedKindFilters.legacyZapPoll]).contains(FeedKindFilters.legacyZapPoll))
    }

    func testProfileFeedModesIncludeArticlesAfterReplies() {
        XCTAssertEqual(FeedMode.allCases, [.posts, .postsAndReplies, .articles])
        XCTAssertEqual(FeedMode.articles.title, "Articles")
    }

    func testProfileArticleModeShowsOnlyDirectLongFormArticles() {
        let author = hex("a")
        let note = makeEvent(id: hex("1"), pubkey: author, kind: FeedKindFilters.shortTextNote, tags: [])
        let reply = makeEvent(
            id: hex("2"),
            pubkey: author,
            kind: FeedKindFilters.shortTextNote,
            tags: [["e", hex("b"), "", "reply"]]
        )
        let article = makeEvent(
            id: hex("3"),
            pubkey: author,
            kind: FeedKindFilters.longFormArticle,
            tags: [["title", "Article"]]
        )
        let articleRepost = FeedItem(
            event: makeEvent(id: hex("4"), pubkey: author, kind: FeedKindFilters.repost, tags: []),
            profile: nil,
            displayEventOverride: article
        )

        XCTAssertTrue(ProfileFeedVisibility.isVisible(FeedItem(event: note, profile: nil), in: .posts))
        XCTAssertFalse(ProfileFeedVisibility.isVisible(FeedItem(event: article, profile: nil), in: .posts))
        XCTAssertTrue(ProfileFeedVisibility.isVisible(FeedItem(event: reply, profile: nil), in: .postsAndReplies))
        XCTAssertTrue(ProfileFeedVisibility.isVisible(FeedItem(event: article, profile: nil), in: .articles))
        XCTAssertFalse(ProfileFeedVisibility.isVisible(articleRepost, in: .articles))
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
