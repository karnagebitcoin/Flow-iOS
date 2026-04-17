import Combine
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
    let attempts: [SourcePublishAttemptReport]

    init(
        successfulSourceCount: Int,
        firstFailureMessage: String?,
        attempts: [SourcePublishAttemptReport] = []
    ) {
        self.successfulSourceCount = successfulSourceCount
        self.firstFailureMessage = firstFailureMessage
        self.attempts = attempts
    }
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

struct SourcePublishAttemptReport: Codable, Equatable, Sendable {
    let sourceURLString: String
    let accepted: Bool
    let failureMessage: String?
    let rateLimited: Bool
    let recordedAt: Date

    init(
        sourceURL: URL,
        accepted: Bool,
        failureMessage: String? = nil,
        rateLimited: Bool = false,
        recordedAt: Date = Date()
    ) {
        self.sourceURLString = Self.normalizedSourceURLString(sourceURL.absoluteString)
        self.accepted = accepted
        self.failureMessage = failureMessage
        self.rateLimited = rateLimited
        self.recordedAt = recordedAt
    }

    private static func normalizedSourceURLString(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

struct SourcePublishStatsSnapshot: Codable, Equatable, Identifiable, Sendable {
    let sourceURLString: String
    var attemptedCount: Int
    var acceptedCount: Int
    var failedCount: Int
    var rateLimitedCount: Int
    var lastAttemptAt: Date?
    var lastAcceptedAt: Date?
    var lastFailedAt: Date?
    var lastFailureMessage: String?

    var id: String { sourceURLString }

    var acceptanceRate: Double {
        guard attemptedCount > 0 else { return 0 }
        return Double(acceptedCount) / Double(attemptedCount)
    }
}

@MainActor
final class SourcePublishStatsStore: ObservableObject {
    static let shared = SourcePublishStatsStore()

    @Published private(set) var snapshotsBySource: [String: SourcePublishStatsSnapshot]

    private let defaults: UserDefaults
    private let storageKey = "flow.sourcePublishStats.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: SourcePublishStatsSnapshot].self, from: data) {
            self.snapshotsBySource = decoded
        } else {
            self.snapshotsBySource = [:]
        }
    }

    func snapshot(for sourceURLString: String) -> SourcePublishStatsSnapshot? {
        snapshotsBySource[normalizedSourceKey(sourceURLString)]
    }

    func orderedSnapshots(for sourceURLStrings: [String]) -> [SourcePublishStatsSnapshot] {
        sourceURLStrings.compactMap(snapshot(for:))
    }

    func record(_ report: SourcePublishAttemptReport) {
        let key = normalizedSourceKey(report.sourceURLString)
        guard !key.isEmpty else { return }

        var snapshot = snapshotsBySource[key] ?? SourcePublishStatsSnapshot(
            sourceURLString: key,
            attemptedCount: 0,
            acceptedCount: 0,
            failedCount: 0,
            rateLimitedCount: 0,
            lastAttemptAt: nil,
            lastAcceptedAt: nil,
            lastFailedAt: nil,
            lastFailureMessage: nil
        )

        snapshot.attemptedCount += 1
        snapshot.lastAttemptAt = report.recordedAt

        if report.accepted {
            snapshot.acceptedCount += 1
            snapshot.lastAcceptedAt = report.recordedAt
        } else {
            snapshot.failedCount += 1
            snapshot.lastFailedAt = report.recordedAt
            snapshot.lastFailureMessage = report.failureMessage
            if report.rateLimited {
                snapshot.rateLimitedCount += 1
            }
        }

        snapshotsBySource[key] = snapshot
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshotsBySource) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func normalizedSourceKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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
    static let sharedRead = RelayEndpointBackoff()
    static let sharedReaction = RelayEndpointBackoff()
    static let sharedPublish = RelayEndpointBackoff()

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
    private let fetchEndpointBackoff: RelayEndpointBackoff
    private let publishEndpointBackoff: RelayEndpointBackoff

