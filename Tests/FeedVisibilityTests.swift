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
        XCTAssertFalse(ProfileViewModel.requestedFeedKinds.contains(FeedKindFilters.legacyZapPoll))
        XCTAssertEqual(FeedKindFilters.pollKinds, [FeedKindFilters.poll])
        XCTAssertFalse(FeedKindFilters.supportedKinds.contains(FeedKindFilters.legacyZapPoll))
        XCTAssertFalse(FeedKindFilters.normalizedKinds([FeedKindFilters.poll, FeedKindFilters.legacyZapPoll]).contains(FeedKindFilters.legacyZapPoll))
    }
}

private func hex(_ character: Character) -> String {
    String(repeating: String(character), count: 64)
}
