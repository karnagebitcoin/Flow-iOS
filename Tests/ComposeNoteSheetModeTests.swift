import XCTest
@testable import Flow

final class ComposeNoteSheetModeTests: XCTestCase {
    func testNewNoteModeUsesSharedComposerCopy() {
        let mode = ComposeNoteSheetMode(hasReplyTarget: false, hasQuotedEvent: false)

        XCTAssertEqual(mode, .newNote)
        XCTAssertEqual(mode.navigationTitle, "Compose note")
        XCTAssertEqual(mode.publishButtonTitle, "Post")
        XCTAssertEqual(mode.placeholderText, "What do you want to share?")
        XCTAssertEqual(mode.accessibilityActionLabel, "Posting")
    }

    func testReplyModeUsesReplySpecificCopy() {
        let mode = ComposeNoteSheetMode(hasReplyTarget: true, hasQuotedEvent: false)

        XCTAssertEqual(mode, .reply)
        XCTAssertEqual(mode.navigationTitle, "Reply")
        XCTAssertEqual(mode.publishButtonTitle, "Reply")
        XCTAssertEqual(mode.placeholderText, "Post your reply")
        XCTAssertEqual(mode.accessibilityActionLabel, "Replying")
    }

    func testQuoteModeKeepsSharedComposerChrome() {
        let mode = ComposeNoteSheetMode(hasReplyTarget: false, hasQuotedEvent: true)

        XCTAssertEqual(mode, .quote)
        XCTAssertEqual(mode.navigationTitle, "Quote")
        XCTAssertEqual(mode.publishButtonTitle, "Post")
        XCTAssertEqual(mode.placeholderText, "Add your thoughts")
        XCTAssertEqual(mode.accessibilityActionLabel, "Quoting")
    }

    func testQuotedEventTakesPriorityWhenBothContextsArePresent() {
        let mode = ComposeNoteSheetMode(hasReplyTarget: true, hasQuotedEvent: true)

        XCTAssertEqual(mode, .quote)
    }
}
