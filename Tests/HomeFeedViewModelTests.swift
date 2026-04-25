import XCTest
@testable import Flow

final class HomeFeedViewModelTests: XCTestCase {
    @MainActor
    func testPaginationDoesNotStopOnShortNonEmptyPage() {
        XCTAssertFalse(FeedPaginationHeuristic.shouldStopPaging(afterFetchedCount: 1))
        XCTAssertFalse(FeedPaginationHeuristic.shouldStopPaging(afterFetchedCount: 24))
    }

    @MainActor
    func testPaginationStopsOnlyAfterEmptyPage() {
        XCTAssertTrue(FeedPaginationHeuristic.shouldStopPaging(afterFetchedCount: 0))
    }

    @MainActor
    func testHomeFeedUsesLargerDefaultPageSize() {
        XCTAssertEqual(HomeFeedViewModel.defaultPageSizeForTesting, 100)
    }

    @MainActor
    func testPaginationPrefetchStartsBeforeLastVisibleItem() {
        XCTAssertTrue(
            HomeFeedViewModel.shouldPrefetchMore(
                visibleItemCount: 100,
                currentIndex: 86
            )
        )
        XCTAssertFalse(
            HomeFeedViewModel.shouldPrefetchMore(
                visibleItemCount: 100,
                currentIndex: 70
            )
        )
    }

    @MainActor
    func testPaginationSpinnerAppearsOnlyNearTheEdge() {
        XCTAssertTrue(
            HomeFeedViewModel.shouldShowPaginationSpinner(
                visibleItemCount: 100,
                currentIndex: 97
            )
        )
        XCTAssertFalse(
            HomeFeedViewModel.shouldShowPaginationSpinner(
                visibleItemCount: 100,
                currentIndex: 90
            )
        )
    }

    @MainActor
    func testFollowingRefreshUsesFastRelayStrategy() {
        let strategy = HomeFeedViewModel.requestStrategy(for: .following, isPagination: false)

        XCTAssertEqual(strategy.relayFetchMode, .firstNonEmptyRelay)
        XCTAssertEqual(strategy.fetchTimeout, 3)
    }

    @MainActor
    func testFollowingPaginationUsesExhaustiveRelayStrategy() {
        let strategy = HomeFeedViewModel.requestStrategy(for: .following, isPagination: true)

        XCTAssertEqual(strategy.relayFetchMode, .allRelays)
        XCTAssertEqual(strategy.fetchTimeout, 12)
    }

    @MainActor
    func testNonFollowingFeedsRetainFastRelayStrategy() {
        let strategy = HomeFeedViewModel.requestStrategy(for: .network, isPagination: true)

        XCTAssertEqual(strategy.relayFetchMode, .firstNonEmptyRelay)
        XCTAssertEqual(strategy.fetchTimeout, 3)
    }

    @MainActor
    func testFollowingInitialLoadTargetsASmallerVisibleSlice() {
        XCTAssertEqual(
            HomeFeedViewModel.initialVisibleTargetForTesting(
                source: .following,
                mode: .posts,
                limit: 100
            ),
            12
        )
        XCTAssertEqual(
            HomeFeedViewModel.initialVisibleTargetForTesting(
                source: .following,
                mode: .postsAndReplies,
                limit: 100
            ),
            8
        )
    }

    @MainActor
    func testFollowingModeSwitchOnlyRequiresInitialVisibleSlice() {
        XCTAssertEqual(
            HomeFeedViewModel.minimumVisibleItemsForSelectedModeForTesting(
                source: .following,
                mode: .posts,
                pageSize: 100
            ),
            12
        )
        XCTAssertEqual(
            HomeFeedViewModel.minimumVisibleItemsForSelectedModeForTesting(
                source: .following,
                mode: .postsAndReplies,
                pageSize: 100
            ),
            8
        )
    }

    @MainActor
    func testPaginationKeepsFullVisibleTargetOutsideInitialFollowingPass() {
        XCTAssertEqual(
            HomeFeedViewModel.initialVisibleTargetForTesting(
                source: .network,
                mode: .posts,
                limit: 100
            ),
            100
        )
        XCTAssertEqual(
            HomeFeedViewModel.initialVisibleTargetForTesting(
                source: .polls,
                mode: nil,
                limit: 100
            ),
            8
        )
    }

    @MainActor
    func testTrendingInitialLoadCanBackfillMultipleDayWindows() {
        XCTAssertEqual(
            HomeFeedViewModel.trendingWindowTraversalLimitForTesting(isInitialPage: true),
            7
        )
    }

    @MainActor
    func testTrendingPaginationChecksOneDayWindowAtATime() {
        XCTAssertEqual(
            HomeFeedViewModel.trendingWindowTraversalLimitForTesting(isInitialPage: false),
            1
        )
    }
}
