import Foundation

enum ReactionBonusTag {
    static let tagName = "reaction_bonus"
    static let maximumBonusCount = 10_000

    static func normalizedBonusCount(_ value: Int) -> Int {
        min(max(value, 0), maximumBonusCount)
    }

    static func bonusTag(for bonusCount: Int) -> [String]? {
        let normalized = normalizedBonusCount(bonusCount)
        guard normalized > 0 else { return nil }
        return [tagName, String(normalized)]
    }

    static func bonusCount(in tags: [[String]]) -> Int {
        for tag in tags {
            guard tag.count >= 2 else { continue }
            guard tag[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == tagName else {
                continue
            }
            return normalizedBonusCount(Int(tag[1]) ?? 0)
        }

        return 0
    }
}
