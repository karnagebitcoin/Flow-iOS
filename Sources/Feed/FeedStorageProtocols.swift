import Foundation

protocol TimelineEventCaching: Actor, Sendable {
    func events(
        for key: String,
        fetcher: @escaping @Sendable () async throws -> [NostrEvent]
    ) async throws -> [NostrEvent]
}

protocol SeenEventStoring: Actor, Sendable {
    func store(events: [NostrEvent])
    func storeRecentFeed(key: String, events: [NostrEvent])
    func recentFeed(key: String) -> [NostrEvent]?
    func events(ids: [String]) -> [String: NostrEvent]
}

protocol FollowListSnapshotStoring: Actor, Sendable {
    func cachedSnapshot(pubkey: String, maxAge: TimeInterval?) async -> FollowListSnapshot?
    func storeSnapshot(_ snapshot: FollowListSnapshot, for pubkey: String) async
}

extension FollowListSnapshotStoring {
    func cachedSnapshot(pubkey: String) async -> FollowListSnapshot? {
        await cachedSnapshot(pubkey: pubkey, maxAge: nil)
    }
}

protocol ProfileRelayHintCaching: Actor, Sendable {
    func storeHints(_ hintsByPubkey: [String: [URL]])
    func prioritizedRelayURLs(for pubkeys: [String], baseRelayURLs: [URL]) -> [URL]
}

protocol ProfileCaching: Actor, Sendable {
    func resolve(
        pubkeys: [String],
        ignoringKnownMisses: Bool
    ) async -> (hits: [String: NostrProfile], missing: [String])
    func cachedProfile(pubkey: String) async -> NostrProfile?
    func cachedProfiles(pubkeys: [String]) async -> [String: NostrProfile]
    func store(profiles newProfiles: [String: NostrProfile], missed: [String]) async
    func setPriorityPubkeys(_ pubkeys: Set<String>)
}
