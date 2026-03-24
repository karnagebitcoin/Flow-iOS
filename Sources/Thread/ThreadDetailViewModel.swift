import Foundation

@MainActor
final class ThreadDetailViewModel: ObservableObject {
    @Published private(set) var rootItem: FeedItem
    @Published private(set) var replies: [FeedItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    let relayURL: URL
    let readRelayURLs: [URL]

    private let service: NostrFeedService
    private var hasLoadedInitialState = false
    private var itemHydrationTask: Task<Void, Never>?
    private static let fastThreadFetchTimeout: TimeInterval = 3
    private static let fastThreadRelayFetchMode: RelayFetchMode = .firstNonEmptyRelay

    init(
        rootItem: FeedItem,
        relayURL: URL,
        readRelayURLs: [URL]? = nil,
        service: NostrFeedService = NostrFeedService()
    ) {
        self.rootItem = rootItem
        let normalizedReadRelays = Self.normalizedRelayURLs(readRelayURLs ?? [relayURL])
        self.readRelayURLs = normalizedReadRelays.isEmpty ? [relayURL] : normalizedReadRelays
        self.relayURL = self.readRelayURLs.first ?? relayURL
        self.service = service
    }

    deinit {
        itemHydrationTask?.cancel()
    }

    var repliesHeaderText: String {
        if replies.isEmpty {
            return "Replies"
        }
        return "Replies (\(replies.count))"
    }

    func loadIfNeeded() async {
        guard !hasLoadedInitialState else { return }
        hasLoadedInitialState = true
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        itemHydrationTask?.cancel()
        itemHydrationTask = nil

        defer {
            isLoading = false
        }

        do {
            replies = try await service.fetchThreadReplies(
                relayURLs: readRelayURLs,
                rootEventID: rootItem.displayEventID,
                hydrationMode: .cachedProfilesOnly,
                fetchTimeout: Self.fastThreadFetchTimeout,
                relayFetchMode: Self.fastThreadRelayFetchMode
            )
            scheduleItemHydration(for: replies)
        } catch {
            if replies.isEmpty {
                errorMessage = "Couldn't load replies right now."
            } else {
                errorMessage = "Couldn't refresh replies."
            }
        }
    }

    func appendLocalReply(_ item: FeedItem) {
        guard item.event.id.lowercased() != rootItem.displayEventID.lowercased() else { return }
        guard !replies.contains(where: { $0.id.lowercased() == item.id.lowercased() }) else { return }
        replies.append(item)
        replies = Self.sortedReplies(replies)
    }

    private func scheduleItemHydration(for sourceItems: [FeedItem]) {
        itemHydrationTask?.cancel()

        let events = sourceItems.map(\.event)
        guard !events.isEmpty else { return }
        let relayTargets = readRelayURLs

        itemHydrationTask = Task { [weak self] in
            guard let self else { return }
            let hydrated = await self.service.buildFeedItems(
                relayURLs: relayTargets,
                events: events,
                hydrationMode: .full
            )
            guard !Task.isCancelled else { return }
            guard !hydrated.isEmpty else { return }

            await MainActor.run {
                self.mergeKeepingThreadOrder(itemsToMerge: hydrated)
            }
        }
    }

    private func mergeKeepingThreadOrder(itemsToMerge: [FeedItem]) {
        var byID = Dictionary(uniqueKeysWithValues: replies.map { ($0.id.lowercased(), $0) })
        for item in itemsToMerge {
            byID[item.id.lowercased()] = item
        }
        replies = Self.sortedReplies(Array(byID.values))
    }

    private static func sortedReplies(_ items: [FeedItem]) -> [FeedItem] {
        items.sorted { lhs, rhs in
            if lhs.event.createdAt == rhs.event.createdAt {
                return lhs.id.lowercased() < rhs.id.lowercased()
            }
            return lhs.event.createdAt < rhs.event.createdAt
        }
    }

    private static func normalizedRelayURLs(_ relayURLs: [URL]) -> [URL] {
        var seen = Set<String>()
        var ordered: [URL] = []

        for relayURL in relayURLs {
            let normalized = relayURL.absoluteString.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            ordered.append(relayURL)
        }

        return ordered
    }
}
