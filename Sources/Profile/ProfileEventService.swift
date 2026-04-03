import Foundation

struct ProfileMetadataSnapshot: Sendable {
    let content: String
    let tags: [[String]]
    let createdAt: Int?

    var jsonObject: [String: Any] {
        guard let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }
}

struct MuteListSnapshot: Sendable {
    let content: String
    let tags: [[String]]

    var publicMutedPubkeys: [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            guard let name = tag.first?.lowercased(), name == "p", tag.count > 1 else { return nil }
            let value = tag[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !value.isEmpty, seen.insert(value).inserted else { return nil }
            return value
        }
    }
}

struct ProfileEventService {
    private let relayClient: any NostrRelayEventFetching
    private let seenEventStore: any SeenEventStoring

    init(
        relayClient: any NostrRelayEventFetching = NostrRelayClient(),
        seenEventStore: any SeenEventStoring = SeenEventStore.shared
    ) {
        self.relayClient = relayClient
        self.seenEventStore = seenEventStore
    }

    func fetchProfileMetadataSnapshot(relayURL: URL, pubkey: String) async throws -> ProfileMetadataSnapshot? {
        try await fetchProfileMetadataSnapshot(relayURLs: [relayURL], pubkey: pubkey)
    }

    func fetchProfileMetadataSnapshot(relayURLs: [URL], pubkey: String) async throws -> ProfileMetadataSnapshot? {
        guard let event = try await fetchLatestReplaceableEvent(
            relayURLs: relayURLs,
            authorPubkey: pubkey,
            kind: 0,
            limit: 20
        ) else {
            return nil
        }

        return ProfileMetadataSnapshot(
            content: event.content,
            tags: event.tags,
            createdAt: event.createdAt
        )
    }

    func fetchMuteListSnapshot(relayURL: URL, pubkey: String) async throws -> MuteListSnapshot? {
        try await fetchMuteListSnapshot(relayURLs: [relayURL], pubkey: pubkey)
    }

    func fetchMuteListSnapshot(relayURLs: [URL], pubkey: String) async throws -> MuteListSnapshot? {
        guard let event = try await fetchLatestReplaceableEvent(
            relayURLs: relayURLs,
            authorPubkey: pubkey,
            kind: 10000,
            limit: 20
        ) else {
            return nil
        }

        return MuteListSnapshot(content: event.content, tags: event.tags)
    }

    private func fetchLatestReplaceableEvent(
        relayURLs: [URL],
        authorPubkey: String,
        kind: Int,
        limit: Int
    ) async throws -> NostrEvent? {
        let targets = normalizedRelayURLs(relayURLs)
        guard !targets.isEmpty else { return nil }

        let filter = NostrFilter(
            authors: [authorPubkey],
            kinds: [kind],
            limit: limit
        )

        let result = await withTaskGroup(
            of: (events: [NostrEvent]?, error: Error?).self,
            returning: (mergedEvents: [NostrEvent], successfulFetches: Int, firstError: Error?).self
        ) { group in
            for relayURL in targets {
                group.addTask {
                    do {
                        let events = try await relayClient.fetchEvents(
                            relayURL: relayURL,
                            filter: filter,
                            timeout: 10
                        )
                        return (events: events, error: nil)
                    } catch {
                        return (events: nil, error: error)
                    }
                }
            }

            var mergedEvents: [NostrEvent] = []
            var firstError: Error?
            var successfulFetches = 0

            for await item in group {
                if let events = item.events {
                    successfulFetches += 1
                    mergedEvents.append(contentsOf: events)
                } else if firstError == nil, let error = item.error {
                    firstError = error
                }
            }

            return (mergedEvents, successfulFetches, firstError)
        }

        if result.successfulFetches == 0, let firstError = result.firstError {
            throw firstError
        }

        let matchingEvents = result.mergedEvents.filter { $0.kind == kind }
        if !matchingEvents.isEmpty {
            await seenEventStore.store(events: matchingEvents)
        }

        return matchingEvents
            .filter { $0.kind == kind }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id > rhs.id
                }
                return lhs.createdAt > rhs.createdAt
            }
            .first
    }

    private func normalizedRelayURLs(_ relayURLs: [URL]) -> [URL] {
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
