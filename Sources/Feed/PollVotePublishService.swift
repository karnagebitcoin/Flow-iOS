import Foundation
import NostrSDK

enum PollVotePublishError: LocalizedError {
    case missingSelection
    case missingPrivateKey
    case missingWriteRelays
    case publishFailed

    var errorDescription: String? {
        switch self {
        case .missingSelection:
            return "Choose an option before voting."
        case .missingPrivateKey:
            return "Sign in with a private key to vote."
        case .missingWriteRelays:
            return "No publish sources are configured for this vote."
        case .publishFailed:
            return "Couldn't submit your vote right now."
        }
    }
}

final class PollVotePublishService {
    private let relayClient: any NostrRelayEventPublishing

    init(relayClient: any NostrRelayEventPublishing = NostrRelayClient()) {
        self.relayClient = relayClient
    }

    func publishVote(
        pollEvent: NostrEvent,
        selectedOptionIDs: [String],
        currentNsec: String?,
        relayURLs: [URL]
    ) async throws -> Int {
        let normalizedOptionIDs = selectedOptionIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedOptionIDs.isEmpty else {
            throw PollVotePublishError.missingSelection
        }

        guard let normalizedNsec = normalizeNsec(currentNsec),
              let keypair = Keypair(nsec: normalizedNsec.lowercased()) else {
            throw PollVotePublishError.missingPrivateKey
        }

        let targets = normalizedRelayURLs(relayURLs)
        guard !targets.isEmpty else {
            throw PollVotePublishError.missingWriteRelays
        }

        let rawTags = [
            ["e", pollEvent.id.lowercased(), "", pollEvent.pubkey.lowercased()],
            ["p", pollEvent.pubkey.lowercased()]
        ] + normalizedOptionIDs.map { ["response", $0] }

        let sdkTags = rawTags.compactMap(decodeSDKTag(from:))
        let event = try NostrSDK.NostrEvent.Builder<NostrSDK.NostrEvent>(kind: .unknown(NostrPollKind.response))
            .content("")
            .appendTags(contentsOf: sdkTags)
            .build(signedBy: keypair)

        let eventData = try JSONEncoder().encode(event)
        let publishOutcome = await relayClient.publishEvent(
            to: targets,
            eventData: eventData,
            eventID: event.id
        )

        if publishOutcome.successfulSourceCount == 0 {
            if let firstFailureMessage = publishOutcome.firstFailureMessage {
                throw SourcePublishTransportError(message: firstFailureMessage)
            }
            throw PollVotePublishError.publishFailed
        }

        return publishOutcome.successfulSourceCount
    }

    private func normalizeNsec(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    private func decodeSDKTag(from raw: [String]) -> NostrSDK.Tag? {
        guard raw.count >= 2 else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: raw),
              let tag = try? JSONDecoder().decode(NostrSDK.Tag.self, from: data) else {
            return nil
        }
        return tag
    }
}
