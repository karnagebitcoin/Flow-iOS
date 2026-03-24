import Foundation

actor NostrLiveFeedSubscriber {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
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

        while !Task.isCancelled {
            let message = try await socket.receive()

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
                if isReadyForNewEvents {
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

    private func serializeJSONArray(_ value: [Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        return String(decoding: data, as: UTF8.self)
    }
}
