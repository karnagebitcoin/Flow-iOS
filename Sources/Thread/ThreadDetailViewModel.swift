import Foundation

@MainActor
final class ThreadDetailViewModel: ObservableObject {
    @Published private(set) var rootItem: FeedItem
    @Published private(set) var replies: [FeedItem] = []
    @Published private(set) var noteActivityRows: [ActivityRow] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingNoteActivity = false
    @Published var errorMessage: String?
    @Published var noteActivityErrorMessage: String?

    let relayURL: URL
    let readRelayURLs: [URL]

    private let service: NostrFeedService
    private var hasLoadedInitialState = false
    private var hasLoadedNoteActivityState = false
    private var rootHydrationTask: Task<Void, Never>?
    private var itemHydrationTask: Task<Void, Never>?
    private static let fastThreadFetchTimeout: TimeInterval = 3
    private static let fastThreadRelayFetchMode: RelayFetchMode = .firstNonEmptyRelay
    private static let noteActivityFetchTimeout: TimeInterval = 8

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
        rootHydrationTask?.cancel()
        itemHydrationTask?.cancel()
    }

    var repliesHeaderText: String {
        if replies.isEmpty {
            return "Replies"
        }
        return "Replies (\(replies.count))"
    }

    var hasLoadedNoteActivity: Bool {
        hasLoadedNoteActivityState
    }

    private var muteFilterSnapshot: MuteFilterSnapshot {
        MuteStore.shared.filterSnapshot
    }

    func loadIfNeeded() async {
        guard !hasLoadedInitialState else { return }
        hasLoadedInitialState = true
        await refresh()
    }

    func loadNoteActivityIfNeeded() async {
        guard !hasLoadedNoteActivityState else { return }
        hasLoadedNoteActivityState = true
        await refreshNoteActivity()
    }

    func refresh(includeNoteActivity: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        rootHydrationTask?.cancel()
        itemHydrationTask?.cancel()
        rootHydrationTask = nil
        itemHydrationTask = nil

        defer {
            isLoading = false
        }

        scheduleRootHydration()

        do {
            replies = pruneMutedItems(try await service.fetchThreadReplies(
                relayURLs: readRelayURLs,
                rootEventID: rootItem.displayEventID,
                hydrationMode: .cachedProfilesOnly,
                fetchTimeout: Self.fastThreadFetchTimeout,
                relayFetchMode: Self.fastThreadRelayFetchMode,
                moderationSnapshot: muteFilterSnapshot
            ))
            scheduleItemHydration(for: replies)
        } catch {
            if replies.isEmpty {
                errorMessage = "Couldn't load replies right now."
            } else {
                errorMessage = "Couldn't refresh replies."
            }
        }

        if includeNoteActivity || hasLoadedNoteActivityState {
            await refreshNoteActivity()
        }
    }

    func refreshNoteActivity() async {
        guard !isLoadingNoteActivity else { return }
        isLoadingNoteActivity = true
        noteActivityErrorMessage = nil

        defer {
            isLoadingNoteActivity = false
        }

        do {
            noteActivityRows = try await service.fetchNoteActivityRows(
                relayURLs: readRelayURLs,
                rootEventID: rootItem.displayEventID,
                fetchTimeout: Self.noteActivityFetchTimeout,
                relayFetchMode: .allRelays,
                profileFetchTimeout: Self.noteActivityFetchTimeout,
                profileRelayFetchMode: .allRelays
            )
        } catch {
            if noteActivityRows.isEmpty {
                noteActivityErrorMessage = "Couldn't load reactions right now."
            } else {
                noteActivityErrorMessage = "Couldn't refresh reactions."
            }
        }
    }

    func appendLocalReply(_ item: FeedItem) {
        guard !pruneMutedItems([item]).isEmpty else { return }
        guard item.event.id.lowercased() != rootItem.displayEventID.lowercased() else { return }
        guard !replies.contains(where: { $0.id.lowercased() == item.id.lowercased() }) else { return }
        replies.append(item)
        replies = Self.sortedReplies(replies)
    }

    private func scheduleRootHydration() {
        let sourceEvent = rootItem.event
        let relayTargets = readRelayURLs

        rootHydrationTask = Task { [weak self] in
            guard let self else { return }

            await self.hydrateRootItem(
                sourceEvent: sourceEvent,
                relayURLs: relayTargets,
                hydrationMode: .cachedProfilesOnly
            )
            guard !Task.isCancelled else { return }

            await self.hydrateRootItem(
                sourceEvent: sourceEvent,
                relayURLs: relayTargets,
                hydrationMode: .full
            )
        }
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
                hydrationMode: .full,
                moderationSnapshot: self.muteFilterSnapshot
            )
            guard !Task.isCancelled else { return }
            guard !hydrated.isEmpty else { return }

            await MainActor.run {
                self.mergeKeepingThreadOrder(itemsToMerge: hydrated)
            }
        }
    }

    private func hydrateRootItem(
        sourceEvent: NostrEvent,
        relayURLs: [URL],
        hydrationMode: FeedItemHydrationMode
    ) async {
        let hydrated = await service.buildFeedItems(
            relayURLs: relayURLs,
            events: [sourceEvent],
            hydrationMode: hydrationMode
        )
        guard !Task.isCancelled, let hydratedRootItem = hydrated.first else { return }

        await MainActor.run {
            guard self.rootItem.event.id.lowercased() == sourceEvent.id.lowercased() else { return }
            self.rootItem = Self.mergedRootItem(current: self.rootItem, hydrated: hydratedRootItem)
        }
    }

    private func mergeKeepingThreadOrder(itemsToMerge: [FeedItem]) {
        var byID = Dictionary(uniqueKeysWithValues: replies.map { ($0.id.lowercased(), $0) })
        for item in itemsToMerge {
            byID[item.id.lowercased()] = item
        }
        replies = pruneMutedItems(Self.sortedReplies(Array(byID.values)))
    }

    private func pruneMutedItems(
        _ sourceItems: [FeedItem],
        snapshot: MuteFilterSnapshot? = nil
    ) -> [FeedItem] {
        let snapshot = snapshot ?? muteFilterSnapshot
        guard snapshot.hasAnyRules else { return sourceItems }

        return sourceItems.filter { item in
            !snapshot.shouldHideAny(in: item.moderationEvents)
        }
    }

    private static func sortedReplies(_ items: [FeedItem]) -> [FeedItem] {
        items.sorted { lhs, rhs in
            if lhs.event.createdAt == rhs.event.createdAt {
                return lhs.id.lowercased() < rhs.id.lowercased()
            }
            return lhs.event.createdAt < rhs.event.createdAt
        }
    }

    private static func mergedRootItem(current: FeedItem, hydrated: FeedItem) -> FeedItem {
        FeedItem(
            event: hydrated.event,
            profile: hydrated.profile ?? current.profile,
            displayEventOverride: hydrated.displayEventOverride ?? current.displayEventOverride,
            displayProfileOverride: hydrated.displayProfileOverride ?? current.displayProfileOverride,
            replyTargetEvent: hydrated.replyTargetEvent ?? current.replyTargetEvent,
            replyTargetProfile: hydrated.replyTargetProfile ?? current.replyTargetProfile
        )
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
