import LinkPresentation
import SwiftUI

struct WebsiteLinkCardView: View {
    private static let imageSize: CGFloat = 64

    @EnvironmentObject private var appSettings: AppSettingsStore
    let url: URL
    let backgroundColor: Color
    let borderColor: Color
    @StateObject private var loader: LinkMetadataLoader

    init(url: URL, backgroundColor: Color, borderColor: Color) {
        self.url = url
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        _loader = StateObject(wrappedValue: LinkMetadataLoader(url: url))
    }

    var body: some View {
        Link(destination: url) {
            HStack(alignment: .top, spacing: 10) {
                previewImageSlot

                VStack(alignment: .leading, spacing: 4) {
                    Text(FlowLayoutGuardrails.softWrapped(displayTitle))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appSettings.themePalette.foreground)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                        .redacted(reason: loader.hasResolvedMetadata ? [] : .placeholder)

                    Text(FlowLayoutGuardrails.softWrapped(displayURL, maxNonBreakingRunLength: 18))
                        .font(.caption)
                        .foregroundStyle(appSettings.themePalette.secondaryForeground)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                        .redacted(reason: loader.hasResolvedMetadata ? [] : .placeholder)

                    Text(FlowLayoutGuardrails.softWrapped(loader.hostDisplay, maxNonBreakingRunLength: 18))
                        .font(.caption2)
                        .foregroundStyle(appSettings.themePalette.secondaryForeground)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: Self.imageSize, alignment: .topLeading)

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .task(id: url) {
            await loader.startIfNeeded()
        }
        .onDisappear {
            loader.cancelPendingLoad()
        }
    }

    @ViewBuilder
    private var previewImageSlot: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholderImage
            }
        }
        .frame(width: Self.imageSize, height: Self.imageSize)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var placeholderImage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(appSettings.themePalette.secondaryFill)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            appSettings.themePalette.tertiaryFill.opacity(0.9),
                            appSettings.themePalette.secondaryFill.opacity(0.65)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "photo")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(appSettings.themePalette.secondaryForeground)
        }
    }

    private var displayTitle: String {
        loader.title ?? fallbackTitle
    }

    private var displayURL: String {
        loader.summary ?? fallbackURL
    }

    private var fallbackTitle: String {
        if let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
           !host.isEmpty {
            return host
        }
        return "Website preview"
    }

    private var fallbackURL: String {
        let absoluteString = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !absoluteString.isEmpty else { return loader.hostDisplay }
        if absoluteString.count > 90 {
            return String(absoluteString.prefix(87)) + "..."
        }
        return absoluteString
    }
}

private actor LinkPreviewLoadCoordinator {
    enum BeginDecision: Sendable, Equatable {
        case started
        case atCapacity
        case blockedByBackoff
    }

    enum Completion: Sendable, Equatable {
        case success
        case failure
        case cancelled
    }

    static let shared = LinkPreviewLoadCoordinator()

    private struct FailureEntry {
        var failureCount: Int
        var retryAfter: Date
    }

    private let maxConcurrentLoads = 2
    private let maxTrackedHosts = 256
    private var activeLoads = 0
    private var hostFailures: [String: FailureEntry] = [:]
    private var hostOrder: [String] = []

    func beginLoad(for url: URL, now: Date = Date()) -> BeginDecision {
        clearExpiredFailures(now: now)

        if let host = normalizedHost(for: url),
           let entry = hostFailures[host],
           entry.retryAfter > now {
            return .blockedByBackoff
        }

        guard activeLoads < maxConcurrentLoads else {
            return .atCapacity
        }

        activeLoads += 1
        return .started
    }

    func finishLoad(for url: URL, completion: Completion) {
        activeLoads = max(0, activeLoads - 1)

        guard let host = normalizedHost(for: url) else { return }

        switch completion {
        case .success:
            hostFailures.removeValue(forKey: host)
            hostOrder.removeAll { $0 == host }
        case .failure:
            let nextFailureCount = (hostFailures[host]?.failureCount ?? 0) + 1
            let multiplier = pow(2.0, Double(min(nextFailureCount - 1, 4)))
            let retryDelay = min(90 * multiplier, 30 * 60)
            hostFailures[host] = FailureEntry(
                failureCount: nextFailureCount,
                retryAfter: Date().addingTimeInterval(retryDelay)
            )
            hostOrder.removeAll { $0 == host }
            hostOrder.append(host)
            trimHostsIfNeeded()
        case .cancelled:
            break
        }
    }

    private func clearExpiredFailures(now: Date) {
        let expiredHosts = hostFailures.compactMap { host, entry in
            entry.retryAfter <= now ? host : nil
        }
        guard !expiredHosts.isEmpty else { return }

        let expiredSet = Set(expiredHosts)
        expiredHosts.forEach { hostFailures.removeValue(forKey: $0) }
        hostOrder.removeAll { expiredSet.contains($0) }
    }

    private func trimHostsIfNeeded() {
        while hostOrder.count > maxTrackedHosts {
            let removedHost = hostOrder.removeFirst()
            hostFailures.removeValue(forKey: removedHost)
        }
    }

    private func normalizedHost(for url: URL) -> String? {
        let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return host?.isEmpty == false ? host : nil
    }
}

