import ImageIO
import UIKit
import XCTest
@testable import Flow

final class MediaUploadPreparationTests: XCTestCase {
    func testPrepareUploadMediaKeepsOversizedJPEGUnderSixHundredKilobytes() throws {
        let originalImage = makeLargeTestImage(size: CGSize(width: 4_000, height: 3_000))
        let originalData = try XCTUnwrap(originalImage.jpegData(compressionQuality: 0.92))

        XCTAssertLessThan(originalData.count, 2 * 1_024 * 1_024)

        let prepared = try MediaUploadPreparation.prepareUploadMedia(
            data: originalData,
            mimeType: "image/jpeg",
            fileExtension: "jpg"
        )

        XCTAssertEqual(prepared.mimeType, "image/jpeg")
        XCTAssertEqual(prepared.fileExtension, "jpg")
        XCTAssertLessThan(prepared.data.count, originalData.count)
        XCTAssertLessThanOrEqual(prepared.data.count, 600 * 1_024)

        let preparedDimensions = try XCTUnwrap(imageDimensions(for: prepared.data))
        XCTAssertLessThanOrEqual(preparedDimensions.width, 2_400)
        XCTAssertLessThanOrEqual(preparedDimensions.height, 2_400)
    }

    private func makeLargeTestImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor(red: 0.96, green: 0.94, blue: 0.88, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let stripeColors: [UIColor] = [
                UIColor(red: 0.89, green: 0.35, blue: 0.22, alpha: 1),
                UIColor(red: 0.17, green: 0.45, blue: 0.74, alpha: 1),
                UIColor(red: 0.19, green: 0.61, blue: 0.39, alpha: 1),
                UIColor(red: 0.92, green: 0.72, blue: 0.18, alpha: 1)
            ]

            let stripeWidth = max(size.width / 12, 1)
            for (index, originX) in stride(from: CGFloat.zero, to: size.width, by: stripeWidth).enumerated() {
                stripeColors[index % stripeColors.count].setFill()
                context.fill(CGRect(x: originX, y: 0, width: stripeWidth * 0.55, height: size.height))
            }

            let insetRect = CGRect(
                x: size.width * 0.12,
                y: size.height * 0.18,
                width: size.width * 0.76,
                height: size.height * 0.64
            )
            UIColor.white.withAlphaComponent(0.25).setFill()
            context.cgContext.fillEllipse(in: insetRect)
        }
    }

    private func imageDimensions(for data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue else {
            return nil
        }

        return CGSize(width: width, height: height)
    }
}
