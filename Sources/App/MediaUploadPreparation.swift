import AVFoundation
import CoreTransferable
import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PreparedUploadMedia {
    let data: Data
    let mimeType: String
    let fileExtension: String
}

enum MediaUploadPreparationError: LocalizedError {
    case missingVideoFile
    case unsupportedVideoExport
    case videoCompressionFailed

    var errorDescription: String? {
        switch self {
        case .missingVideoFile:
            return "Couldn't access the selected video."
        case .unsupportedVideoExport:
            return "This video format can't be optimized right now."
        case .videoCompressionFailed:
            return "Couldn't optimize the selected video."
        }
    }
}

enum MediaUploadPreparation {
    private static let lightCompressionThresholdBytes = 24 * 1_024 * 1_024
    private static let aggressiveCompressionThresholdBytes = 80 * 1_024 * 1_024
    private static let imageCompressionThresholdBytes = 2 * 1_024 * 1_024
    private static let maxStillImageDimension: CGFloat = 2_400

    static func prepareUploadMedia(from item: PhotosPickerItem) async throws -> PreparedUploadMedia {
        let contentType = preferredContentType(for: item)
        let mimeType = contentType.preferredMIMEType ?? fallbackMimeType(for: contentType)
        let fileExtension = contentType.preferredFilenameExtension ?? defaultFileExtension(for: mimeType)

        if contentType.conforms(to: UTType.movie) || mimeType.lowercased().hasPrefix("video/") {
            let sourceURL = try await loadTemporaryFileURL(from: item, contentType: contentType, fallbackFileExtension: fileExtension)
            defer { try? FileManager.default.removeItem(at: sourceURL) }
            return try await prepareVideoUpload(from: sourceURL, mimeType: mimeType, fallbackFileExtension: fileExtension)
        }

        guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
            throw MediaUploadError.missingFileData
        }

        let optimizedMedia = optimizeStillImageIfUseful(
            data: data,
            contentType: contentType,
            mimeType: mimeType,
            fileExtension: fileExtension
        )

