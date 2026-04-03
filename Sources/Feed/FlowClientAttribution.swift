import Foundation

enum FlowClientAttribution {
    static let tagName = "client"
    static let displayName = "Halo"
    static let handlerAddress: String? = nil
    static let handlerRelayHint: String? = nil

    static var rawTag: [String] {
        var tag = [tagName, displayName]

        if let handlerAddress = normalizedName(from: handlerAddress) {
            tag.append(handlerAddress)
            if let handlerRelayHint = normalizedName(from: handlerRelayHint) {
                tag.append(handlerRelayHint)
            }
        }

        return tag
    }

    static func appending(to tags: [[String]]) -> [[String]] {
        if tags.contains(where: { tag in
            guard let name = tag.first?.lowercased(), name == tagName else { return false }
            return normalizedName(from: tag.count > 1 ? tag[1] : nil) != nil
        }) {
            return tags
        }

        return tags + [rawTag]
    }

    static func normalizedName(from value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension NostrEvent {
    var clientName: String? {
        for tag in tags {
            guard let name = tag.first?.lowercased(), name == FlowClientAttribution.tagName else { continue }
            guard tag.count > 1 else { continue }
            return FlowClientAttribution.normalizedName(from: tag[1])
        }
        return nil
    }
}
