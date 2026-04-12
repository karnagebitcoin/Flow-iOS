import Foundation

final class NostrLiveFeedSubscriber: @unchecked Sendable {
    private let session: URLSession
    private let liveEventFallbackDelayNanoseconds: UInt64
    private let receiveIdleTimeoutNanoseconds: UInt64
    private let pingTimeoutNanoseconds: UInt64

    init(
        session: URLSession = .shared,
        liveEventFallbackDelayNanoseconds: UInt64 = 1_200_000_000,
        receiveIdleTimeoutNanoseconds: UInt64 = 45_000_000_000,
        pingTimeoutNanoseconds: UInt64 = 8_000_000_000
    ) {
        self.session = session
        self.liveEventFallbackDelayNanoseconds = liveEventFallbackDelayNanoseconds
        self.receiveIdleTimeoutNanoseconds = receiveIdleTimeoutNanoseconds
        self.pingTimeoutNanoseconds = pingTimeoutNanoseconds
    }

    func run(
        relayURL: URL,
        filter: NostrFilter,
        onNewEvent: @escaping @Sendable (NostrEvent) async -> Void,
        onStatus: @escaping @Sendable (String) async -> Void = { _ in }
    ) async {
        while !Task.isCancelled {
            do {
                try await runSingleSubscription(
                    relayURL: relayURL,
                    filter: filter,
                    onNewEvent: onNewEvent
                )
            } catch {
                await onStatus(error.localizedDescription)
            }

            if Task.isCancelled {
                return
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func runSingleSubscription(
        relayURL: URL,
        filter: NostrFilter,
        onNewEvent: @escaping @Sendable (NostrEvent) async -> Void
    ) async throws {
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

        var isReadyForNewEvents = false
        let subscriptionStartedAt = DispatchTime.now().uptimeNanoseconds

        while !Task.isCancelled {
            let message = try await receiveMessageKeepingSocketAlive(socket)

            let text: String
            switch message {
            case .string(let value):
                text = value
            case .data(let data):
                text = String(data: data, encoding: .utf8) ?? ""
            @unknown default:
                text = ""
            }

            guard let inbound = RelayInboundMessage.parse(text) else {
                continue
            }

            switch inbound {
            case .event(let id, let event):
                guard id == subscriptionID else { continue }
                let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - subscriptionStartedAt
                if isReadyForNewEvents || elapsedNanoseconds >= liveEventFallbackDelayNanoseconds {
                    await onNewEvent(event)
                }

            case .eose(let id):
                guard id == subscriptionID else { continue }
                isReadyForNewEvents = true

            case .closed(let id, let reason):
                guard id == subscriptionID else { continue }
                throw RelayClientError.closed(reason)

            case .notice:
                continue

            case .ok:
                continue
            }
        }
    }

    private func receiveMessageKeepingSocketAlive(
        _ socket: URLSessionWebSocketTask
    ) async throws -> URLSessionWebSocketTask.Message {
        while !Task.isCancelled {
            do {
                return try await receiveMessage(
                    from: socket,
                    timeoutNanoseconds: receiveIdleTimeoutNanoseconds
                )
            } catch LiveFeedSubscriptionError.receiveTimedOut {
                try await sendPing(
                    on: socket,
                    timeoutNanoseconds: pingTimeoutNanoseconds
                )
            }
        }

        throw CancellationError()
    }

    private func receiveMessage(
        from socket: URLSessionWebSocketTask,
        timeoutNanoseconds: UInt64
    ) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask {
                try await socket.receive()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw LiveFeedSubscriptionError.receiveTimedOut
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                throw CancellationError()
            }
            return result
        }
    }

    private func sendPing(
        on socket: URLSessionWebSocketTask,
        timeoutNanoseconds: UInt64
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.awaitPing(on: socket)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw LiveFeedSubscriptionError.pingTimedOut
            }

            defer { group.cancelAll() }

            guard let _ = try await group.next() else {
                throw CancellationError()
            }
        }
    }

    private func awaitPing(on socket: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func serializeJSONArray(_ value: [Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        return String(decoding: data, as: UTF8.self)
    }
}

private enum LiveFeedSubscriptionError: LocalizedError {
    case receiveTimedOut
    case pingTimedOut

    var errorDescription: String? {
        switch self {
        case .receiveTimedOut:
            return "Source stopped delivering live updates."
        case .pingTimedOut:
            return "Source stopped responding to heartbeat checks."
        }
    }
}
