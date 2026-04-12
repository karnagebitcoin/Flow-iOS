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

    func testM3U8URLTokenizesAsVideoInsteadOfWebsitePreview() {
        let tokens = NoteContentParser.tokenize(content: "Watch https://example.com/live/master.m3u8")

        XCTAssertTrue(tokens.contains(where: { $0.type == .video && $0.value == "https://example.com/live/master.m3u8" }))
        XCTAssertNil(NoteContentParser.lastWebsiteURL(in: tokens))
    }

    func testHLSImetaTagTokenizesAsVideoFromMimeType() {
        let event = NostrEvent(
            id: String(repeating: "1", count: 64),
            pubkey: String(repeating: "a", count: 64),
            createdAt: 1_700_000_000,
            kind: 1,
            tags: [[
                "imeta",
                "url https://example.com/live/channel",
                "m application/vnd.apple.mpegurl"
            ]],
            content: "",
            sig: String(repeating: "f", count: 128)
        )

        let tokens = NoteContentParser.tokenize(event: event)

        XCTAssertTrue(tokens.contains(where: { $0.type == .video && $0.value == "https://example.com/live/channel" }))
    }

    func testImageAspectRatioHintsReadImetaDimensions() {
        let hints = NoteImageLayoutGuide.imageAspectRatioHints(from: [[
            "imeta",
            "url https://example.com/photo.jpg",
            "m image/jpeg",
            "dim 1200x900"
        ]])

        XCTAssertEqual(hints["https://example.com/photo.jpg"] ?? 0, 1200.0 / 900.0, accuracy: 0.001)
    }

    func testBucketedSingleImageAspectRatioUsesNearestLayoutBucket() {
        XCTAssertEqual(
            NoteImageLayoutGuide.bucketedSingleImageAspectRatio(for: 1.72),
            16.0 / 9.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            NoteImageLayoutGuide.bucketedSingleImageAspectRatio(for: 0.78),
            4.0 / 5.0,
            accuracy: 0.001
        )
    }
}
