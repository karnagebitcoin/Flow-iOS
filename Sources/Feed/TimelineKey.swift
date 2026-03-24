import CryptoKit
import Foundation

func generateTimelineKey(relayURL: URL, filter: NostrFilter) -> String {
    let normalizedRelay = relayURL.absoluteString.lowercased()
    let canonicalFilter = filter.canonicalString
    let input = "urls:\(normalizedRelay)|filter:\(canonicalFilter)"

    let digest = SHA256.hash(data: Data(input.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

private extension NostrFilter {
    var canonicalString: String {
        var components: [String] = []

        if let ids, !ids.isEmpty {
            components.append("ids=\(ids.sorted().joined(separator: ","))")
        }
        if let authors, !authors.isEmpty {
            components.append("authors=\(authors.sorted().joined(separator: ","))")
        }
        if let kinds, !kinds.isEmpty {
            components.append("kinds=\(kinds.sorted().map(String.init).joined(separator: ","))")
        }
        if let search {
            let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSearch.isEmpty {
                components.append("search=\(trimmedSearch)")
            }
        }
        if let limit {
            components.append("limit=\(limit)")
        }
        if let since {
            components.append("since=\(since)")
        }
        if let until {
            components.append("until=\(until)")
        }
        if let tagFilters, !tagFilters.isEmpty {
            let stableTags = tagFilters
                .map { key, values -> String in
                    let normalizedKey = key.hasPrefix("#") ? key.lowercased() : "#\(key.lowercased())"
                    return "\(normalizedKey)=\(values.sorted().joined(separator: ","))"
                }
                .sorted()
            components.append(contentsOf: stableTags)
        }

        return components.joined(separator: "|")
    }
}
