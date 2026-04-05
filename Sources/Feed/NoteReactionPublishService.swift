import Foundation
import NostrSDK

enum NoteReactionToggleResult {
    case liked(NostrEvent)
    case unliked(String)
}

enum NoteReactionPublishError: LocalizedError {
    case missingPrivateKey
    case missingWriteRelays
    case malformedTargetEvent
    case malformedReaction
    case malformedDeletion
    case publishFailed

    var errorDescription: String? {
        switch self {
        case .missingPrivateKey:
            return "Sign in with a private key to react to notes."
        case .missingWriteRelays:
            return "No publish sources are configured."
        case .malformedTargetEvent:
            return "Couldn't prepare this note for reacting."
        case .malformedReaction:
            return "Couldn't build the reaction event."
        case .malformedDeletion:
            return "Couldn't remove the reaction."
        case .publishFailed:
            return "Couldn't publish the reaction right now."
        }
    }
}

final class NoteReactionPublishService {
    private let relayClient: any NostrRelayEventPublishing

    init(relayClient: any NostrRelayEventPublishing = NostrRelayClient()) {
        self.relayClient = relayClient
    }

    func toggleReaction(
        for targetEvent: NostrEvent,
        existingReactionID: String?,
        bonusCount: Int = 0,
        currentNsec: String?,
        writeRelayURLs: [URL],
        relayHintURL: URL?
    ) async throws -> NoteReactionToggleResult {
        guard let normalizedNsec = normalizeNsec(currentNsec),
              let keypair = Keypair(nsec: normalizedNsec.lowercased()) else {
            throw NoteReactionPublishError.missingPrivateKey
        }

        let targets = normalizedRelayURLs(writeRelayURLs)
        guard !targets.isEmpty else {
            throw NoteReactionPublishError.missingWriteRelays
        }

        if let existingReactionID = normalizedIdentifier(existingReactionID) {
            let deleteEvent = try makeReactionDeletionEvent(
                reactionEventID: existingReactionID,
                keypair: keypair
            )
            try await publish(event: deleteEvent, to: targets)
            return .unliked(existingReactionID)
        }

        let reactionEvent = try makeReactionEvent(
            targetEvent: targetEvent,
            keypair: keypair,
            bonusCount: bonusCount,
            relayHintURL: relayHintURL
        )
        try await publish(event: reactionEvent, to: targets)
        return .liked(localEvent(from: reactionEvent))
    }

    private func makeReactionEvent(
        targetEvent: NostrEvent,
        keypair: Keypair,
        bonusCount: Int,
        relayHintURL: URL?
    ) throws -> NostrSDK.NostrEvent {
        guard let targetEventID = normalizedIdentifier(targetEvent.id),
              let targetPubkey = normalizedIdentifier(targetEvent.pubkey) else {
            throw NoteReactionPublishError.malformedTargetEvent
        }

        var rawTags: [[String]] = []
        if let relayHintURL {
            rawTags.append(["e", targetEventID, relayHintURL.absoluteString])
        } else {
            rawTags.append(["e", targetEventID])
        }
        rawTags.append(["p", targetPubkey])
        rawTags.append(["k", "\(targetEvent.kind)"])
        if let bonusTag = ReactionBonusTag.bonusTag(for: bonusCount) {
            rawTags.append(bonusTag)
        }

        let sdkTags = FlowClientAttribution.appending(to: rawTags).compactMap(decodeSDKTag(from:))
        let reactionEvent = try NostrSDK.NostrEvent.Builder<NostrSDK.NostrEvent>(kind: .unknown(7))
            .content("+")
            .appendTags(contentsOf: sdkTags)
            .build(signedBy: keypair)

        guard !reactionEvent.id.isEmpty else {
            throw NoteReactionPublishError.malformedReaction
        }

        return reactionEvent
    }

    private func makeReactionDeletionEvent(
        reactionEventID: String,
        keypair: Keypair
    ) throws -> NostrSDK.NostrEvent {
        let rawTags = [
            ["e", reactionEventID],
            ["k", "7"]
        ]
        let sdkTags = FlowClientAttribution.appending(to: rawTags).compactMap(decodeSDKTag(from:))
        let deleteEvent = try NostrSDK.NostrEvent.Builder<NostrSDK.NostrEvent>(kind: .unknown(5))
            .content("Removed reaction")
            .appendTags(contentsOf: sdkTags)
            .build(signedBy: keypair)

        guard !deleteEvent.id.isEmpty else {
            throw NoteReactionPublishError.malformedDeletion
        }

        return deleteEvent
    }

    private func publish(event: NostrSDK.NostrEvent, to relayURLs: [URL]) async throws {
        let eventData = try JSONEncoder().encode(event)
        let publishOutcome = await relayClient.publishEvent(
            to: relayURLs,
            eventData: eventData,
            eventID: event.id
        )

        if publishOutcome.successfulSourceCount == 0 {
            if let firstFailureMessage = publishOutcome.firstFailureMessage {
                throw SourcePublishTransportError(message: firstFailureMessage)
            }
            throw NoteReactionPublishError.publishFailed
        }
    }

    private func localEvent(from event: NostrSDK.NostrEvent) -> NostrEvent {
        NostrEvent(
            id: event.id.lowercased(),
            pubkey: event.pubkey.lowercased(),
            createdAt: Int(event.createdAt),
            kind: event.kind.rawValue,
            tags: event.tags.map { [$0.name, $0.value] + $0.otherParameters },
            content: event.content,
            sig: event.signature ?? ""
        )
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

    private func normalizedIdentifier(_ value: String?) -> String? {
        let trimmed = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return trimmed.isEmpty ? nil : trimmed
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
