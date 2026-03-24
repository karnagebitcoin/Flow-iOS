import Foundation

@MainActor
final class HashtagFavoritesStore: ObservableObject {
    static let shared = HashtagFavoritesStore()

    @Published private(set) var favoriteHashtags: [String] = []

    private let defaults: UserDefaults
    private let keyPrefix = "flow.favoriteHashtags"
    private let legacyKeyPrefix = "x21.favoriteHashtags"
    private var accountPubkey: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func configure(accountPubkey: String?) {
        let normalized = normalizePubkey(accountPubkey)
        guard normalized != self.accountPubkey else { return }

        self.accountPubkey = normalized
        favoriteHashtags = loadFavorites(for: normalized)
    }

    func isFavorite(_ hashtag: String) -> Bool {
        let normalized = normalizeHashtag(hashtag)
        guard !normalized.isEmpty else { return false }
        return favoriteHashtags.contains(normalized)
    }

    func toggleFavorite(_ hashtag: String) {
        let normalized = normalizeHashtag(hashtag)
        guard !normalized.isEmpty else { return }

        if favoriteHashtags.contains(normalized) {
            favoriteHashtags.removeAll { $0 == normalized }
        } else {
            favoriteHashtags.append(normalized)
        }

        favoriteHashtags = normalizedUniqueHashtags(favoriteHashtags)
        persistCurrentFavorites()
    }

    private func loadFavorites(for accountPubkey: String?) -> [String] {
        let key = defaultsKey(for: accountPubkey)
        if let stored = defaults.stringArray(forKey: key) {
            return normalizedUniqueHashtags(stored)
        }

        let legacyKey = legacyDefaultsKey(for: accountPubkey)
        guard let stored = defaults.stringArray(forKey: legacyKey) else { return [] }
        let migrated = normalizedUniqueHashtags(stored)
        defaults.set(migrated, forKey: key)
        return migrated
    }

    private func persistCurrentFavorites() {
        let key = defaultsKey(for: accountPubkey)
        defaults.set(favoriteHashtags, forKey: key)
    }

    private func defaultsKey(for accountPubkey: String?) -> String {
        "\(keyPrefix).\(accountPubkey ?? "anonymous")"
    }

    private func legacyDefaultsKey(for accountPubkey: String?) -> String {
        "\(legacyKeyPrefix).\(accountPubkey ?? "anonymous")"
    }

    private func normalizePubkey(_ value: String?) -> String? {
        let normalized = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizeHashtag(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .lowercased()
    }

    private func normalizedUniqueHashtags(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for value in values {
            let normalized = normalizeHashtag(value)
            guard !normalized.isEmpty else { continue }
            guard seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }

        return ordered
    }
}
