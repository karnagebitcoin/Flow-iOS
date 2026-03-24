import Foundation

struct FeedKindFilterOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let kinds: [Int]
}

enum FeedKindFilters {
    static let shortTextNote = 1
    static let repost = 6
    static let highlights = 9802
    static let picture = 20
    static let video = 21
    static let shortVideo = 22
    static let poll = 1068
    static let legacyZapPoll = 6969
    static let comment = 1111
    static let voice = 1222
    static let voiceComment = 1244
    static let longFormArticle = 30023
    static let relayReview = 31987
    static let musicTrack = 36787

    static let pollKinds = [poll, legacyZapPoll]

    static let options: [FeedKindFilterOption] = [
        FeedKindFilterOption(id: "posts", title: "Posts", kinds: [shortTextNote, comment]),
        FeedKindFilterOption(id: "reposts", title: "Reposts", kinds: [repost]),
        FeedKindFilterOption(id: "articles", title: "Articles", kinds: [longFormArticle]),
        FeedKindFilterOption(id: "polls", title: "Polls", kinds: pollKinds),
        FeedKindFilterOption(id: "voice", title: "Voice Posts", kinds: [voice, voiceComment]),
        FeedKindFilterOption(id: "photos", title: "Photo Posts", kinds: [picture]),
        FeedKindFilterOption(id: "videos", title: "Video Posts", kinds: [video, shortVideo])
    ]

    static let allOptionKinds = Array(Set(options.flatMap(\.kinds))).sorted()

    static let supportedKinds: [Int] = [
        shortTextNote,
        repost,
        highlights,
        picture,
        video,
        shortVideo,
        poll,
        legacyZapPoll,
        comment,
        voice,
        voiceComment,
        longFormArticle,
        relayReview,
        musicTrack
    ]

    static func normalizedKinds(_ kinds: [Int]) -> [Int] {
        let uniqueKinds = Array(Set(kinds))
        if uniqueKinds.isEmpty {
            return supportedKinds
        }

        let supportedSet = Set(supportedKinds)
        let orderedSupportedKinds = supportedKinds.filter { uniqueKinds.contains($0) }
        let extraKinds = uniqueKinds
            .filter { !supportedSet.contains($0) }
            .sorted()
        let normalized = orderedSupportedKinds + extraKinds
        return normalized.isEmpty ? supportedKinds : normalized
    }

    static func isSameSelection(_ lhs: [Int], _ rhs: [Int]) -> Bool {
        Set(lhs) == Set(rhs)
    }
}
