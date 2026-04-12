import Foundation

enum NostrPollKind {
    static let poll = 1_068
    static let legacyZapPoll = 6_969
    static let response = 1_018
}

enum NostrPollType: String, Hashable, Sendable {
    case singleChoice = "singlechoice"
    case multipleChoice = "multiplechoice"

    var allowsMultipleChoices: Bool {
        self == .multipleChoice
    }
}

enum NostrPollFormat: String, Hashable, Sendable {
    case nip88
    case legacyZap
}

struct NostrPollOption: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let imageURL: URL?
}

struct NostrPollMetadata: Hashable, Sendable {
    let format: NostrPollFormat
    let options: [NostrPollOption]
    let pollType: NostrPollType
    let relayURLs: [URL]
    let endsAt: Int?
    let minZapAmount: Int?
    let maxZapAmount: Int?

    init?(event: NostrEvent) {
        guard event.kind == NostrPollKind.poll else {
            return nil
        }

        var options: [NostrPollOption] = []
        var optionImageURLs: [String: URL] = [:]
        var relayURLs: [URL] = []
        var pollType: NostrPollType = .singleChoice
        var endsAt: Int?

        for tag in event.tags {
            guard let name = tag.first?.lowercased() else { continue }

            switch name {
            case "option", "poll_option":
                guard tag.count > 2 else { continue }
                let optionID = tag[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let optionLabel = tag[2].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !optionID.isEmpty, !optionLabel.isEmpty else { continue }
                options.append(
                    NostrPollOption(
                        id: optionID,
                        label: optionLabel,
                        imageURL: nil
                    )
                )
            case "option_image":
                guard tag.count > 2 else { continue }
                let optionID = tag[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !optionID.isEmpty,
                      let imageURL = Self.normalizedHTTPURL(from: tag[2]) else {
                    continue
                }
                optionImageURLs[optionID] = imageURL
            case "relay":
                guard tag.count > 1,
                      let relayURL = Self.normalizedWebSocketURL(from: tag[1]) else {
                    continue
                }
                let normalized = relayURL.absoluteString.lowercased()
                guard !relayURLs.contains(where: { $0.absoluteString.lowercased() == normalized }) else {
                    continue
                }
                relayURLs.append(relayURL)
            case "polltype":
                guard tag.count > 1 else { continue }
                pollType = NostrPollType(rawValue: tag[1].lowercased()) ?? .singleChoice
            case "endsat":
                guard tag.count > 1,
                      let timestamp = Int(tag[1].trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    continue
                }
                endsAt = timestamp
            default:
                continue
            }
        }

        let resolvedOptions = options.map { option in
            NostrPollOption(
                id: option.id,
                label: option.label,
                imageURL: optionImageURLs[option.id]
            )
        }
        guard !resolvedOptions.isEmpty else {
            return nil
        }

        self.format = .nip88
        self.options = resolvedOptions
        self.pollType = pollType
        self.relayURLs = relayURLs
        self.endsAt = endsAt
        self.minZapAmount = nil
        self.maxZapAmount = nil
    }

    var validOptionIDs: Set<String> {
        Set(options.map(\.id))
    }

    var isLegacyZapPoll: Bool {
        format == .legacyZap
    }

    private static func normalizedHTTPURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private static func normalizedWebSocketURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss" else {
            return nil
        }
        return url
    }
}

struct NostrPollResponse: Hashable, Sendable {
    let pubkey: String
    let createdAt: Int
    let selectedOptionIDs: [String]

    init?(
        event: NostrEvent,
        validOptionIDs: Set<String>,
        allowsMultipleChoices: Bool
    ) {
        guard event.kind == NostrPollKind.response else {
            return nil
        }

        let normalizedPubkey = event.pubkey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedPubkey.isEmpty else {
            return nil
        }

        var selectedOptionIDs: [String] = []
        var seen = Set<String>()

        for tag in event.tags {
            guard let name = tag.first?.lowercased(), name == "response", tag.count > 1 else {
                continue
            }

            let optionID = tag[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !optionID.isEmpty,
                  validOptionIDs.contains(optionID),
                  seen.insert(optionID).inserted else {
                continue
            }
            selectedOptionIDs.append(optionID)
        }

        guard !selectedOptionIDs.isEmpty else {
            return nil
        }
        if selectedOptionIDs.count > 1 && !allowsMultipleChoices {
            return nil
        }

        self.pubkey = normalizedPubkey
        self.createdAt = event.createdAt
        self.selectedOptionIDs = selectedOptionIDs
    }
}

struct NostrPollResults: Hashable, Sendable {
    let totalVotes: Int
    let voters: Set<String>
    let optionVoters: [String: Set<String>]

    static func empty(for poll: NostrPollMetadata) -> NostrPollResults {
        NostrPollResults(
            totalVotes: 0,
            voters: [],
            optionVoters: poll.options.reduce(into: [String: Set<String>]()) { partialResult, option in
                partialResult[option.id] = Set<String>()
            }
        )
    }

    static func build(
        for poll: NostrPollMetadata,
        responses: [NostrPollResponse]
    ) -> NostrPollResults {
        let newestFirst = responses.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.pubkey > rhs.pubkey
            }
            return lhs.createdAt > rhs.createdAt
        }

        var voters = Set<String>()
        var totalVotes = 0
        var optionVoters = poll.options.reduce(into: [String: Set<String>]()) { partialResult, option in
            partialResult[option.id] = Set<String>()
        }

        for response in newestFirst {
            guard voters.insert(response.pubkey).inserted else { continue }
            totalVotes += response.selectedOptionIDs.count

            for optionID in response.selectedOptionIDs {
                var current = optionVoters[optionID, default: Set<String>()]
                current.insert(response.pubkey)
                optionVoters[optionID] = current
            }
        }

        return NostrPollResults(
            totalVotes: totalVotes,
            voters: voters,
            optionVoters: optionVoters
        )
    }

    func voteCount(for optionID: String) -> Int {
        optionVoters[optionID]?.count ?? 0
    }

    func fraction(for optionID: String) -> Double {
        guard totalVotes > 0 else { return 0 }
        return Double(voteCount(for: optionID)) / Double(totalVotes)
    }

    func selectedOptionIDs(for pubkey: String?) -> [String] {
        let normalizedPubkey = pubkey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard !normalizedPubkey.isEmpty else { return [] }

        return optionVoters.compactMap { optionID, voters in
            voters.contains(normalizedPubkey) ? optionID : nil
        }
        .sorted()
    }

    var winningOptionIDs: Set<String> {
        let highestVoteCount = optionVoters.values.map(\.count).max() ?? 0
        guard highestVoteCount > 0 else { return [] }
        return Set(
            optionVoters.compactMap { optionID, voters in
                voters.count == highestVoteCount ? optionID : nil
            }
        )
    }
}

extension NostrEvent {
    var pollMetadata: NostrPollMetadata? {
        NostrPollMetadata(event: self)
    }
}
