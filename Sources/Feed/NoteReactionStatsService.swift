import Foundation

@MainActor
final class NoteReactionStatsService: ObservableObject {
    static let shared = NoteReactionStatsService()

    struct OptimisticToggleState {
        let previousReaction: NoteReaction?
        let optimisticReactionID: String?
    }

    @Published private(set) var statsByEventID: [String: NoteReactionStats] = [:]
    @Published private(set) var publishingEventIDs = Set<String>()

    private struct PendingRequest {
        let eventID: String
        let relayURL: URL
    }

    private let relayClient: any NostrRelayEventFetching
    private let store: NoteReactionStatsStore

    private let fetchDebounceNanos: UInt64 = 40_000_000
    private let persistDebounceNanos: UInt64 = 80_000_000
    private let batchMaxNotes = 60
    private let optimisticReactionPrefix = "optimistic-reaction-"
    private let statsFreshnessInterval: TimeInterval = 45
    private let fetchRetryCooldownInterval: TimeInterval = 15

    private var hydratedEventIDs = Set<String>()
    private var pendingRequests: [String: PendingRequest] = [:]
    private var pendingPersistEventIDs = Set<String>()
    private var suppressedReactionIDs = Set<String>()
    private var lastFetchAttemptByRequestKey: [String: Date] = [:]

    private var fetchTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?

    init(
        relayClient: any NostrRelayEventFetching = NostrRelayClient(),
        store: NoteReactionStatsStore = .shared
    ) {
        self.relayClient = relayClient
        self.store = store
    }

    func prefetch(events: [NostrEvent], relayURL: URL) {
        let noteIDs = events.map(\.id)
        guard !noteIDs.isEmpty else { return }

        Task { @MainActor [weak self] in
            await self?.prepareAndQueue(noteIDs: noteIDs, relayURL: relayURL)
        }
    }

