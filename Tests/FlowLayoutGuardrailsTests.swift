import XCTest
@testable import Flow

final class FlowLayoutGuardrailsTests: XCTestCase {
    func testSoftWrappedLeavesShortStringsUntouched() {
        let value = "hello world"

        XCTAssertEqual(FlowLayoutGuardrails.softWrapped(value), value)
    }

    func testSoftWrappedInsertsBreaksForLongUnbrokenRuns() {
        let value = "https://example.com/" + String(repeating: "a", count: 60)
        let wrapped = FlowLayoutGuardrails.softWrapped(value)

        XCTAssertNotEqual(wrapped, value)
        XCTAssertTrue(wrapped.contains("\u{200B}"))
        XCTAssertEqual(wrapped.replacingOccurrences(of: "\u{200B}", with: ""), value)
    }

    func testSoftWrappedCanProtectShorterProfileRuns() {
        let value = String(repeating: "A", count: 24)
        let wrapped = FlowLayoutGuardrails.softWrapped(
            value,
            maxNonBreakingRunLength: 8,
            minimumLength: 8
        )

        XCTAssertTrue(wrapped.contains("\u{200B}"))
        XCTAssertEqual(wrapped.replacingOccurrences(of: "\u{200B}", with: ""), value)
    }

    func testClampedAspectRatioRejectsInvalidValuesAndCapsOutliers() throws {
        XCTAssertNil(FlowLayoutGuardrails.clampedAspectRatio(nil))
        XCTAssertNil(FlowLayoutGuardrails.clampedAspectRatio(0))
        XCTAssertEqual(try XCTUnwrap(FlowLayoutGuardrails.clampedAspectRatio(0.05)), 0.28, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(FlowLayoutGuardrails.clampedAspectRatio(10)), 3.2, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(FlowLayoutGuardrails.clampedAspectRatio(1.6)), 1.6, accuracy: 0.0001)
    }

    func testAspectFitMediaSizeKeepsWideMediaWithinAvailableWidth() {
        let size = FlowLayoutGuardrails.aspectFitMediaSize(
            availableWidth: 320,
            aspectRatio: 3.2,
            maxHeight: 620,
            fallbackWidth: 320
        )

        XCTAssertEqual(size.width, 320, accuracy: 0.0001)
        XCTAssertEqual(size.height, 100, accuracy: 0.0001)
    }

    func testAspectFitMediaSizeCapsTallMediaHeightWithoutStretching() {
        let size = FlowLayoutGuardrails.aspectFitMediaSize(
            availableWidth: 320,
            aspectRatio: 0.4,
            maxHeight: 300,
            fallbackWidth: 320
        )

        XCTAssertEqual(size.width, 120, accuracy: 0.0001)
        XCTAssertEqual(size.height, 300, accuracy: 0.0001)
    }

    func testProfileHeaderWidthUsesFiniteProposal() {
        XCTAssertEqual(
            ProfileHeaderLayoutGuardrails.boundedWidth(
                proposedWidth: 375,
                fallbackWidth: 320
            ),
            375,
            accuracy: 0.0001
        )
    }

    func testProfileHeaderWidthFallsBackWhenProposalIsInvalid() {
        XCTAssertEqual(
            ProfileHeaderLayoutGuardrails.boundedWidth(
                proposedWidth: nil,
                fallbackWidth: 320
            ),
            320,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ProfileHeaderLayoutGuardrails.boundedWidth(
                proposedWidth: .infinity,
                fallbackWidth: 320
            ),
            320,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ProfileHeaderLayoutGuardrails.boundedWidth(
                proposedWidth: -1,
                fallbackWidth: 320
            ),
            320,
            accuracy: 0.0001
        )
    }
}