        return optimizedMedia ?? PreparedUploadMedia(
            data: data,
            mimeType: mimeType,
            fileExtension: fileExtension.lowercased()
        )
    }

    static func prepareUploadMedia(
        data: Data,
        mimeType: String,
        fileExtension: String
    ) throws -> PreparedUploadMedia {
        guard !data.isEmpty else {
            throw MediaUploadError.missingFileData
        }

        let inferredContentType = UTType(mimeType: mimeType) ?? UTType(filenameExtension: fileExtension)
        let optimizedMedia = optimizeStillImageIfUseful(
            data: data,
            contentType: inferredContentType,
            mimeType: mimeType,
            fileExtension: fileExtension
        )

        return optimizedMedia ?? PreparedUploadMedia(
            data: data,
            mimeType: mimeType,
            fileExtension: fileExtension.lowercased()
        )
    }

    static func prepareUploadMedia(
        fileURL: URL,
        mimeType: String,
        fileExtension: String
    ) async throws -> PreparedUploadMedia {
        try await prepareVideoUpload(from: fileURL, mimeType: mimeType, fallbackFileExtension: fileExtension)
    }

    private static func prepareVideoUpload(
        from sourceURL: URL,
        mimeType: String,
        fallbackFileExtension: String
    ) async throws -> PreparedUploadMedia {
        let originalData = try Data(contentsOf: sourceURL)
        guard !originalData.isEmpty else {
            throw MediaUploadError.missingFileData
        }

        let originalSize = originalData.count
        let optimizedURL = await optimizedVideoURLIfNeeded(
            from: sourceURL,
            mimeType: mimeType,
            fallbackFileExtension: fallbackFileExtension,
            originalSize: originalSize
        )

        defer {
            if let optimizedURL {
                try? FileManager.default.removeItem(at: optimizedURL)
            }
        }

        let finalData: Data
        let finalExtension: String
        let finalMimeType: String

        if let optimizedURL,
           let optimizedData = try? Data(contentsOf: optimizedURL),
           !optimizedData.isEmpty,
           optimizedData.count < originalData.count {
            finalData = optimizedData
            finalExtension = optimizedURL.pathExtension.isEmpty
                ? fallbackFileExtension.lowercased()
                : optimizedURL.pathExtension.lowercased()
            finalMimeType = UTType(filenameExtension: finalExtension)?.preferredMIMEType ?? mimeType
        } else {
            finalData = originalData
            finalExtension = sourceURL.pathExtension.isEmpty
                ? fallbackFileExtension.lowercased()
                : sourceURL.pathExtension.lowercased()
            finalMimeType = UTType(filenameExtension: finalExtension)?.preferredMIMEType ?? mimeType
        }

        return PreparedUploadMedia(
            data: finalData,
            mimeType: finalMimeType,
            fileExtension: finalExtension
        )
    }

    private static func optimizedVideoURLIfNeeded(
        from sourceURL: URL,
        mimeType: String,
        fallbackFileExtension: String,
        originalSize: Int
    ) async -> URL? {
        let normalizedMimeType = mimeType.lowercased()
        let normalizedExtension = fallbackFileExtension.lowercased()
        let shouldAttemptCompression =
            originalSize >= lightCompressionThresholdBytes ||
            normalizedMimeType.contains("quicktime") ||
            normalizedExtension == "mov"

        guard shouldAttemptCompression else {
            return nil
        }

        let asset = AVURLAsset(url: sourceURL)
        let presets = preferredExportPresets(for: asset, originalSize: originalSize)

        for presetName in presets {
            let candidateURL = try? await exportCompressedVideo(
                from: sourceURL,
                presetName: presetName,
                mimeType: mimeType,
                fallbackFileExtension: fallbackFileExtension
            )

            guard let candidateURL else { continue }
            let candidateSize = measuredFileSize(at: candidateURL)

            if candidateSize > 0, candidateSize < originalSize {
                return candidateURL
            }

            try? FileManager.default.removeItem(at: candidateURL)
        }

        return nil
    }

    private static func exportCompressedVideo(
        from sourceURL: URL,
        presetName: String,
        mimeType: String,
        fallbackFileExtension: String
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw MediaUploadPreparationError.videoCompressionFailed
        }

        let outputFileType = preferredOutputFileType(for: exportSession) ?? .mov
        let outputExtension = fileExtension(for: outputFileType) ?? fallbackFileExtension.lowercased()
        let outputURL = temporaryFileURL(prefix: "video-upload-", fileExtension: outputExtension)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFileType
        exportSession.shouldOptimizeForNetworkUse = true

        try await export(session: exportSession)
        return outputURL
    }

    private static func preferredExportPresets(for asset: AVAsset, originalSize: Int) -> [String] {
        let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        var preferredPresets = [
            AVAssetExportPresetPassthrough,
            AVAssetExportPresetHighestQuality
        ]

        if originalSize >= aggressiveCompressionThresholdBytes {
            preferredPresets.append(contentsOf: [
                AVAssetExportPreset1920x1080,
                AVAssetExportPreset1280x720,
                AVAssetExportPresetMediumQuality
            ])
        }

        return preferredPresets.filter { presets.contains($0) }
    }

    private static func preferredOutputFileType(for exportSession: AVAssetExportSession) -> AVFileType? {
        if exportSession.supportedFileTypes.contains(.mp4) {
            return .mp4
        }
        if exportSession.supportedFileTypes.contains(.mov) {
            return .mov
        }
        return exportSession.supportedFileTypes.first
    }

    private static func export(session: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: session.error ?? MediaUploadPreparationError.videoCompressionFailed)
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(throwing: MediaUploadPreparationError.videoCompressionFailed)
                }
            }
        }
    }

    private static func loadTemporaryFileURL(
        from item: PhotosPickerItem,
        contentType: UTType,
        fallbackFileExtension: String
    ) async throws -> URL {
        guard let transferredFile = try await item.loadTransferable(type: ImportedMovieFile.self) else {
            throw MediaUploadPreparationError.missingVideoFile
        }

        let sourceURL = transferredFile.file
        let sourceExtension = sourceURL.pathExtension.isEmpty
            ? fallbackFileExtension.lowercased()
            : sourceURL.pathExtension.lowercased()
        let copiedURL = temporaryFileURL(prefix: "picked-video-", fileExtension: sourceExtension)
        try FileManager.default.copyItem(at: sourceURL, to: copiedURL)
        return copiedURL
    }

    private static func preferredContentType(for item: PhotosPickerItem) -> UTType {
        item.supportedContentTypes.first(where: { $0.conforms(to: UTType.movie) })
            ?? item.supportedContentTypes.first
            ?? .jpeg
    }

    private static func optimizeStillImageIfUseful(
        data: Data,
        contentType: UTType?,
        mimeType: String,
        fileExtension: String
    ) -> PreparedUploadMedia? {
        let normalizedMimeType = mimeType.lowercased()
        let normalizedExtension = fileExtension.lowercased()

        guard shouldAttemptStillImageOptimization(
            contentType: contentType,
            mimeType: normalizedMimeType,
            fileExtension: normalizedExtension,
            byteCount: data.count
        ) else {
            return nil
        }

        guard let optimized = optimizedStillImagePayload(
            from: data,
            contentType: contentType,
            originalMimeType: mimeType,
            originalFileExtension: normalizedExtension
        ) else {
            return nil
        }

        guard optimized.data.count > 0, optimized.data.count < data.count else {
            return nil
        }

        return optimized
    }

    private static func shouldAttemptStillImageOptimization(
        contentType: UTType?,
        mimeType: String,
        fileExtension: String,
        byteCount: Int
    ) -> Bool {
        if let contentType, contentType.conforms(to: .movie) {
            return false
        }

        let normalizedExtension = fileExtension.lowercased()
        if ["gif", "webp", "svg", "pdf"].contains(normalizedExtension) {
            return false
        }

        if mimeType.contains("gif") || mimeType.contains("webp") || mimeType.contains("svg") {
            return false
        }

        guard contentType?.conforms(to: .image) != false || mimeType.hasPrefix("image/") else {
            return false
        }

        return byteCount >= imageCompressionThresholdBytes || mimeType.contains("heic") || mimeType.contains("png")
    }

    private static func optimizedStillImagePayload(
        from data: Data,
        contentType: UTType?,
        originalMimeType: String,
        originalFileExtension: String
    ) -> PreparedUploadMedia? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        guard CGImageSourceGetCount(source) <= 1 else {
            return nil
        }

        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = (sourceProperties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let pixelHeight = (sourceProperties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        let longestEdge = max(pixelWidth, pixelHeight)
        let shouldResize = longestEdge > maxStillImageDimension

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxStillImageDimension,
            kCGImageSourceShouldCacheImmediately: false
        ]

        let cgImage: CGImage?
        if shouldResize {
            cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
        } else {
            cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        guard let cgImage else {
            return nil
        }

        let hasAlphaChannel = cgImage.hasAlphaChannel
        let renderedImage = renderedStillImage(from: cgImage, hasAlphaChannel: hasAlphaChannel)

        if hasAlphaChannel {
            guard let pngData = renderedImage.pngData() else {
                return nil
            }

            return PreparedUploadMedia(
                data: pngData,
                mimeType: "image/png",
                fileExtension: "png"
            )
        }

        let jpegQuality: CGFloat
        if data.count >= 8 * 1_024 * 1_024 || longestEdge > 3_600 {
            jpegQuality = 0.82
        } else {
            jpegQuality = 0.88
        }

        guard let jpegData = renderedImage.jpegData(compressionQuality: jpegQuality) else {
            return nil
        }

        return PreparedUploadMedia(
            data: jpegData,
            mimeType: "image/jpeg",
            fileExtension: "jpg"
        )
    }

    private static func renderedStillImage(
        from cgImage: CGImage,
        hasAlphaChannel: Bool
    ) -> UIImage {
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = !hasAlphaChannel
        let renderer = UIGraphicsImageRenderer(size: imageSize, format: format)

        return renderer.image { _ in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: imageSize))
        }
    }

    private static func fallbackMimeType(for contentType: UTType) -> String {
        if contentType.conforms(to: UTType.movie) {
            return "video/quicktime"
        }
        if contentType.conforms(to: UTType.image) {
            return "image/jpeg"
        }
        return "application/octet-stream"
    }

    private static func fileExtension(for fileType: AVFileType) -> String? {
        switch fileType {
        case .mp4:
            return "mp4"
        case .mov:
            return "mov"
        case .m4v:
            return "m4v"
        default:
            return nil
        }
    }

    private static func temporaryFileURL(prefix: String, fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
    }

    private static func measuredFileSize(at url: URL) -> Int {
        if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           fileSize > 0 {
            return fileSize
        }

        if let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = fileAttributes[.size] as? NSNumber {
            return fileSize.intValue
        }

        if let data = try? Data(contentsOf: url) {
            return data.count
        }

        return 0
    }

    private static func defaultFileExtension(for mimeType: String) -> String {
        let normalized = mimeType.lowercased()
        if normalized.contains("jpeg") || normalized.contains("jpg") {
            return "jpg"
        }
        if normalized.contains("png") {
            return "png"
        }
        if normalized.contains("heic") {
            return "heic"
        }
        if normalized.contains("gif") {
            return "gif"
        }
        if normalized.contains("webp") {
            return "webp"
        }
        if normalized.contains("quicktime") || normalized.contains("mov") {
            return "mov"
        }
        if normalized.contains("mp4") {
            return "mp4"
        }
        if normalized.contains("mpeg") || normalized.contains("mp3") {
            return "mp3"
        }
        if normalized.contains("m4a") {
            return "m4a"
        }
        return "bin"
    }
}

private extension CGImage {
    var hasAlphaChannel: Bool {
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }
}

private struct ImportedMovieFile: Transferable {
    let file: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: UTType.movie) { received in
            ImportedMovieFile(file: received.file)
        }
    }
}
