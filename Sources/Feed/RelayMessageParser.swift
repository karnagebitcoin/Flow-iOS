import Foundation

enum RelayInboundMessage {
    case event(String, NostrEvent)
    case eose(String)
    case notice(String)
    case closed(String, String)
    case ok(String, Bool, String?)

    static func parse(_ text: String) -> RelayInboundMessage? {
        guard let data = text.data(using: .utf8) else { return nil }
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        guard let type = payload.first as? String else { return nil }

        switch type {
        case "EVENT":
            guard payload.count >= 3,
                  let subscriptionID = payload[1] as? String,
                  let eventObject = payload[2] as? [String: Any],
                  let eventData = try? JSONSerialization.data(withJSONObject: eventObject),
                  let event = try? JSONDecoder().decode(NostrEvent.self, from: eventData) else {
                return nil
            }
            return .event(subscriptionID, event)

        case "EOSE":
            guard payload.count >= 2, let subscriptionID = payload[1] as? String else {
                return nil
            }
            return .eose(subscriptionID)

        case "NOTICE":
            guard payload.count >= 2, let message = payload[1] as? String else {
                return nil
            }
            return .notice(message)

        case "CLOSED":
            guard payload.count >= 3,
                  let subscriptionID = payload[1] as? String,
                  let reason = payload[2] as? String else {
                return nil
            }
            return .closed(subscriptionID, reason)

        case "OK":
            guard payload.count >= 3,
                  let eventID = payload[1] as? String,
                  let accepted = payload[2] as? Bool else {
                return nil
            }
            let message = payload.count > 3 ? payload[3] as? String : nil
            return .ok(eventID, accepted, message)

        default:
            return nil
        }
    }
}
