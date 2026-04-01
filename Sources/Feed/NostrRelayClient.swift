import Foundation

protocol NostrRelayEventFetching: Sendable {
    func fetchEvents(
        relayURL: URL,
        filter: NostrFilter,
        timeout: TimeInterval
    ) async throws -> [NostrEvent]
}

protocol NostrRelayEventPublishing: Sendable {
    func publishEvent(
        relayURL: URL,
        eventData: Data,
        eventID: String,
        timeout: TimeInterval
    ) async throws
}

struct SourcePublishOutcome: Sendable {
    let successfulSourceCount: Int
    let firstFailureMessage: String?
}

enum SourcePublishSuccessPolicy: Sendable {
    case waitForAllAcknowledgements
    case returnAfterFirstSuccess
}

struct SourcePublishTransportError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? {
        message
    }
}

enum RelayClientError: LocalizedError {
    case invalidRelayURL(String)
    case coolingDown(String)
    case closed(String)
    case publishRejected(String)
    case publishTimedOut

    var errorDescription: String? {
        switch self {
        case .invalidRelayURL(let value):
            return "Invalid source URL: \(value)"
        case .coolingDown(let value):
            return "Source is cooling down after repeated failures: \(value)"
        case .closed(let reason):
            return "Source closed the subscription: \(reason)"
        case .publishRejected(let reason):
            return "Source rejected the event: \(reason)"
        case .publishTimedOut:
            return "Source publish timed out."
        }
    }
}

