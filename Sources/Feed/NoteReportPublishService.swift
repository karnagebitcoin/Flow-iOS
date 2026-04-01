import Foundation
import NostrSDK

enum NoteReportType: String, CaseIterable, Identifiable, Sendable {
    case spam
    case profanity
    case nudity
    case illegal
    case malware
    case impersonation
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spam:
            return "Spam"
        case .profanity:
            return "Profanity or Hate"
        case .nudity:
            return "Nudity"
        case .illegal:
            return "Illegal Content"
        case .malware:
            return "Malware"
        case .impersonation:
            return "Impersonation"
        case .other:
            return "Other"
        }
    }

    var subtitle: String {
        switch self {
        case .spam:
            return "Unwanted promotions, scams, or repetitive junk."
        case .profanity:
            return "Abusive, hateful, or profane content."
        case .nudity:
            return "Explicit sexual or nude material."
        case .illegal:
            return "May violate laws or platform policies."
        case .malware:
            return "Malicious links, files, or harmful software."
        case .impersonation:
            return "Pretending to be another person or brand."
        case .other:
            return "Something else that should be reviewed."
        }
    }

    var systemImage: String {
        switch self {
        case .spam:
            return "exclamationmark.arrow.trianglehead.2.clockwise"
        case .profanity:
            return "hand.raised"
        case .nudity:
            return "eye.slash"
        case .illegal:
            return "exclamationmark.shield"
        case .malware:
            return "ant"
        case .impersonation:
            return "person.crop.circle.badge.exclamationmark"
        case .other:
            return "ellipsis.circle"
        }
    }
}

enum NoteReportPublishError: LocalizedError {
    case missingPrivateKey
    case missingWriteRelays
    case malformedTargetEvent
    case malformedReport
    case publishFailed

    var errorDescription: String? {
        switch self {
        case .missingPrivateKey:
            return "Sign in with a private key to send a report."
        case .missingWriteRelays:
            return "No publish sources are configured."
        case .malformedTargetEvent:
            return "Couldn't prepare this note for reporting."
        case .malformedReport:
            return "Couldn't build the report event."
        case .publishFailed:
            return "Couldn't publish the report right now."
        }
    }
}

final class NoteReportPublishService {
    private let relayClient: any NostrRelayEventPublishing

    init(relayClient: any NostrRelayEventPublishing = NostrRelayClient()) {
        self.relayClient = relayClient
    }

    func publishReport(
        for targetEvent: NostrEvent,
        type: NoteReportType,
        details: String,
        currentNsec: String?,
        writeRelayURLs: [URL]
    ) async throws {
        guard let normalizedNsec = normalizeNsec(currentNsec),
              let keypair = Keypair(nsec: normalizedNsec.lowercased()) else {
            throw NoteReportPublishError.missingPrivateKey
        }

        let targets = normalizedRelayURLs(writeRelayURLs)
        guard !targets.isEmpty else {
            throw NoteReportPublishError.missingWriteRelays
        }

        let reportEvent = try makeReportEvent(
            targetEvent: targetEvent,
            type: type,
            details: details,
            keypair: keypair
        )
        try await publish(event: reportEvent, to: targets)
    }

    private func makeReportEvent(
        targetEvent: NostrEvent,
        type: NoteReportType,
        details: String,
        keypair: Keypair
    ) throws -> NostrSDK.NostrEvent {
        guard let targetEventID = normalizedIdentifier(targetEvent.id),
              let targetPubkey = normalizedIdentifier(targetEvent.pubkey) else {
            throw NoteReportPublishError.malformedTargetEvent
        }

        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        var rawTags: [[String]] = [
            ["p", targetPubkey, type.rawValue],
            ["e", targetEventID, type.rawValue]
        ]
        rawTags = FlowClientAttribution.appending(to: rawTags)

        let sdkTags = rawTags.compactMap(decodeSDKTag(from:))
        let event = try NostrSDK.NostrEvent.Builder<NostrSDK.NostrEvent>(kind: .unknown(1984))
            .content(trimmedDetails)
            .appendTags(contentsOf: sdkTags)
            .build(signedBy: keypair)

        guard !event.id.isEmpty else {
            throw NoteReportPublishError.malformedReport
        }

        return event
    }

    private func publish(event: NostrSDK.NostrEvent, to relayURLs: [URL]) async throws {
        let eventData = try JSONEncoder().encode(event)
        let publishOutcome = await relayClient.publishEvent(
            to: relayURLs,
            eventData: eventData,
            eventID: event.id,
            successPolicy: .returnAfterFirstSuccess
        )

        if publishOutcome.successfulSourceCount == 0 {
            if let firstFailureMessage = publishOutcome.firstFailureMessage {
                throw SourcePublishTransportError(message: firstFailureMessage)
            }
            throw NoteReportPublishError.publishFailed
        }
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