    func prefetch(events: [NostrEvent], relayURLs: [URL]) {
        let noteIDs = events.map(\.id)
        guard !noteIDs.isEmpty else { return }

        let normalizedRelayURLs = normalizedRelayTargets(relayURLs)
        guard !normalizedRelayURLs.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            for relayURL in normalizedRelayURLs {
                await self.prepareAndQueue(noteIDs: noteIDs, relayURL: relayURL)
            }
        }
    }

    func reactionCount(for eventID: String) -> Int {
        statsByEventID[normalizedEventID(eventID)]?.reactions.reduce(0) { partialResult, reaction in
            partialResult + reaction.totalWeight
        } ?? 0
    }

    func currentUserReaction(for eventID: String, currentPubkey: String?) -> NoteReaction? {
        guard let currentPubkey = normalizePubkey(currentPubkey) else { return nil }
        return statsByEventID[normalizedEventID(eventID)]?.reactions.first(where: {
            normalizePubkey($0.pubkey) == currentPubkey
        })
    }

    func isReactedByCurrentUser(for eventID: String, currentPubkey: String?) -> Bool {
        currentUserReaction(for: eventID, currentPubkey: currentPubkey) != nil
    }

    func isPublishingReaction(for eventID: String) -> Bool {
        publishingEventIDs.contains(normalizedEventID(eventID))
    }

    func beginPublishingReaction(for eventID: String) -> Bool {
        let normalizedEventID = normalizedEventID(eventID)
        guard !normalizedEventID.isEmpty else { return false }
        guard !publishingEventIDs.contains(normalizedEventID) else { return false }
        publishingEventIDs.insert(normalizedEventID)
        return true
    }

    func endPublishingReaction(for eventID: String) {
        publishingEventIDs.remove(normalizedEventID(eventID))
    }

    func applyOptimisticToggle(
        for eventID: String,
        currentPubkey: String?,
        bonusCount: Int = 0
    ) -> OptimisticToggleState? {
        let normalizedTargetEventID = normalizedEventID(eventID)
        guard !normalizedTargetEventID.isEmpty,
              let normalizedCurrentPubkey = normalizePubkey(currentPubkey) else {
            return nil
        }

        let previousReaction = currentUserReaction(
            for: normalizedTargetEventID,
            currentPubkey: normalizedCurrentPubkey
        )

        var stats = statsByEventID[normalizedTargetEventID] ?? NoteReactionStats()
        let now = Int(Date().timeIntervalSince1970)

        if let previousReaction {
            suppressedReactionIDs.insert(normalizedEventID(previousReaction.id))
            removeReaction(id: previousReaction.id, from: &stats)
            if ReactionBonusTag.normalizedBonusCount(bonusCount) == 0 {
                stats.updatedAt = now
                statsByEventID[normalizedTargetEventID] = stats
                return OptimisticToggleState(previousReaction: previousReaction, optimisticReactionID: nil)
            }
        }

        let optimisticReactionID = "\(optimisticReactionPrefix)\(UUID().uuidString.lowercased())"
        removeOptimisticReactions(for: normalizedCurrentPubkey, from: &stats)
        upsertReaction(
            NoteReaction(
                id: optimisticReactionID,
                pubkey: normalizedCurrentPubkey,
                createdAt: now,
                emoji: "+",
                bonusCount: bonusCount
            ),
            in: &stats
        )
        stats.updatedAt = now
        statsByEventID[normalizedTargetEventID] = stats
        return OptimisticToggleState(previousReaction: nil, optimisticReactionID: optimisticReactionID)
    }

    func rollbackOptimisticToggle(for eventID: String, snapshot: OptimisticToggleState?) {
        guard let snapshot else { return }

        let normalizedTargetEventID = normalizedEventID(eventID)
        guard !normalizedTargetEventID.isEmpty else { return }

        var stats = statsByEventID[normalizedTargetEventID] ?? NoteReactionStats()
        if let optimisticReactionID = snapshot.optimisticReactionID {
            removeReaction(id: optimisticReactionID, from: &stats)
        }
        if let previousReaction = snapshot.previousReaction {
            suppressedReactionIDs.remove(normalizedEventID(previousReaction.id))
            upsertReaction(previousReaction, in: &stats)
        }
        stats.updatedAt = Int(Date().timeIntervalSince1970)
        statsByEventID[normalizedTargetEventID] = stats
    }

    func registerPublishedReaction(_ event: NostrEvent, targetEventID: String) {
        let normalizedTargetEventID = normalizedEventID(targetEventID)
        guard !normalizedTargetEventID.isEmpty else { return }

        suppressedReactionIDs.remove(normalizedEventID(event.id))
        let touchedIDs = mergeReactionEvents(
            [event],
            trackedEventIDs: Set([normalizedTargetEventID])
        )
        guard !touchedIDs.isEmpty else { return }

        let now = Int(Date().timeIntervalSince1970)
        for eventID in touchedIDs {
            var stats = statsByEventID[eventID] ?? NoteReactionStats()
            stats.updatedAt = now
            statsByEventID[eventID] = stats
        }
        schedulePersist(eventIDs: Array(touchedIDs))
    }

    func registerDeletedReaction(reactionID: String, targetEventID: String) {
        let normalizedTargetEventID = normalizedEventID(targetEventID)
        let normalizedReactionID = normalizedEventID(reactionID)
        guard !normalizedTargetEventID.isEmpty, !normalizedReactionID.isEmpty else { return }

        suppressedReactionIDs.insert(normalizedReactionID)
        var stats = statsByEventID[normalizedTargetEventID] ?? NoteReactionStats()
        let priorReactionCount = stats.reactions.count
        let removedReactionID = stats.reactionIDs.remove(normalizedReactionID) != nil
        stats.reactions.removeAll { normalizedEventID($0.id) == normalizedReactionID }
        guard removedReactionID || stats.reactions.count != priorReactionCount else { return }

        stats.updatedAt = Int(Date().timeIntervalSince1970)
        statsByEventID[normalizedTargetEventID] = stats
        schedulePersist(eventIDs: [normalizedTargetEventID])
    }

    private func prepareAndQueue(noteIDs: [String], relayURL: URL) async {
        await hydrateFromStoreIfNeeded(noteIDs: noteIDs)

        let now = Date()
        let uniqueIDs = Set(noteIDs.map { normalizedEventID($0) }.filter { !$0.isEmpty })
        for noteID in uniqueIDs {
            guard shouldQueueFetch(for: noteID, relayURL: relayURL, now: now) else { continue }
            let key = pendingKey(eventID: noteID, relayURL: relayURL)
            pendingRequests[key] = PendingRequest(eventID: noteID, relayURL: relayURL)
            lastFetchAttemptByRequestKey[key] = now
        }

        scheduleBatchFetch()
    }

    private func hydrateFromStoreIfNeeded(noteIDs: [String]) async {
        let normalizedNoteIDs = Set(noteIDs.map { normalizedEventID($0) }.filter { !$0.isEmpty })
        let idsToHydrate = normalizedNoteIDs.filter { !hydratedEventIDs.contains($0) }
        guard !idsToHydrate.isEmpty else { return }

        idsToHydrate.forEach { hydratedEventIDs.insert($0) }
        let cached = await store.getMany(noteIDs: Array(idsToHydrate))

        for (eventID, stats) in cached {
            let existingUpdatedAt = statsByEventID[eventID]?.updatedAt ?? 0
            let incomingUpdatedAt = stats.updatedAt ?? 0
            if incomingUpdatedAt >= existingUpdatedAt {
                statsByEventID[eventID] = stats
            }
        }
    }

    private func scheduleBatchFetch() {
        guard fetchTask == nil else { return }
        fetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.fetchDebounceNanos)
            await self.flushBatchFetches()
        }
    }

    private func flushBatchFetches() async {
        fetchTask = nil
        guard !pendingRequests.isEmpty else { return }

        let batch = Array(pendingRequests.values.prefix(batchMaxNotes))
        batch.forEach { pendingRequests.removeValue(forKey: pendingKey(eventID: $0.eventID, relayURL: $0.relayURL)) }

        let requestsByRelay = Dictionary(grouping: batch, by: { $0.relayURL.absoluteString.lowercased() })
        struct RelayReactionFetchPlan {
            let relayURL: URL
            let eventIDs: [String]
            let since: Int?
            let reactionLimit: Int
        }

        struct RelayReactionFetchResult {
            let relayURL: URL
            let eventIDs: [String]
            let events: [NostrEvent]?
        }

        var plans: [RelayReactionFetchPlan] = []
        plans.reserveCapacity(requestsByRelay.count)

        for (_, relayRequests) in requestsByRelay {
            guard let relayURL = relayRequests.first?.relayURL else { continue }
            let eventIDs = Array(Set(relayRequests.map(\.eventID)))
            guard !eventIDs.isEmpty else { continue }

            let since = eventIDs.compactMap { statsByEventID[$0]?.updatedAt }.min()
            let reactionLimit = min(1_200, max(160, eventIDs.count * 24))
            plans.append(
                RelayReactionFetchPlan(
                    relayURL: relayURL,
                    eventIDs: eventIDs,
                    since: since,
                    reactionLimit: reactionLimit
                )
            )
        }

        let fetchResults = await withTaskGroup(of: RelayReactionFetchResult.self, returning: [RelayReactionFetchResult].self) { group in
            for plan in plans {
                group.addTask { [relayClient] in
                    let filter = NostrFilter(
                        kinds: [7],
                        limit: plan.reactionLimit,
                        since: plan.since,
                        tagFilters: ["e": plan.eventIDs]
                    )

                    do {
                        let reactionEvents = try await relayClient.fetchEvents(
                            relayURL: plan.relayURL,
                            filter: filter,
                            timeout: 12
                        )
                        return RelayReactionFetchResult(
                            relayURL: plan.relayURL,
                            eventIDs: plan.eventIDs,
                            events: reactionEvents
                        )
                    } catch {
                        return RelayReactionFetchResult(
                            relayURL: plan.relayURL,
                            eventIDs: plan.eventIDs,
                            events: nil
                        )
                    }
                }
            }

            var results: [RelayReactionFetchResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        for result in fetchResults {
            guard let reactionEvents = result.events else { continue }

            let touchedIDs = mergeReactionEvents(reactionEvents, trackedEventIDs: Set(result.eventIDs))
            let now = Int(Date().timeIntervalSince1970)

            var persistedIDs = touchedIDs
            for eventID in result.eventIDs {
                var stats = statsByEventID[eventID] ?? NoteReactionStats()
                stats.updatedAt = now
                statsByEventID[eventID] = stats
                persistedIDs.insert(eventID)
            }

            schedulePersist(eventIDs: Array(persistedIDs))
        }

        if !pendingRequests.isEmpty {
            scheduleBatchFetch()
        }
    }

    private func mergeReactionEvents(
        _ events: [NostrEvent],
        trackedEventIDs: Set<String>
    ) -> Set<String> {
        var touched = Set<String>()

        for event in events where event.kind == 7 {
            guard let lastEventReferenceID = event.lastEventReferenceID else { continue }
            let targetEventID = normalizedEventID(lastEventReferenceID)
            guard !targetEventID.isEmpty else { continue }
            guard trackedEventIDs.contains(targetEventID) else { continue }
            guard let emoji = normalizedReactionEmoji(from: event.content) else { continue }
            let normalizedReactionID = normalizedEventID(event.id)
            guard !suppressedReactionIDs.contains(normalizedReactionID) else { continue }
            let normalizedPubkey = normalizePubkey(event.pubkey) ?? event.pubkey.lowercased()

            var stats = statsByEventID[targetEventID] ?? NoteReactionStats()
            removeOptimisticReactions(for: normalizedPubkey, from: &stats)
            guard !stats.reactionIDs.contains(normalizedReactionID) else { continue }

            upsertReaction(
                NoteReaction(
                    id: normalizedReactionID,
                    pubkey: normalizedPubkey,
                    createdAt: event.createdAt,
                    emoji: emoji,
                    bonusCount: ReactionBonusTag.bonusCount(in: event.tags)
                ),
                in: &stats
            )

            statsByEventID[targetEventID] = stats
            touched.insert(targetEventID)
        }

        return touched
    }

    private func normalizedReactionEmoji(from content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Match web fallback: shortcode reactions become generic "+" if not directly resolvable.
        if trimmed.hasPrefix(":"), trimmed.hasSuffix(":"), trimmed.count > 2 {
            return "+"
        }

        return trimmed
    }

    private func schedulePersist(eventIDs: [String]) {
        guard !eventIDs.isEmpty else { return }
        pendingPersistEventIDs.formUnion(eventIDs)
        guard persistTask == nil else { return }

        persistTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.persistDebounceNanos)
            await self.flushPersist()
        }
    }

    private func flushPersist() async {
        persistTask = nil
        let ids = Array(pendingPersistEventIDs)
        pendingPersistEventIDs.removeAll()
        guard !ids.isEmpty else { return }

        var entries: [String: NoteReactionStats] = [:]
        for eventID in ids {
            guard let stats = statsByEventID[eventID] else { continue }
            entries[eventID] = stats
        }

        if !entries.isEmpty {
            await store.putMany(entries: entries)
        }

        if !pendingPersistEventIDs.isEmpty {
            schedulePersist(eventIDs: Array(pendingPersistEventIDs))
        }
    }

    private func pendingKey(eventID: String, relayURL: URL) -> String {
        "\(relayURL.absoluteString.lowercased())|\(normalizedEventID(eventID))"
    }

    private func normalizedRelayTargets(_ relayURLs: [URL]) -> [URL] {
        var seen = Set<String>()
        var ordered: [URL] = []

        for relayURL in relayURLs {
            let normalized = relayURL.absoluteString.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            ordered.append(relayURL)
        }

        return ordered
    }

    private func shouldQueueFetch(for eventID: String, relayURL: URL, now: Date) -> Bool {
        let key = pendingKey(eventID: eventID, relayURL: relayURL)
        if pendingRequests[key] != nil {
            return false
        }

        if let updatedAt = statsByEventID[eventID]?.updatedAt {
            let updatedDate = Date(timeIntervalSince1970: TimeInterval(updatedAt))
            if now.timeIntervalSince(updatedDate) < statsFreshnessInterval {
                return false
            }
        }

        if let lastAttempt = lastFetchAttemptByRequestKey[key],
           now.timeIntervalSince(lastAttempt) < fetchRetryCooldownInterval {
            return false
        }

        return true
    }

    private func removeReaction(id reactionID: String, from stats: inout NoteReactionStats) {
        let normalizedReactionID = normalizedEventID(reactionID)
        stats.reactionIDs.remove(normalizedReactionID)
        stats.reactions.removeAll { normalizedEventID($0.id) == normalizedReactionID }
    }

    private func removeOptimisticReactions(for pubkey: String, from stats: inout NoteReactionStats) {
        let reactionIDsToRemove = stats.reactions
            .filter { reaction in
                normalizePubkey(reaction.pubkey) == pubkey && isOptimisticReactionID(reaction.id)
            }
            .map(\.id)

        guard !reactionIDsToRemove.isEmpty else { return }
        for reactionID in reactionIDsToRemove {
            removeReaction(id: reactionID, from: &stats)
        }
    }

    private func upsertReaction(_ reaction: NoteReaction, in stats: inout NoteReactionStats) {
        removeReaction(id: reaction.id, from: &stats)
        stats.reactionIDs.insert(normalizedEventID(reaction.id))
        stats.reactions.append(reaction)
        stats.reactions.sort { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id > rhs.id
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func normalizedEventID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isOptimisticReactionID(_ value: String) -> Bool {
        normalizedEventID(value).hasPrefix(optimisticReactionPrefix)
    }

    private func normalizePubkey(_ value: String?) -> String? {
        let trimmed = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}
