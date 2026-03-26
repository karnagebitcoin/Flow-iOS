import CryptoKit
import Foundation
import SwiftUI
import UIKit

enum FlowMediaCache {
    static let sharedURLCacheMemoryCapacity = 64 * 1_024 * 1_024
    static let sharedURLCacheDiskCapacity = 256 * 1_024 * 1_024
    static let sharedURLCacheDirectory = "flow-url-cache"

    static func configureSharedURLCache() {
        let current = URLCache.shared
        if current.memoryCapacity >= sharedURLCacheMemoryCapacity,
           current.diskCapacity >= sharedURLCacheDiskCapacity {
            return
        }

        URLCache.shared = URLCache(
            memoryCapacity: sharedURLCacheMemoryCapacity,
            diskCapacity: sharedURLCacheDiskCapacity,
            diskPath: sharedURLCacheDirectory
        )
    }
}

actor FlowImageCache {
    static let shared = FlowImageCache()

    private let fileManager: FileManager
    private let directoryURL: URL
    private let memoryCache = NSCache<NSURL, UIImage>()
    private let maxDiskBytes: Int64 = 384 * 1_024 * 1_024
    private let maxDiskEntries = 12_000
    private let maxEntryAge: TimeInterval = 60 * 60 * 24 * 30
    private var inFlight: [URL: Task<Data?, Never>] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let root = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directoryURL = root.appendingPathComponent("flow-media-cache", isDirectory: true)
        memoryCache.totalCostLimit = FlowMediaCache.sharedURLCacheMemoryCapacity
    }

    func image(for url: URL) async -> UIImage? {
        guard isCacheable(url) else { return nil }

        let cacheKey = url as NSURL
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        if let diskImage = loadImageFromDisk(for: url, cacheKey: cacheKey) {
            return diskImage
        }

        let request = URLRequest(
            url: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 30
        )

        if let cachedResponse = URLCache.shared.cachedResponse(for: request),
           let sharedCachedImage = storeDecodedImage(
                data: cachedResponse.data,
                for: url,
                cacheKey: cacheKey,
                persistToDisk: true
           ) {
            return sharedCachedImage
        }

        if let existingTask = inFlight[url] {
            let data = await existingTask.value
            return storeDecodedImage(data: data, for: url, cacheKey: cacheKey, persistToDisk: true)
        }

        let task = Task {
            await Self.fetchImageData(with: request)
        }
        inFlight[url] = task

        let data = await task.value
        inFlight[url] = nil
        return storeDecodedImage(data: data, for: url, cacheKey: cacheKey, persistToDisk: true)
    }

    func prefetch(urls: [URL]) async {
        let deduplicated = deduplicatedURLs(from: urls)
        guard !deduplicated.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for url in deduplicated.prefix(36) {
                group.addTask {
                    _ = await self.image(for: url)
                }
            }
            await group.waitForAll()
        }
    }

    func totalCacheSizeBytes() -> Int64 {
        localDiskUsageBytes() + Int64(URLCache.shared.currentDiskUsage)
    }

    func clearAllCachedImages() async {
        memoryCache.removeAllObjects()
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
        URLCache.shared.removeAllCachedResponses()

        if fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.removeItem(at: directoryURL)
        }
        ensureDirectory()
    }

    private func isCacheable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func loadImageFromDisk(for url: URL, cacheKey: NSURL) -> UIImage? {
        ensureDirectory()
        let fileURL = diskFileURL(for: url)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        let modificationDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
        if Date().timeIntervalSince(modificationDate) > maxEntryAge {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL),
              let image = preparedImage(from: data) else {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }

        memoryCache.setObject(image, forKey: cacheKey, cost: memoryCost(for: image))
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        return image
    }

    private func storeDecodedImage(
        data: Data?,
        for url: URL,
        cacheKey: NSURL,
        persistToDisk: Bool
    ) -> UIImage? {
        guard let data,
              let image = preparedImage(from: data) else {
            return nil
        }

        memoryCache.setObject(image, forKey: cacheKey, cost: memoryCost(for: image))
        if persistToDisk {
            persistImageData(data, for: url)
        }
        return image
    }

    private func persistImageData(_ data: Data, for url: URL) {
        ensureDirectory()
        let fileURL = diskFileURL(for: url)
        try? data.write(to: fileURL, options: .atomic)
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        pruneDiskIfNeeded()
    }

    private func ensureDirectory() {
        if fileManager.fileExists(atPath: directoryURL.path) {
            return
        }

        try? fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func diskFileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hashed = digest.map { String(format: "%02x", $0) }.joined()
        let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension.lowercased()
        return directoryURL.appendingPathComponent("\(hashed).\(ext)", isDirectory: false)
    }

    private func deduplicatedURLs(from urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var ordered: [URL] = []

        for url in urls where isCacheable(url) {
            let normalized = url.absoluteString.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            ordered.append(url)
        }

        return ordered
    }

    private func localDiskUsageBytes() -> Int64 {
        ensureDirectory()
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(fileSize)
        }
        return total
    }

    private func pruneDiskIfNeeded() {
        ensureDirectory()
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var totalBytes: Int64 = 0
        let sortedFiles = files.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            return lhsDate > rhsDate
        }

        for fileURL in sortedFiles {
            let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            totalBytes += Int64(fileSize)
        }

        if sortedFiles.count <= maxDiskEntries, totalBytes <= maxDiskBytes {
            return
        }

        var retainedCount = 0
        var retainedBytes: Int64 = 0
        for fileURL in sortedFiles {
            let fileSize = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            let shouldRetain = retainedCount < maxDiskEntries && retainedBytes + fileSize <= maxDiskBytes
            if shouldRetain {
                retainedCount += 1
                retainedBytes += fileSize
            } else {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    private func memoryCost(for image: UIImage) -> Int {
        let scale = image.scale
        let width = Int(image.size.width * scale)
        let height = Int(image.size.height * scale)
        guard width > 0, height > 0 else { return 1 }
        return width * height * 4
    }

    private func preparedImage(from data: Data) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        return image.preparingForDisplay() ?? image
    }

    private static func fetchImageData(with request: URLRequest) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...399).contains(httpResponse.statusCode) {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }
}

enum CachedAsyncImagePhase {
    case empty
    case success(Image)
    case failure
}

struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    let transaction: Transaction
    private let content: (CachedAsyncImagePhase) -> Content

    @State private var phase: CachedAsyncImagePhase = .empty
    @State private var loadedURL: URL?

    init(
        url: URL?,
        transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (CachedAsyncImagePhase) -> Content
    ) {
        self.url = url
        self.transaction = transaction
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                await load()
            }
    }

    @MainActor
    private func load() async {
        guard let url else {
            loadedURL = nil
            phase = .failure
            return
        }

        if loadedURL == url, case .success = phase {
            return
        }

        loadedURL = url
        phase = .empty

        if let image = await FlowImageCache.shared.image(for: url) {
            withTransaction(transaction) {
                phase = .success(Image(uiImage: image))
            }
        } else {
            withTransaction(transaction) {
                phase = .failure
            }
        }
    }
}
