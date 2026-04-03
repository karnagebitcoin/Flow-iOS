import XCTest
import NostrSDK
@testable import Flow

final class NoteContentLinkResolverTests: XCTestCase {
    func testMentionLinkUsesInAppProfileRouteWhenProfileTapAvailable() throws {
        let pubkey = String(format: "%064x", 1)
        let npub = try XCTUnwrap(PublicKey(hex: pubkey)?.npub)
        let token = NoteContentToken(type: .nostrMention, value: npub)

        let url = try XCTUnwrap(
            NoteContentLinkResolver.linkURL(
                for: token,
                allowsInAppProfileRouting: true
            )
        )

        XCTAssertEqual(url.scheme, "x21-profile")
        XCTAssertEqual(NoteContentParser.profilePubkey(fromActionURL: url), pubkey)
    }

    func testMentionLinkFallsBackToExternalNlinkWhenProfileTapUnavailable() throws {
        let pubkey = String(format: "%064x", 2)
        let npub = try XCTUnwrap(PublicKey(hex: pubkey)?.npub)
        let token = NoteContentToken(type: .nostrMention, value: npub)

        let url = try XCTUnwrap(
            NoteContentLinkResolver.linkURL(
                for: token,
                allowsInAppProfileRouting: false
            )
        )

        XCTAssertEqual(url.absoluteString, "https://nlink.to/\(npub)")
    }
}
