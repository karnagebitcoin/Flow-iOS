import XCTest
@testable import Flow

final class HomeFeedViewModelTests: XCTestCase {
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
