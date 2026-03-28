import Foundation
import NostrSDK

enum ComposeNotePublishError: LocalizedError {
    case emptyContent
    case missingPrivateKey
    case missingWriteRelays
    case malformedEvent
    case publishFailed

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "Write something or attach media before posting."
        case .missingPrivateKey:
            return "This account can read posts, but it needs an nsec to publish."
        case .missingWriteRelays:
            return "No publish sources are configured."
        case .malformedEvent:
            return "Couldn't build the note to publish."
        case .publishFailed:
            return "Couldn't publish the note right now."
        }
    }
}

final class ComposeNotePublishService {
    private let relayClient: any NostrRelayEventPublishing

    init(relayClient: any NostrRelayEventPublishing = NostrRelayClient()) {
        self.relayClient = relayClient
    }

    func publishNote(
        content: String,
        currentNsec: String?,
        writeRelayURLs: [URL],
        additionalTags: [[String]] = []
    ) async throws -> Int {
        let publishedContent = ComposePublishedMediaContentBuilder.content(
            baseText: content,
            additionalTags: additionalTags
        )
        guard !publishedContent.isEmpty || !additionalTags.isEmpty else {
            throw ComposeNotePublishError.emptyContent
        }

        guard let normalizedNsec = normalizeNsec(currentNsec),
              let keypair = Keypair(nsec: normalizedNsec.lowercased()) else {
            throw ComposeNotePublishError.missingPrivateKey
        }

        let targets = normalizedRelayURLs(writeRelayURLs)
        guard !targets.isEmpty else {
            throw ComposeNotePublishError.missingWriteRelays
        }

        var sdkTags: [Tag] = []
        for rawTag in additionalTags {
            guard let tag = decodeSDKTag(from: rawTag) else { continue }
            sdkTags.append(tag)
        }

        let event = try NostrSDK.NostrEvent.Builder<NostrSDK.NostrEvent>(kind: .textNote)
            .content(publishedContent)
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
            throw ComposeNotePublishError.publishFailed
        }

        return publishOutcome.successfulSourceCount
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

    private func normalizeNsec(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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

private enum ComposePublishedMediaContentBuilder {
    static func content(baseText: String, additionalTags: [[String]]) -> String {
        let trimmedText = baseText.trimmingCharacters(in: .whitespacesAndNewlines)
        let mediaURLs = extractedMediaURLs(from: additionalTags).filter { !trimmedText.contains($0) }

        guard !mediaURLs.isEmpty else { return trimmedText }
        if trimmedText.isEmpty {
            return mediaURLs.joined(separator: "\n")
        }

        return ([trimmedText] + mediaURLs).joined(separator: "\n")
    }

    private static func extractedMediaURLs(from tags: [[String]]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for tag in tags {
            guard let name = tag.first?.lowercased(), name == "imeta" else { continue }

            for value in tag.dropFirst() {
                guard value.hasPrefix("url ") else { continue }
                let url = String(value.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !url.isEmpty else { continue }

                let normalized = url.lowercased()
                guard seen.insert(normalized).inserted else { continue }
                ordered.append(url)
                break
            }
        }

        return ordered
    }
}
