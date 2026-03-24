import Foundation

struct HomeFeedFilterDefaults: Sendable {
    let showKinds: [Int]
    let mediaOnly: Bool
}

final class HomeFeedFilterStore: @unchecked Sendable {
    static let shared = HomeFeedFilterStore()

    private let defaults: UserDefaults
    private let showKindsKey = "flow.home.showKinds"
    private let showKindsVersionKey = "flow.home.showKindsVersion"
    private let mediaOnlyKey = "flow.home.mediaOnly"
    private let legacyShowKindsKey = "x21.home.showKinds"
    private let legacyShowKindsVersionKey = "x21.home.showKindsVersion"
    private let legacyMediaOnlyKey = "x21.home.mediaOnly"
    private let showKindsVersion = 2

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadDefaults() -> HomeFeedFilterDefaults {
        let storedKinds = (defaults.array(forKey: showKindsKey) as? [Int])
            ?? (defaults.array(forKey: legacyShowKindsKey) as? [Int])
        let migratedKinds: [Int]

        if let storedKinds {
            var kinds = storedKinds
            let storedVersion: Int
            if defaults.object(forKey: showKindsVersionKey) != nil {
                storedVersion = defaults.integer(forKey: showKindsVersionKey)
            } else {
                storedVersion = defaults.integer(forKey: legacyShowKindsVersionKey)
            }

            if storedVersion < 1 {
                kinds.append(contentsOf: [FeedKindFilters.video, FeedKindFilters.shortVideo])
            }
            if storedVersion < 2 && kinds.contains(FeedKindFilters.poll) {
                kinds.append(FeedKindFilters.legacyZapPoll)
            }
            migratedKinds = FeedKindFilters.normalizedKinds(kinds)
        } else {
            migratedKinds = FeedKindFilters.supportedKinds
        }

        defaults.set(migratedKinds, forKey: showKindsKey)
        defaults.set(showKindsVersion, forKey: showKindsVersionKey)

        let mediaOnly: Bool
        if defaults.object(forKey: mediaOnlyKey) == nil {
            if defaults.object(forKey: legacyMediaOnlyKey) == nil {
                mediaOnly = false
            } else {
                mediaOnly = defaults.bool(forKey: legacyMediaOnlyKey)
            }
        } else {
            mediaOnly = defaults.bool(forKey: mediaOnlyKey)
        }

        defaults.set(mediaOnly, forKey: mediaOnlyKey)

        return HomeFeedFilterDefaults(showKinds: migratedKinds, mediaOnly: mediaOnly)
    }

    func saveDefaults(showKinds: [Int], mediaOnly: Bool) {
        let normalizedKinds = FeedKindFilters.normalizedKinds(showKinds)
        defaults.set(normalizedKinds, forKey: showKindsKey)
        defaults.set(showKindsVersion, forKey: showKindsVersionKey)
        defaults.set(mediaOnly, forKey: mediaOnlyKey)
    }
}