@MainActor
private final class LinkMetadataLoader: ObservableObject {
    @Published var title: String?
    @Published var summary: String?
    @Published var image: UIImage?
    @Published private(set) var hasResolvedMetadata = false

    let hostDisplay: String
    private let url: URL
    private var metadataProvider: LPMetadataProvider?
    private var isLoading = false
    private static let metadataLoadTimeoutNanoseconds: UInt64 = 8_000_000_000
    private static let imageLoadTimeoutNanoseconds: UInt64 = 6_000_000_000

    private static let metadataCache: NSCache<NSURL, LPLinkMetadata> = {
        let cache = NSCache<NSURL, LPLinkMetadata>()
        cache.countLimit = 96
        return cache
    }()

    private static let imageCache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 24 * 1_024 * 1_024
        return cache
    }()

    init(url: URL) {
        self.url = url
        hostDisplay = url.host ?? url.absoluteString
    }

    func startIfNeeded() async {
        let cacheKey = url as NSURL
        if let cachedMetadata = Self.metadataCache.object(forKey: cacheKey) {
            apply(metadata: cachedMetadata)
            hasResolvedMetadata = true
            if let cachedImage = Self.imageCache.object(forKey: cacheKey) {
                image = cachedImage
            } else {
                await loadImageIfNeeded(metadata: cachedMetadata, cacheKey: cacheKey)
            }
            return
        }

        guard !isLoading else { return }

        var decision = await Self.coordinator.beginLoad(for: url)
        while decision == .atCapacity && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 200_000_000)
            decision = await Self.coordinator.beginLoad(for: url)
        }

        guard !Task.isCancelled else { return }
        guard decision == .started else { return }

        isLoading = true
        var completion: LinkPreviewLoadCoordinator.Completion = .failure
        defer {
            isLoading = false
            metadataProvider = nil
            let url = self.url
            Task {
                await Self.coordinator.finishLoad(for: url, completion: completion)
            }
        }

        let provider = LPMetadataProvider()
        metadataProvider = provider

        guard let metadata = await fetchMetadata(with: provider) else {
            completion = Task.isCancelled ? .cancelled : .failure
            if !Task.isCancelled {
                hasResolvedMetadata = true
            }
            return
        }

        guard !Task.isCancelled else {
            completion = .cancelled
            return
        }

        Self.metadataCache.setObject(metadata, forKey: cacheKey)
        apply(metadata: metadata)
        hasResolvedMetadata = true
        completion = .success
        await loadImageIfNeeded(metadata: metadata, cacheKey: cacheKey)
    }

    private func apply(metadata: LPLinkMetadata) {
        if let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            self.title = title
        }
        if let summary = metadata.url?.absoluteString,
           summary != url.absoluteString,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.summary = summary
        }
    }

    func cancelPendingLoad() {
        metadataProvider?.cancel()
    }

    private func fetchMetadata(with provider: LPMetadataProvider) async -> LPLinkMetadata? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<LPLinkMetadata?, Never>) in
                var didResume = false
                func finish(_ metadata: LPLinkMetadata?) {
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume(returning: metadata)
                }
                let timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: Self.metadataLoadTimeoutNanoseconds)
                    await MainActor.run {
                        provider.cancel()
                        finish(nil)
                    }
                }
                provider.startFetchingMetadata(for: url) { metadata, _ in
                    Task { @MainActor in
                        timeoutTask.cancel()
                        finish(metadata)
                    }
                }
            }
        } onCancel: {
            provider.cancel()
        }
    }

    private func loadImageIfNeeded(metadata: LPLinkMetadata, cacheKey: NSURL) async {
        if let cachedImage = Self.imageCache.object(forKey: cacheKey) {
            image = cachedImage
            return
        }
        guard let provider = metadata.imageProvider else { return }
        guard provider.canLoadObject(ofClass: UIImage.self) else { return }

        let loadedImage = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            var didResume = false
            func finish(_ image: UIImage?) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: image)
            }
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: Self.imageLoadTimeoutNanoseconds)
                await MainActor.run {
                    finish(nil)
                }
            }
            _ = provider.loadObject(ofClass: UIImage.self) { object, _ in
                let loadedImage = object as? UIImage
                Task { @MainActor in
                    timeoutTask.cancel()
                    finish(loadedImage)
                }
            }
        }
        guard let loadedImage, !Task.isCancelled else { return }

        Self.imageCache.setObject(
            loadedImage,
            forKey: cacheKey,
            cost: Self.imageMemoryCost(for: loadedImage)
        )
        image = loadedImage
    }

    private static let coordinator = LinkPreviewLoadCoordinator.shared

    private static func imageMemoryCost(for image: UIImage) -> Int {
        let scale = image.scale
        let width = Int(image.size.width * scale)
        let height = Int(image.size.height * scale)
        guard width > 0, height > 0 else { return 1 }
        return width * height * 4
    }
}

actor CustomEmojiImageLoader {
    static let shared = CustomEmojiImageLoader()

    func image(for url: URL) async -> UIImage? {
        await FlowImageCache.shared.image(for: url)
    }
}
