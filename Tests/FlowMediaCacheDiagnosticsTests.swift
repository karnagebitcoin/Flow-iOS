import XCTest
@testable import Flow

final class FlowMediaCacheDiagnosticsTests: XCTestCase {
    func testImageDiagnosticsTrackNetworkThenImageMemoryHit() async {
        let rootDirectoryURL = makeTemporaryDirectory()
        let urlCache = makeURLCache()
        let data = makePNGData()
        let cache = FlowImageCache(
            rootDirectoryURL: rootDirectoryURL,
            urlCache: urlCache,
            fetchImageData: { _ in data }
        )
        let url = URL(string: "https://example.com/photo.png")!

        let firstImage = await cache.image(for: url)
        let secondImage = await cache.image(for: url)
        let snapshot = await cache.diagnosticsSnapshot()

        XCTAssertNotNil(firstImage)
        XCTAssertNotNil(secondImage)
        XCTAssertEqual(snapshot.trackedRequestCount, 2)
        XCTAssertEqual(snapshot.networkFetchCount, 1)
        XCTAssertEqual(snapshot.imageMemoryHitCount, 1)
        XCTAssertEqual(snapshot.cacheHitCount, 1)
        XCTAssertEqual(snapshot.cacheMissCount, 1)
        XCTAssertEqual(snapshot.networkServedByteCount, Int64(data.count))
        XCTAssertEqual(snapshot.cacheServedByteCount, Int64(data.count))
        XCTAssertEqual(snapshot.cacheHitRate, 0.5, accuracy: 0.0001)
    }

    func testDiskHitIsReportedForNewCacheInstanceUsingPersistedMedia() async {
        let rootDirectoryURL = makeTemporaryDirectory()
        let urlCache = makeURLCache()
        let data = Data("cached-on-disk".utf8)
        let url = URL(string: "https://example.com/avatar.jpg")!

        let warmCache = FlowImageCache(
            rootDirectoryURL: rootDirectoryURL,
            urlCache: urlCache,
            fetchImageData: { _ in data }
        )
        _ = await warmCache.data(for: url)

        let diskBackedCache = FlowImageCache(
            rootDirectoryURL: rootDirectoryURL,
            urlCache: urlCache,
            fetchImageData: { _ in nil }
        )
        let cachedData = await diskBackedCache.data(for: url)
        let snapshot = await diskBackedCache.diagnosticsSnapshot()

        XCTAssertEqual(cachedData, data)
        XCTAssertEqual(snapshot.trackedRequestCount, 1)
        XCTAssertEqual(snapshot.diskHitCount, 1)
        XCTAssertEqual(snapshot.cacheHitCount, 1)
        XCTAssertEqual(snapshot.networkFetchCount, 0)
        XCTAssertEqual(snapshot.cacheServedByteCount, Int64(data.count))
        XCTAssertEqual(snapshot.cacheHitRate, 1.0, accuracy: 0.0001)
    }

    func testURLCacheHitIsReportedWithoutTouchingNetworkFetcher() async {
        let rootDirectoryURL = makeTemporaryDirectory()
        let urlCache = makeURLCache()
        let data = Data("cached-response".utf8)
        let url = URL(string: "https://example.com/banner.webp")!
        let request = URLRequest(
            url: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 30
        )
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        urlCache.storeCachedResponse(
            CachedURLResponse(response: response, data: data),
            for: request
        )

        let cache = FlowImageCache(
            rootDirectoryURL: rootDirectoryURL,
            urlCache: urlCache,
            fetchImageData: { _ in nil }
        )

        let cachedData = await cache.data(for: url)
        let snapshot = await cache.diagnosticsSnapshot()

        XCTAssertEqual(cachedData, data)
        XCTAssertEqual(snapshot.trackedRequestCount, 1)
        XCTAssertEqual(snapshot.urlCacheHitCount, 1)
        XCTAssertEqual(snapshot.cacheHitCount, 1)
        XCTAssertEqual(snapshot.networkFetchCount, 0)
        XCTAssertEqual(snapshot.cacheServedByteCount, Int64(data.count))
        XCTAssertEqual(snapshot.cacheHitRate, 1.0, accuracy: 0.0001)
    }

    func testPrefetchWarmsCacheWithoutChangingDiagnosticsUntilTrackedLoad() async {
        let rootDirectoryURL = makeTemporaryDirectory()
        let urlCache = makeURLCache()
        let data = makePNGData()
        let cache = FlowImageCache(
            rootDirectoryURL: rootDirectoryURL,
            urlCache: urlCache,
            fetchImageData: { _ in data }
        )
        let url = URL(string: "https://example.com/prefetch.png")!

        await cache.prefetch(urls: [url])
        let snapshotAfterPrefetch = await cache.diagnosticsSnapshot()
        let image = await cache.image(for: url)
        let snapshotAfterTrackedLoad = await cache.diagnosticsSnapshot()

        XCTAssertEqual(snapshotAfterPrefetch, FlowMediaCacheDiagnostics())
        XCTAssertNotNil(image)
        XCTAssertEqual(snapshotAfterTrackedLoad.trackedRequestCount, 1)
        XCTAssertEqual(snapshotAfterTrackedLoad.imageMemoryHitCount, 1)
        XCTAssertEqual(snapshotAfterTrackedLoad.cacheHitRate, 1.0, accuracy: 0.0001)
    }

    func testGIFURLsDecodeToStaticImages() async {
        let rootDirectoryURL = makeTemporaryDirectory()
        let urlCache = makeURLCache()
        let data = makeGIFData()
        let cache = FlowImageCache(
            rootDirectoryURL: rootDirectoryURL,
            urlCache: urlCache,
            fetchImageData: { _ in data }
        )
        let url = URL(string: "https://example.com/animated.gif")!

        let image = await cache.image(for: url)

        XCTAssertNotNil(image)
        XCTAssertNil(image?.images)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
        XCTAssertGreaterThan(image?.size.height ?? 0, 0)
    }

    func testResetDiagnosticsClearsSessionMetrics() async {
        let rootDirectoryURL = makeTemporaryDirectory()
        let urlCache = makeURLCache()
        let data = Data("network".utf8)
        let cache = FlowImageCache(
            rootDirectoryURL: rootDirectoryURL,
            urlCache: urlCache,
            fetchImageData: { _ in data }
        )
        let url = URL(string: "https://example.com/reset.jpg")!

        _ = await cache.data(for: url)
        let snapshotBeforeReset = await cache.diagnosticsSnapshot()
        await cache.resetDiagnostics()
        let snapshotAfterReset = await cache.diagnosticsSnapshot()

        XCTAssertEqual(snapshotBeforeReset.trackedRequestCount, 1)
        XCTAssertEqual(snapshotBeforeReset.networkFetchCount, 1)
        XCTAssertEqual(snapshotAfterReset, FlowMediaCacheDiagnostics())
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeURLCache() -> URLCache {
        URLCache(
            memoryCapacity: 2 * 1_024 * 1_024,
            diskCapacity: 2 * 1_024 * 1_024,
            diskPath: nil
        )
    }

    private func makePNGData() -> Data {
        Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAAaADAAQAAAABAAAAAQAAAAD5Ip3+AAAADElEQVQIHWNg+P8fAAMBAf8kN8l+AAAAAElFTkSuQmCC"
        ) ?? Data([0x89, 0x50, 0x4E, 0x47])
    }

    private func makeGIFData() -> Data {
        Data(
            base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="
        ) ?? Data([0x47, 0x49, 0x46])
    }
}