actor RelayEndpointBackoff {
    static let shared = RelayEndpointBackoff()

    private struct Entry {
        var failureCount: Int
        var retryAfter: Date
    }

    private let aggressiveHosts: Set<String>
    private let maxEntries = 64
    private var failures: [String: Entry] = [:]
    private var failureOrder: [String] = []

    init(aggressiveHosts: Set<String> = ["relay.nostr.band", "relay.damus.io"]) {
        self.aggressiveHosts = aggressiveHosts
    }

    func canAttempt(_ url: URL, now: Date = Date()) -> Bool {
        clearExpiredEntries(now: now)

        guard let key = endpointKey(for: url),
              let entry = failures[key] else {
            return true
        }

        return entry.retryAfter <= now
    }

    func recordSuccess(for url: URL) {
        guard let key = endpointKey(for: url) else { return }
        failures.removeValue(forKey: key)
        failureOrder.removeAll { $0 == key }
    }

    func recordFailure(for url: URL) {
        guard let key = endpointKey(for: url) else { return }

        let baseDelay: TimeInterval = aggressiveHosts.contains(url.host?.lowercased() ?? "") ? 60 : 20
        let nextFailureCount = (failures[key]?.failureCount ?? 0) + 1
        let multiplier = pow(2.0, Double(min(nextFailureCount - 1, 5)))
        let delay = min(baseDelay * multiplier, 15 * 60)

        failures[key] = Entry(
            failureCount: nextFailureCount,
            retryAfter: Date().addingTimeInterval(delay)
        )
        failureOrder.removeAll { $0 == key }
        failureOrder.append(key)
        trimIfNeeded()
    }

    private func clearExpiredEntries(now: Date) {
        let expiredKeys = failures.compactMap { key, entry in
            entry.retryAfter <= now ? key : nil
        }
        guard !expiredKeys.isEmpty else { return }

        let expiredSet = Set(expiredKeys)
        expiredKeys.forEach { failures.removeValue(forKey: $0) }
        failureOrder.removeAll { expiredSet.contains($0) }
    }

    private func trimIfNeeded() {
        while failureOrder.count > maxEntries {
            let removedKey = failureOrder.removeFirst()
            failures.removeValue(forKey: removedKey)
        }
    }

    private func endpointKey(for url: URL) -> String? {
        let normalized = url.absoluteString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

final class NostrRelayClient: @unchecked Sendable {
    private let session: URLSession
    private let endpointBackoff: RelayEndpointBackoff

    init(
        session: URLSession = .shared,
        endpointBackoff: RelayEndpointBackoff = .shared
    ) {
        self.session = session
        self.endpointBackoff = endpointBackoff
    }

    func fetchEvents(
        relayURL: URL,
        filter: NostrFilter,
        timeout: TimeInterval = 12
    ) async throws -> [NostrEvent] {
        let validatedRelayURL = try validatedWebSocketRelayURL(relayURL)
        guard await endpointBackoff.canAttempt(validatedRelayURL) else {
            throw RelayClientError.coolingDown(validatedRelayURL.absoluteString)
        }

        do {
            let socket = session.webSocketTask(with: validatedRelayURL)
            socket.resume()

            let subscriptionID = UUID().uuidString
            let request = try serializeJSONArray(["REQ", subscriptionID, filter.jsonObject])
            try await socket.send(.string(request))

            defer {
                Task {
                    if let close = try? serializeJSONArray(["CLOSE", subscriptionID]) {
                        try? await socket.send(.string(close))
                    }
                    socket.cancel(with: .normalClosure, reason: nil)
                }
            }

            var events: [NostrEvent] = []
            let deadline = Date().addingTimeInterval(timeout)

            while Date() < deadline {
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { break }

                guard let text = try await receiveText(from: socket, timeout: remaining) else {
                    break
                }

                guard let message = RelayInboundMessage.parse(text) else {
                    continue
                }

                switch message {
                case .event(let id, let event):
                    if id == subscriptionID {
                        events.append(event)
                    }
                case .eose(let id):
                    if id == subscriptionID {
                        await endpointBackoff.recordSuccess(for: validatedRelayURL)
                        return events
                    }
                case .ok:
                    continue
                case .closed(let id, let reason):
                    if id == subscriptionID {
                        throw RelayClientError.closed(reason)
                    }
                case .notice:
                    continue
                }
            }

            await endpointBackoff.recordSuccess(for: validatedRelayURL)
            return events
        } catch {
            if shouldRecordBackoff(for: error) {
                await endpointBackoff.recordFailure(for: validatedRelayURL)
            }
            throw error
        }
    }

    func publishEvent(
        relayURL: URL,
        eventObject: [String: Any],
        eventID: String,
        timeout: TimeInterval = 10
    ) async throws {
        let validatedRelayURL = try validatedWebSocketRelayURL(relayURL)
        guard await endpointBackoff.canAttempt(validatedRelayURL) else {
            throw RelayClientError.coolingDown(validatedRelayURL.absoluteString)
        }

        do {
            let socket = session.webSocketTask(with: validatedRelayURL)
            socket.resume()

            let request = try serializeJSONArray(["EVENT", eventObject])
            try await socket.send(.string(request))

            defer {
                socket.cancel(with: .normalClosure, reason: nil)
            }

            let deadline = Date().addingTimeInterval(timeout)

            while Date() < deadline {
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { break }

                guard let text = try await receiveText(from: socket, timeout: remaining) else {
                    break
                }

                guard let message = RelayInboundMessage.parse(text) else {
                    continue
                }

                switch message {
                case .ok(let ackedEventID, let accepted, let reason):
                    guard ackedEventID == eventID else { continue }
                    if accepted {
                        await endpointBackoff.recordSuccess(for: validatedRelayURL)
                        return
                    }
                    throw RelayClientError.publishRejected(reason ?? "Unknown reason")

                case .closed(_, let reason):
                    throw RelayClientError.closed(reason)

                case .notice, .event, .eose:
                    continue
                }
            }

            throw RelayClientError.publishTimedOut
        } catch {
            if shouldRecordBackoff(for: error) {
                await endpointBackoff.recordFailure(for: validatedRelayURL)
            }
            throw error
        }
    }

    func publishEvent(
        relayURL: URL,
        eventData: Data,
        eventID: String,
        timeout: TimeInterval = 10
    ) async throws {
        guard let eventObject = try JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
            throw RelayClientError.publishRejected("Malformed event payload")
        }

        try await publishEvent(
            relayURL: relayURL,
            eventObject: eventObject,
            eventID: eventID,
            timeout: timeout
        )
    }

    func fetchEvents(
        relayURLString: String,
        filter: NostrFilter,
        timeout: TimeInterval = 12
    ) async throws -> [NostrEvent] {
        guard let relayURL = URL(string: relayURLString) else {
            throw RelayClientError.invalidRelayURL(relayURLString)
        }
        return try await fetchEvents(relayURL: relayURL, filter: filter, timeout: timeout)
    }

    private func receiveText(
        from socket: URLSessionWebSocketTask,
        timeout: TimeInterval
    ) async throws -> String? {
        try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                let message = try await socket.receive()
                switch message {
                case .string(let text):
                    return text
                case .data(let data):
                    return String(data: data, encoding: .utf8)
                @unknown default:
                    return nil
                }
            }

            group.addTask {
                let nanoseconds = UInt64(max(timeout, 0) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                return nil
            }

            let value = try await group.next() ?? nil
            group.cancelAll()
            return value
        }
    }

    private func validatedWebSocketRelayURL(_ relayURL: URL) throws -> URL {
        guard let scheme = relayURL.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss",
              let host = relayURL.host,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RelayClientError.invalidRelayURL(relayURL.absoluteString)
        }
        return relayURL
    }

    private func serializeJSONArray(_ value: [Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        return String(decoding: data, as: UTF8.self)
    }

    private func shouldRecordBackoff(for error: Error) -> Bool {
        if let relayError = error as? RelayClientError {
            switch relayError {
            case .invalidRelayURL, .coolingDown, .publishRejected:
                return false
            case .closed, .publishTimedOut:
                return true
            }
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
    }
}

extension NostrRelayClient: NostrRelayEventFetching {}
extension NostrRelayClient: NostrRelayEventPublishing {}

private enum SourcePublishAttempt: Sendable {
    case success
    case failure(String)
}

extension NostrRelayEventPublishing {
    func publishEvent(
        to sourceURLs: [URL],
        eventData: Data,
        eventID: String,
        timeout: TimeInterval = 10,
        successPolicy: SourcePublishSuccessPolicy = .waitForAllAcknowledgements
    ) async -> SourcePublishOutcome {
        await withTaskGroup(of: SourcePublishAttempt.self, returning: SourcePublishOutcome.self) { group in
            for sourceURL in sourceURLs {
                group.addTask {
                    do {
                        try await publishEvent(
                            relayURL: sourceURL,
                            eventData: eventData,
                            eventID: eventID,
                            timeout: timeout
                        )
                        return .success
                    } catch {
                        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        return .failure(message)
                    }
                }
            }

            var successfulSourceCount = 0
            var firstFailureMessage: String?

            for await attempt in group {
                switch attempt {
                case .success:
                    successfulSourceCount += 1
                    if successPolicy == .returnAfterFirstSuccess {
                        group.cancelAll()
                        return SourcePublishOutcome(
                            successfulSourceCount: successfulSourceCount,
                            firstFailureMessage: firstFailureMessage
                        )
                    }
                case .failure(let message):
                    if firstFailureMessage == nil {
                        firstFailureMessage = message
                    }
                }
            }

            return SourcePublishOutcome(
                successfulSourceCount: successfulSourceCount,
                firstFailureMessage: firstFailureMessage
            )
        }
    }
}
