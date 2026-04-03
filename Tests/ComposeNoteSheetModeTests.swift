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

    func testActiveMentionQuerySupportsFreeformLocalSearchWithSpaces() {
        let text = "gm @fiat jaf"
        let selection = NSRange(location: (text as NSString).length, length: 0)

        let query = ComposeMentionSupport.activeQuery(
            in: text,
            selection: selection,
            confirmedMentions: []
        )

        XCTAssertEqual(query?.query, "fiat jaf")
    }

    func testActiveMentionQuerySupportsNip05StyleSearchText() {
        let text = "@jb55@damus.io"
        let selection = NSRange(location: (text as NSString).length, length: 0)

        let query = ComposeMentionSupport.activeQuery(
            in: text,
            selection: selection,
            confirmedMentions: []
        )

        XCTAssertEqual(query?.query, "jb55@damus.io")
    }

    func testActiveMentionQueryIgnoresEmailAddresses() {
        let text = "reach me at fiat@jaf.com"
        let selection = NSRange(location: (text as NSString).length, length: 0)

        let query = ComposeMentionSupport.activeQuery(
            in: text,
            selection: selection,
            confirmedMentions: []
        )

        XCTAssertNil(query)
    }

    func testActiveMentionQueryDoesNotReopenConfirmedMentionAfterInsertion() {
        let text = "@fiatjaf "
        let selection = NSRange(location: (text as NSString).length, length: 0)
        let confirmedMention = ComposeSelectedMention(
            pubkey: String(format: "%064x", 1),
            handle: "fiatjaf",
            range: NSRange(location: 0, length: 8)
        )

        let query = ComposeMentionSupport.activeQuery(
            in: text,
            selection: selection,
            confirmedMentions: [confirmedMention]
        )

        XCTAssertNil(query)
    }

    func testActiveMentionQueryStopsAfterTrailingProseExtendsPastSearchBounds() {
        let text = "gm @michael saylor thanks for the note"
        let selection = NSRange(location: (text as NSString).length, length: 0)

        let query = ComposeMentionSupport.activeQuery(
            in: text,
            selection: selection,
            confirmedMentions: []
        )

        XCTAssertNil(query)
    }
}
