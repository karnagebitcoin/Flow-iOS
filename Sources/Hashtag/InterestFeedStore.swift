import Foundation

enum InterestTopic: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case news
    case sports
    case entertainment
    case finance
    case business
    case politics
    case science
    case space
    case outdoors
    case gaming
    case animals
    case technology
    case travel
    case food
    case music
    case health

    var id: String { rawValue }

    var title: String {
        switch self {
        case .news: return "News"
        case .sports: return "Sports"
        case .entertainment: return "Entertainment"
        case .finance: return "Finance"
        case .business: return "Business"
        case .politics: return "Politics"
        case .science: return "Science"
        case .space: return "Space"
        case .outdoors: return "Outdoors"
        case .gaming: return "Gaming"
        case .animals: return "Animals"
        case .technology: return "Technology"
        case .travel: return "Travel"
        case .food: return "Food"
        case .music: return "Music"
        case .health: return "Health"
        }
    }

    var iconName: String {
        switch self {
        case .news: return "newspaper"
        case .sports: return "sportscourt"
        case .entertainment: return "sparkles.tv"
        case .finance: return "chart.line.uptrend.xyaxis"
        case .business: return "briefcase"
        case .politics: return "building.columns"
        case .science: return "atom"
        case .space: return "moon.stars"
        case .outdoors: return "mountain.2"
        case .gaming: return "gamecontroller"
        case .animals: return "pawprint"
        case .technology: return "desktopcomputer"
        case .travel: return "airplane"
        case .food: return "fork.knife"
        case .music: return "music.note"
        case .health: return "heart.text.square"
        }
    }

    var hashtags: [String] {
        switch self {
        case .news:
            return ["news", "breakingnews", "worldnews", "headlines", "currentevents"]
        case .sports:
            return ["sports", "football", "soccer", "basketball", "formula1"]
        case .entertainment:
            return ["entertainment", "movies", "tv", "popculture", "streaming"]
        case .finance:
            return ["finance", "investing", "markets", "stocks", "economy"]
        case .business:
            return ["business", "startups", "entrepreneurship", "leadership", "smallbusiness"]
        case .politics:
            return ["politics", "elections", "policy", "geopolitics", "government"]
        case .science:
            return ["science", "research", "physics", "biology", "chemistry"]
        case .space:
            return ["space", "astronomy", "nasa", "spacex", "rockets"]
        case .outdoors:
            return ["outdoors", "hiking", "camping", "nature", "climbing"]
        case .gaming:
            return ["gaming", "videogames", "pcgaming", "nintendo", "esports"]
        case .animals:
            return ["animals", "wildlife", "pets", "dogs", "cats"]
        case .technology:
            return ["technology", "tech", "ai", "programming", "software"]
        case .travel:
            return ["travel", "roadtrip", "wanderlust", "airlines", "hotels"]
        case .food:
            return ["food", "cooking", "recipes", "restaurants", "coffee"]
        case .music:
            return ["music", "nowplaying", "concerts", "vinyl", "indie"]
        case .health:
            return ["health", "wellness", "fitness", "nutrition", "longevity"]
        }
    }

    static func combinedHashtags(for selections: [InterestTopic]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for topic in selections {
            for hashtag in topic.hashtags {
                let normalized = normalizeHashtag(hashtag)
                guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
                ordered.append(normalized)
            }
        }

        return ordered
    }

    static func normalizeHashtag(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .lowercased()
    }
}

enum InterestFeedStoreError: LocalizedError {
    case invalidHashtag

    var errorDescription: String? {
        switch self {
        case .invalidHashtag:
            return "Enter a valid hashtag for the Interests feed."
        }
    }
}

@MainActor
final class InterestFeedStore: ObservableObject {
    static let shared = InterestFeedStore()

    @Published private(set) var hashtags: [String] = []
    @Published private(set) var selectedTopics: [InterestTopic] = []

