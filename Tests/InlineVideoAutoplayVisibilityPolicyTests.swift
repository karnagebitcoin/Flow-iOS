import XCTest
@testable import Flow

final class InlineVideoAutoplayVisibilityPolicyTests: XCTestCase {
    func testReturnsNilWhenVideoCenterIsTooCloseToTop() {
        let frame = CGRect(x: 0, y: 40, width: 320, height: 280)

        let score = InlineVideoAutoplayVisibilityPolicy.autoplayScore(
            for: frame,
            viewportHeight: 800
        )

        XCTAssertNil(score)
    }

    func testReturnsNilWhenTooLittleOfVideoIsVisible() {
        let frame = CGRect(x: 0, y: 580, width: 320, height: 700)

        let score = InlineVideoAutoplayVisibilityPolicy.autoplayScore(
            for: frame,
            viewportHeight: 800
        )

        XCTAssertNil(score)
    }

    func testReturnsScoreWhenVideoIsInCentralViewingBand() {
        let frame = CGRect(x: 0, y: 250, width: 320, height: 300)

        let score = InlineVideoAutoplayVisibilityPolicy.autoplayScore(
            for: frame,
            viewportHeight: 800
        )

        XCTAssertNotNil(score)
        XCTAssertGreaterThan(score ?? 0, 1.0)
    }

    func testPrefersVideoCloserToViewportCenter() {
        let centered = CGRect(x: 0, y: 250, width: 320, height: 300)
        let edgeOfBand = CGRect(x: 0, y: 170, width: 320, height: 300)

        let centeredScore = InlineVideoAutoplayVisibilityPolicy.autoplayScore(
            for: centered,
            viewportHeight: 800
        )
        let edgeScore = InlineVideoAutoplayVisibilityPolicy.autoplayScore(
            for: edgeOfBand,
            viewportHeight: 800
        )

        XCTAssertGreaterThan(centeredScore ?? 0, edgeScore ?? 0)
    }

    func testIgnoresTinyFrameChangesWithinSameAutoplayBucket() {
        let previous = CGRect(x: 0, y: 250, width: 320, height: 300)
        let next = CGRect(x: 0, y: 255, width: 320, height: 300)

        let shouldReport = InlineVideoAutoplayVisibilityPolicy.shouldReportFrameChange(
            previous: previous,
            next: next,
            viewportHeight: 800
        )

        XCTAssertFalse(shouldReport)
    }

    func testReportsFrameChangeWhenEligibilityChanges() {
        let previous = CGRect(x: 0, y: 250, width: 320, height: 300)
        let next = CGRect(x: 0, y: 80, width: 320, height: 300)

        let shouldReport = InlineVideoAutoplayVisibilityPolicy.shouldReportFrameChange(
            previous: previous,
            next: next,
            viewportHeight: 800
        )

        XCTAssertTrue(shouldReport)
    }
}
