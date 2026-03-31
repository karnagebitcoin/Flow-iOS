import XCTest
@testable import Flow

final class HomeFeedViewModelTests: XCTestCase {
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
    func testFollowingRefreshUsesExhaustiveRelayStrategy() {
        let strategy = HomeFeedViewModel.requestStrategy(for: .following, isPagination: false)

        XCTAssertEqual(strategy.relayFetchMode, .allRelays)
        XCTAssertEqual(strategy.fetchTimeout, 8)
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
}