    private let defaults: UserDefaults
    private let hashtagKeyPrefix = "flow.interestHashtags"
    private let topicKeyPrefix = "flow.interestTopics"
    private let legacyHashtagKeyPrefix = "x21.interestHashtags"
    private let legacyTopicKeyPrefix = "x21.interestTopics"
    private var accountPubkey: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func configure(accountPubkey: String?) {
        let normalized = normalizePubkey(accountPubkey)
        guard normalized != self.accountPubkey else { return }

        self.accountPubkey = normalized
        hashtags = loadHashtags(for: normalized)
        selectedTopics = loadTopics(for: normalized)
    }

    func seedFromOnboarding(_ topics: [InterestTopic]) {
        let normalizedTopics = normalizeTopics(topics)
        selectedTopics = normalizedTopics
        hashtags = InterestTopic.combinedHashtags(for: normalizedTopics)
        persistCurrentState()
    }

    func setHashtags(_ hashtags: [String]) {
        self.hashtags = normalizedUniqueHashtags(hashtags)
        persistCurrentState()
    }

    func addHashtag(_ rawValue: String) throws {
        let normalized = InterestTopic.normalizeHashtag(rawValue)
        guard !normalized.isEmpty else {
            throw InterestFeedStoreError.invalidHashtag
        }
        hashtags = normalizedUniqueHashtags(hashtags + [normalized])
        persistCurrentState()
    }

    func removeHashtag(_ hashtag: String) {
        let normalized = InterestTopic.normalizeHashtag(hashtag)
        guard !normalized.isEmpty else { return }
        hashtags.removeAll { $0 == normalized }
        persistCurrentState()
    }

    private func loadHashtags(for accountPubkey: String?) -> [String] {
        let key = hashtagsKey(for: accountPubkey)
        if let stored = defaults.stringArray(forKey: key) {
            return normalizedUniqueHashtags(stored)
        }

        let legacyKey = legacyHashtagsKey(for: accountPubkey)
        guard let stored = defaults.stringArray(forKey: legacyKey) else { return [] }
        let migrated = normalizedUniqueHashtags(stored)
        defaults.set(migrated, forKey: key)
        return migrated
    }

    private func loadTopics(for accountPubkey: String?) -> [InterestTopic] {
        let key = topicsKey(for: accountPubkey)
        if let stored = defaults.stringArray(forKey: key) {
            return normalizeTopics(stored.compactMap(InterestTopic.init(rawValue:)))
        }

        let legacyKey = legacyTopicsKey(for: accountPubkey)
        guard let stored = defaults.stringArray(forKey: legacyKey) else { return [] }
        let migrated = normalizeTopics(stored.compactMap(InterestTopic.init(rawValue:)))
        defaults.set(migrated.map(\.rawValue), forKey: key)
        return migrated
    }

    private func persistCurrentState() {
        let hashtagKey = hashtagsKey(for: accountPubkey)
        let topicKey = topicsKey(for: accountPubkey)
        defaults.set(hashtags, forKey: hashtagKey)
        defaults.set(selectedTopics.map(\.rawValue), forKey: topicKey)
    }

    private func hashtagsKey(for accountPubkey: String?) -> String {
        "\(hashtagKeyPrefix).\(accountPubkey ?? "anonymous")"
    }

    private func topicsKey(for accountPubkey: String?) -> String {
        "\(topicKeyPrefix).\(accountPubkey ?? "anonymous")"
    }

    private func legacyHashtagsKey(for accountPubkey: String?) -> String {
        "\(legacyHashtagKeyPrefix).\(accountPubkey ?? "anonymous")"
    }

    private func legacyTopicsKey(for accountPubkey: String?) -> String {
        "\(legacyTopicKeyPrefix).\(accountPubkey ?? "anonymous")"
    }

    private func normalizePubkey(_ value: String?) -> String? {
        let normalized = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizedUniqueHashtags(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for value in values {
            let normalized = InterestTopic.normalizeHashtag(value)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }

        return ordered
    }

    private func normalizeTopics(_ values: [InterestTopic]) -> [InterestTopic] {
        var seen = Set<InterestTopic>()
        var ordered: [InterestTopic] = []

        for value in values where seen.insert(value).inserted {
            ordered.append(value)
        }

        return ordered
    }
}
