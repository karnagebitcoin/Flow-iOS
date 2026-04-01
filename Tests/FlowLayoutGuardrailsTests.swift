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

    func testClampedAspectRatioRejectsInvalidValuesAndCapsOutliers() {
        XCTAssertNil(FlowLayoutGuardrails.clampedAspectRatio(nil))
        XCTAssertNil(FlowLayoutGuardrails.clampedAspectRatio(0))
        XCTAssertEqual(FlowLayoutGuardrails.clampedAspectRatio(0.05), 0.28, accuracy: 0.0001)
        XCTAssertEqual(FlowLayoutGuardrails.clampedAspectRatio(10), 3.2, accuracy: 0.0001)
        XCTAssertEqual(FlowLayoutGuardrails.clampedAspectRatio(1.6), 1.6, accuracy: 0.0001)
    }
}
