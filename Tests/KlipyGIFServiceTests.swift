import XCTest
@testable import Flow

final class KlipyGIFServiceTests: XCTestCase {
    func testKlipyGIFItemPrefersSmallerPreviewAndAnimatedGIFForAttachment() throws {
        let item = try JSONDecoder().decode(KlipyGIFItem.self, from: Data(
            """
            {
              "id": 8041071659142944,
              "slug": "hello-hi-662",
              "title": "Hello",
              "file": {
                "hd": {
                  "gif": {
                    "url": "https://static.klipy.com/hello-hd.gif",
                    "width": 498,
                    "height": 498,
                    "size": 4001918
                  },
                  "jpg": {
                    "url": "https://static.klipy.com/hello-hd.jpg",
                    "width": 498,
                    "height": 498,
                    "size": 19255
                  }
                },
                "md": {
                  "gif": {
                    "url": "https://static.klipy.com/hello-md.gif",
                    "width": 320,
                    "height": 320,
                    "size": 1200000
                  }
                },
                "sm": {
                  "jpg": {
                    "url": "https://static.klipy.com/hello-sm.jpg",
                    "width": 200,
                    "height": 200,
                    "size": 8000
                  }
                }
              }
            }
            """.utf8
        ))

        let candidate = try XCTUnwrap(
            item.makeAttachmentCandidate(
                customerID: "customer-123",
                searchQuery: "hello"
            )
        )

        XCTAssertEqual(candidate.slug, "hello-hi-662")
        XCTAssertEqual(candidate.customerID, "customer-123")
        XCTAssertEqual(candidate.searchQuery, "hello")
        XCTAssertEqual(candidate.previewURL?.absoluteString, "https://static.klipy.com/hello-sm.jpg")
        XCTAssertEqual(candidate.downloadURL.absoluteString, "https://static.klipy.com/hello-md.gif")
        XCTAssertEqual(candidate.mimeType, "image/gif")
        XCTAssertEqual(candidate.fileExtension, "gif")
    }

    func testKlipyGIFItemRequiresAnimatedGIFAssetForAttachment() throws {
        let item = try JSONDecoder().decode(KlipyGIFItem.self, from: Data(
            """
            {
              "id": 123,
              "slug": "still-only",
              "title": "Still only",
              "file": {
                "sm": {
                  "jpg": {
                    "url": "https://static.klipy.com/still.jpg",
                    "width": 200,
                    "height": 200,
                    "size": 8000
                  }
                }
              }
            }
            """.utf8
        ))

        XCTAssertNil(
            item.makeAttachmentCandidate(
                customerID: "customer-123",
                searchQuery: nil
            )
        )
    }
}
