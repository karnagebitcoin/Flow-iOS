import Foundation

struct HashtagRoute: Identifiable, Hashable {
    let hashtag: String
    let seedItems: [FeedItem]

    init(hashtag: String, seedItems: [FeedItem] = []) {
        self.hashtag = hashtag
        self.seedItems = seedItems
    }

    var normalizedHashtag: String {
        NostrEvent.normalizedHashtagValue(hashtag)
    }

    var id: String {
        normalizedHashtag
    }
}

func matchingHashtagSeedItems(
    hashtag: String,
    from sourceItems: [FeedItem],
    limit: Int = 24
) -> [FeedItem] {
    let normalizedHashtag = NostrEvent.normalizedHashtagValue(hashtag)
    guard !normalizedHashtag.isEmpty else { return [] }

    var itemsByID: [String: FeedItem] = [:]

    for item in sourceItems {
        let canonicalItem = item.canonicalDisplayItem
        guard canonicalItem.displayEvent.containsHashtag(normalizedHashtag) else { continue }
        itemsByID[canonicalItem.id.lowercased()] = canonicalItem
    }

    return itemsByID.values
        .sorted { lhs, rhs in
            if lhs.event.createdAt == rhs.event.createdAt {
                return lhs.id.lowercased() > rhs.id.lowercased()
            }
            return lhs.event.createdAt > rhs.event.createdAt
        }
        .prefix(limit)
        .map { $0 }
}