    init(
        session: URLSession = .shared,
        fetchEndpointBackoff: RelayEndpointBackoff = .sharedRead,
        publishEndpointBackoff: RelayEndpointBackoff = .sharedPublish
    ) {
        self.session = session
        self.fetchEndpointBackoff = fetchEndpointBackoff
        self.publishEndpointBackoff = publishEndpointBackoff
    }

    init(
        session: URLSession = .shared,
        endpointBackoff: RelayEndpointBackoff
    ) {
        self.session = session
        self.fetchEndpointBackoff = endpointBackoff
        self.publishEndpointBackoff = endpointBackoff
    }

    func fetchEvents(
        relayURL: URL,
        filter: NostrFilter,
        timeout: TimeInterval = 12
    ) async throws -> [NostrEvent] {
        let validatedRelayURL = try validatedWebSocketRelayURL(relayURL)
        guard await fetchEndpointBackoff.canAttempt(validatedRelayURL) else {
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
                        await fetchEndpointBackoff.recordSuccess(for: validatedRelayURL)
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

            await fetchEndpointBackoff.recordSuccess(for: validatedRelayURL)
            return events
        } catch {
            if shouldRecordBackoff(for: error) {
                await fetchEndpointBackoff.recordFailure(for: validatedRelayURL)
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
        guard await publishEndpointBackoff.canAttempt(validatedRelayURL) else {
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
                        await publishEndpointBackoff.recordSuccess(for: validatedRelayURL)
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
                await publishEndpointBackoff.recordFailure(for: validatedRelayURL)
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
        let result = await withTaskGroup(of: Result<String?, Error>.self) { group in
            group.addTask {
                do {
                    let message = try await socket.receive()
                    switch message {
                    case .string(let text):
                        return .success(text)
                    case .data(let data):
                        return .success(String(data: data, encoding: .utf8))
                    @unknown default:
                        return .success(nil)
                    }
                } catch {
                    return .failure(error)
                }
            }

            group.addTask {
                let nanoseconds = UInt64(max(timeout, 0) * 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return .success(nil)
                }

                guard !Task.isCancelled else {
                    return .success(nil)
                }

                socket.cancel(with: .goingAway, reason: nil)
                return .success(nil)
            }

            let result = await group.next() ?? .success(nil)
            group.cancelAll()
            return result
        }
        return try result.get()
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

private actor SourcePublishFirstSuccessCoordinator {
    private let continuation: CheckedContinuation<SourcePublishOutcome, Never>
    private var remainingCount: Int
    private var successfulSourceCount = 0
    private var firstFailureMessage: String?
    private var attempts: [SourcePublishAttemptReport] = []
    private var didResume = false

    init(
        totalCount: Int,
        continuation: CheckedContinuation<SourcePublishOutcome, Never>
    ) {
        self.remainingCount = totalCount
        self.continuation = continuation
    }

    func record(_ attempt: SourcePublishAttemptReport) {
        guard !didResume else { return }

        attempts.append(attempt)
        remainingCount -= 1

        if attempt.accepted {
            successfulSourceCount += 1
            didResume = true
            continuation.resume(
                returning: SourcePublishOutcome(
                    successfulSourceCount: successfulSourceCount,
                    firstFailureMessage: firstFailureMessage,
                    attempts: attempts
                )
            )
            return
        }

        if firstFailureMessage == nil {
            firstFailureMessage = attempt.failureMessage
        }

        if remainingCount <= 0 {
            didResume = true
            continuation.resume(
                returning: SourcePublishOutcome(
                    successfulSourceCount: successfulSourceCount,
                    firstFailureMessage: firstFailureMessage,
                    attempts: attempts
                )
            )
        }
    }
}

extension NostrRelayEventPublishing {
    func publishEvent(
        to sourceURLs: [URL],
        eventData: Data,
        eventID: String,
        timeout: TimeInterval = 10,
        successPolicy: SourcePublishSuccessPolicy = .waitForAllAcknowledgements
    ) async -> SourcePublishOutcome {
        guard !sourceURLs.isEmpty else {
            return SourcePublishOutcome(successfulSourceCount: 0, firstFailureMessage: nil)
        }

        switch successPolicy {
        case .waitForAllAcknowledgements:
            return await publishEventWaitingForAllSources(
                sourceURLs: sourceURLs,
                eventData: eventData,
                eventID: eventID,
                timeout: timeout
            )
        case .returnAfterFirstSuccess:
            return await publishEventReturningAfterFirstSourceSuccess(
                sourceURLs: sourceURLs,
                eventData: eventData,
                eventID: eventID,
                timeout: timeout
            )
        }
    }

    private func publishEventWaitingForAllSources(
        sourceURLs: [URL],
        eventData: Data,
        eventID: String,
        timeout: TimeInterval
    ) async -> SourcePublishOutcome {
        await withTaskGroup(of: SourcePublishAttempt.self, returning: SourcePublishOutcome.self) { group in
            for sourceURL in sourceURLs {
                group.addTask {
                    await publishAttemptReport(
                        publisher: self,
                        sourceURL: sourceURL,
                        eventData: eventData,
                        eventID: eventID,
                        timeout: timeout
                    )
                }
            }

            var successfulSourceCount = 0
            var firstFailureMessage: String?
            var attempts: [SourcePublishAttemptReport] = []

            for await attempt in group {
                attempts.append(attempt)
                recordSourcePublishAttempt(attempt)

                if attempt.accepted {
                    successfulSourceCount += 1
                } else if firstFailureMessage == nil {
                    firstFailureMessage = attempt.failureMessage
                }
            }

            return SourcePublishOutcome(
                successfulSourceCount: successfulSourceCount,
                firstFailureMessage: firstFailureMessage,
                attempts: attempts
            )
        }
    }

    private func publishEventReturningAfterFirstSourceSuccess(
        sourceURLs: [URL],
        eventData: Data,
        eventID: String,
        timeout: TimeInterval
    ) async -> SourcePublishOutcome {
        await withCheckedContinuation { continuation in
            let coordinator = SourcePublishFirstSuccessCoordinator(
                totalCount: sourceURLs.count,
                continuation: continuation
            )

            for sourceURL in sourceURLs {
                Task.detached(priority: .userInitiated) {
                    let attempt = await publishAttemptReport(
                        publisher: self,
                        sourceURL: sourceURL,
                        eventData: eventData,
                        eventID: eventID,
                        timeout: timeout
                    )

                    recordSourcePublishAttempt(attempt)
                    await coordinator.record(attempt)
                }
            }
        }
    }
}

private typealias SourcePublishAttempt = SourcePublishAttemptReport

private func recordSourcePublishAttempt(_ attempt: SourcePublishAttemptReport) {
    Task { @MainActor in
        SourcePublishStatsStore.shared.record(attempt)
    }
}

private func publishAttemptReport(
    publisher: any NostrRelayEventPublishing,
    sourceURL: URL,
    eventData: Data,
    eventID: String,
    timeout: TimeInterval
) async -> SourcePublishAttemptReport {
    do {
        try await publisher.publishEvent(
            relayURL: sourceURL,
            eventData: eventData,
            eventID: eventID,
            timeout: timeout
        )
        return SourcePublishAttemptReport(sourceURL: sourceURL, accepted: true)
    } catch {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return SourcePublishAttemptReport(
            sourceURL: sourceURL,
            accepted: false,
            failureMessage: message,
            rateLimited: SourcePublishFailureClassifier.isRateLimited(error: error, message: message)
        )
    }
}

private enum SourcePublishFailureClassifier {
    static func isRateLimited(error: Error, message: String) -> Bool {
        if let relayError = error as? RelayClientError {
            switch relayError {
            case .coolingDown:
                return true
            case .publishRejected(let reason):
                return isRateLimitMessage(reason)
            case .invalidRelayURL, .closed, .publishTimedOut:
                break
            }
        }

        return isRateLimitMessage(message)
    }

    private static func isRateLimitMessage(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("rate limit") ||
            normalized.contains("rate-limit") ||
            normalized.contains("ratelimit") ||
            normalized.contains("too many") ||
            normalized.contains("too-many") ||
            normalized.contains("limited")
    }
}
