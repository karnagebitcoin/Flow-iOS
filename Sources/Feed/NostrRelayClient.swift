import Foundation

enum RelayClientError: LocalizedError {
    case invalidRelayURL(String)
    case closed(String)
    case publishRejected(String)
    case publishTimedOut

    var errorDescription: String? {
        switch self {
        case .invalidRelayURL(let value):
            return "Invalid relay URL: \(value)"
        case .closed(let reason):
            return "Relay closed the subscription: \(reason)"
        case .publishRejected(let reason):
            return "Relay rejected the event: \(reason)"
        case .publishTimedOut:
            return "Relay publish timed out."
        }
    }
}

actor NostrRelayClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchEvents(
        relayURL: URL,
        filter: NostrFilter,
        timeout: TimeInterval = 12
    ) async throws -> [NostrEvent] {
        let socket = session.webSocketTask(with: relayURL)
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

        return events
    }

    func publishEvent(
        relayURL: URL,
        eventObject: [String: Any],
        eventID: String,
        timeout: TimeInterval = 10
    ) async throws {
        let socket = session.webSocketTask(with: relayURL)
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

    private func serializeJSONArray(_ value: [Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        return String(decoding: data, as: UTF8.self)
    }
}
