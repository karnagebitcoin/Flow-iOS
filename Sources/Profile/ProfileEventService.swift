import Foundation

struct ProfileMetadataSnapshot: Sendable {
    let content: String
    let tags: [[String]]

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
    private let relayClient: NostrRelayClient

    init(relayClient: NostrRelayClient = NostrRelayClient()) {
        self.relayClient = relayClient
    }

    func fetchProfileMetadataSnapshot(relayURL: URL, pubkey: String) async throws -> ProfileMetadataSnapshot? {
        guard let event = try await fetchLatestReplaceableEvent(
            relayURL: relayURL,
            authorPubkey: pubkey,
            kind: 0,
            limit: 20
        ) else {
            return nil
        }

        return ProfileMetadataSnapshot(content: event.content, tags: event.tags)
    }

    func fetchMuteListSnapshot(relayURL: URL, pubkey: String) async throws -> MuteListSnapshot? {
        guard let event = try await fetchLatestReplaceableEvent(
            relayURL: relayURL,
            authorPubkey: pubkey,
            kind: 10000,
            limit: 20
        ) else {
            return nil
        }

        return MuteListSnapshot(content: event.content, tags: event.tags)
    }

    private func fetchLatestReplaceableEvent(
        relayURL: URL,
        authorPubkey: String,
        kind: Int,
        limit: Int
    ) async throws -> NostrEvent? {
        let filter = NostrFilter(
            authors: [authorPubkey],
            kinds: [kind],
            limit: limit
        )

        let events = try await relayClient.fetchEvents(
            relayURL: relayURL,
            filter: filter,
            timeout: 10
        )

        return events
            .filter { $0.kind == kind }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id > rhs.id
                }
                return lhs.createdAt > rhs.createdAt
            }
            .first
    }
}
