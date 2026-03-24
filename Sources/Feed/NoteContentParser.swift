import Foundation

enum NoteContentTokenType: Hashable {
    case text
    case url
    case websocketURL
    case nostrMention
    case nostrEvent
    case hashtag
    case emoji
    case image
    case video
    case audio
}

struct NoteContentToken: Hashable {
    let type: NoteContentTokenType
    let value: String
}

enum NoteContentParser {
    private enum CandidateType {
        case httpURL
        case websocketURL
        case nostrURI
        case hashtag
        case emoji
    }

    private struct Candidate {
        let range: NSRange
        let value: String
        let type: CandidateType
    }

    private static let linkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    private static let websocketRegex = try? NSRegularExpression(
        pattern: #"wss?:\/\/[^\s]+"#,
        options: [.caseInsensitive]
    )

    // Mirrors Flow web combined matching for both `nostr:` URIs and bare bech32 IDs.
    private static let nostrReferenceRegex = try? NSRegularExpression(
        pattern: #"(?:nostr:)?(npub1[a-z0-9]{58}|nprofile1[a-z0-9]+|note1[a-z0-9]{58}|nevent1[a-z0-9]+|naddr1[a-z0-9]+|nrelay1[a-z0-9]+)"#,
        options: [.caseInsensitive]
    )
    
    private static let hashtagRegex = try? NSRegularExpression(
        pattern: #"#[\p{L}\p{N}\p{M}_]+"#,
        options: []
    )

    private static let emojiShortcodeRegex = try? NSRegularExpression(
        pattern: #":[^\s:]{1,64}:"#,
        options: []
    )

    private static let trailingURLPunctuation = CharacterSet(charactersIn: #".,;:'")]}!?，。；："'！？】）"#)

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "svg"
    ]

    private static let videoExtensions: Set<String> = [
        "mp4", "webm", "ogg", "mov"
    ]

    private static let audioExtensions: Set<String> = [
        "mp3", "wav", "flac", "aac", "m4a", "opus", "wma"
    ]

    static func tokenize(event: NostrEvent) -> [NoteContentToken] {
        let baseTokens = tokenize(content: event.content)
        let mediaAwareTokens = appendImetaMediaIfNeeded(tokens: baseTokens, tags: event.tags)
        return appendQuotedReferencesIfNeeded(tokens: mediaAwareTokens, tags: event.tags)
    }

    static func tokenize(content: String) -> [NoteContentToken] {
        guard !content.isEmpty else { return [] }
        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        var candidates: [Candidate] = []

        if let linkDetector {
            let matches = linkDetector.matches(in: content, options: [], range: fullRange)
            for match in matches {
                guard let url = match.url else { continue }
                let scheme = url.scheme?.lowercased() ?? ""
                guard scheme == "http" || scheme == "https" else { continue }
                candidates.append(
                    Candidate(
                        range: match.range,
                        value: nsContent.substring(with: match.range),
                        type: .httpURL
                    )
                )
            }
        }

        if let websocketRegex {
            let matches = websocketRegex.matches(in: content, options: [], range: fullRange)
            for match in matches {
                let raw = nsContent.substring(with: match.range)
                let sanitized = trimTrailingPunctuation(raw)
                let adjustedLength = (sanitized as NSString).length
                guard adjustedLength > 0 else { continue }
                candidates.append(
                    Candidate(
                        range: NSRange(location: match.range.location, length: adjustedLength),
                        value: sanitized,
                        type: .websocketURL
                    )
                )
            }
        }

        if let nostrReferenceRegex {
            let matches = nostrReferenceRegex.matches(in: content, options: [], range: fullRange)
            for match in matches {
                candidates.append(
                    Candidate(
                        range: match.range,
                        value: nsContent.substring(with: match.range),
                        type: .nostrURI
                    )
                )
            }
        }
        
        if let hashtagRegex {
            let matches = hashtagRegex.matches(in: content, options: [], range: fullRange)
            for match in matches {
                candidates.append(
                    Candidate(
                        range: match.range,
                        value: nsContent.substring(with: match.range),
                        type: .hashtag
                    )
                )
            }
        }

        if let emojiShortcodeRegex {
            let matches = emojiShortcodeRegex.matches(in: content, options: [], range: fullRange)
            for match in matches {
                candidates.append(
                    Candidate(
                        range: match.range,
                        value: nsContent.substring(with: match.range),
                        type: .emoji
                    )
                )
            }
        }

        let sortedCandidates = candidates.sorted { lhs, rhs in
            if lhs.range.location != rhs.range.location {
                return lhs.range.location < rhs.range.location
            }
            return lhs.range.length > rhs.range.length
        }

        var tokens: [NoteContentToken] = []
        var cursor = 0

        for candidate in sortedCandidates {
            guard candidate.range.location >= cursor else {
                continue
            }

            if candidate.range.location > cursor {
                let textRange = NSRange(location: cursor, length: candidate.range.location - cursor)
                let textChunk = nsContent.substring(with: textRange)
                if !textChunk.isEmpty {
                    tokens.append(NoteContentToken(type: .text, value: textChunk))
                }
            }

            if let token = token(from: candidate) {
                tokens.append(token)
            } else {
                tokens.append(NoteContentToken(type: .text, value: candidate.value))
            }
            cursor = candidate.range.location + candidate.range.length
        }

        if cursor < nsContent.length {
            let tail = nsContent.substring(from: cursor)
            if !tail.isEmpty {
                tokens.append(NoteContentToken(type: .text, value: tail))
            }
        }

        return mergeConsecutiveTextTokens(tokens)
    }

    static func njumpURL(for nostrURIOrIdentifier: String) -> URL? {
        guard let identifier = nostrIdentifier(from: nostrURIOrIdentifier) else { return nil }
        guard !identifier.isEmpty else { return nil }
        return URL(string: "https://nlink.to/\(identifier)")
    }
    
    static func hashtagActionURL(for tokenValue: String) -> URL? {
        guard let normalized = normalizedHashtag(from: tokenValue), !normalized.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "x21-hashtag"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "t", value: normalized)]
        return components.url
    }
    
    static func hashtagFromActionURL(_ url: URL) -> String? {
        guard url.scheme == "x21-hashtag" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let value = components.queryItems?.first(where: { $0.name == "t" })?.value
        guard let value, !value.isEmpty else { return nil }
        return value.lowercased()
    }

    static func lastWebsiteURL(in tokens: [NoteContentToken]) -> URL? {
        for token in tokens.reversed() where token.type == .url {
            if let url = URL(string: token.value) {
                return url
            }
        }
        return nil
    }

    private static func token(from candidate: Candidate) -> NoteContentToken? {
        switch candidate.type {
        case .nostrURI:
            guard let identifier = nostrIdentifier(from: candidate.value) else {
                return NoteContentToken(type: .text, value: candidate.value)
            }
            if isProfileIdentifier(identifier) {
                return NoteContentToken(type: .nostrMention, value: identifier)
            }
            if isEventIdentifier(identifier) {
                return NoteContentToken(type: .nostrEvent, value: identifier)
            }
            if isRelayIdentifier(identifier) {
                // Keep relay references tappable through the same external flow used for other nostr references.
                return NoteContentToken(type: .nostrMention, value: identifier)
            }
            return NoteContentToken(type: .text, value: candidate.value)
        case .hashtag:
            guard let normalized = normalizedHashtag(from: candidate.value), !normalized.isEmpty else {
                return NoteContentToken(type: .text, value: candidate.value)
            }
            return NoteContentToken(type: .hashtag, value: "#\(normalized)")
        case .emoji:
            return NoteContentToken(type: .emoji, value: candidate.value)
        case .websocketURL:
            return NoteContentToken(type: .websocketURL, value: candidate.value)
        case .httpURL:
            let mediaType = classifyMediaType(urlString: candidate.value, mimeType: nil)
            switch mediaType {
            case .image:
                return NoteContentToken(type: .image, value: candidate.value)
            case .video:
                return NoteContentToken(type: .video, value: candidate.value)
            case .audio:
                return NoteContentToken(type: .audio, value: candidate.value)
            case .none:
                return NoteContentToken(type: .url, value: candidate.value)
            }
        }
    }

    private static func mergeConsecutiveTextTokens(_ tokens: [NoteContentToken]) -> [NoteContentToken] {
        var merged: [NoteContentToken] = []

        for token in tokens {
            guard token.type == .text else {
                merged.append(token)
                continue
            }

            if let last = merged.last, last.type == .text {
                merged[merged.count - 1] = NoteContentToken(type: .text, value: last.value + token.value)
            } else {
                merged.append(token)
            }
        }

        return merged
    }

    private static func trimTrailingPunctuation(_ raw: String) -> String {
        var scalarView = raw.unicodeScalars
        while let last = scalarView.last, trailingURLPunctuation.contains(last) {
            scalarView.removeLast()
        }
        return String(String.UnicodeScalarView(scalarView))
    }

    private static func nostrIdentifier(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("nostr:") {
            let identifier = String(lowered.dropFirst("nostr:".count))
            return identifier.isEmpty ? nil : identifier
        }
        return lowered
    }

    private static func isProfileIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("npub1") || identifier.hasPrefix("nprofile1")
    }

    private static func isEventIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("note1") || identifier.hasPrefix("nevent1") || identifier.hasPrefix("naddr1")
    }

    private static func isRelayIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("nrelay1")
    }
    
    private static func normalizedHashtag(from tokenValue: String) -> String? {
        let trimmed = tokenValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withoutHash: String
        if trimmed.hasPrefix("#") {
            withoutHash = String(trimmed.dropFirst())
        } else {
            withoutHash = trimmed
        }
        let normalized = withoutHash.lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func appendImetaMediaIfNeeded(
        tokens: [NoteContentToken],
        tags: [[String]]
    ) -> [NoteContentToken] {
        var result = tokens
        var existingURLs = Set(
            tokens.filter { $0.type != .text }.map(\.value)
        )

        for tag in tags {
            guard let name = tag.first?.lowercased(), name == "imeta" else { continue }

            var urlString: String?
            var mimeType: String?
            for value in tag.dropFirst() {
                if value.hasPrefix("url ") {
                    urlString = String(value.dropFirst(4))
                } else if value.hasPrefix("m ") {
                    mimeType = String(value.dropFirst(2)).lowercased()
                }
            }

            guard let urlString, !urlString.isEmpty else { continue }
            guard !existingURLs.contains(urlString) else { continue }

            let mediaType = classifyMediaType(urlString: urlString, mimeType: mimeType)
            let tokenType: NoteContentTokenType
            switch mediaType {
            case .image:
                tokenType = .image
            case .video:
                tokenType = .video
            case .audio:
                tokenType = .audio
            case .none:
                tokenType = .url
            }

            if let last = result.last, last.type != .text {
                result.append(NoteContentToken(type: .text, value: "\n"))
            }
            result.append(NoteContentToken(type: tokenType, value: urlString))
            existingURLs.insert(urlString)
        }

        return mergeConsecutiveTextTokens(result)
    }

    private static func appendQuotedReferencesIfNeeded(
        tokens: [NoteContentToken],
        tags: [[String]]
    ) -> [NoteContentToken] {
        var result = tokens
        var existingReferences = Set(
            tokens
                .filter { $0.type == .nostrEvent }
                .map { normalizeReferenceValue($0.value) }
                .filter { !$0.isEmpty }
        )

        for tag in tags {
            guard tag.count > 1 else { continue }
            guard let name = tag.first?.lowercased() else { continue }

            let value = tag[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            let marker = tag.count > 3 ? tag[3].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : ""
            let isQuoteReferenceTag = name == "q"
            let isMentionedEventTag = name == "e" && marker == "mention"
            let isMentionedAddressTag = name == "a" && marker == "mention"
            guard isQuoteReferenceTag || isMentionedEventTag || isMentionedAddressTag else { continue }

            let normalized = normalizeReferenceValue(value)
            guard isRenderableReference(normalized) else { continue }
            guard existingReferences.insert(normalized).inserted else { continue }

            if let last = result.last, last.type != .text {
                result.append(NoteContentToken(type: .text, value: "\n"))
            }
            result.append(NoteContentToken(type: .nostrEvent, value: normalized))
        }

        return mergeConsecutiveTextTokens(result)
    }

    private static func normalizeReferenceValue(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("nostr:") {
            return String(trimmed.dropFirst("nostr:".count))
        }
        return trimmed
    }

    private static func isRenderableReference(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }

        if isEventIdentifier(value) {
            return true
        }

        // Hex event IDs often appear in `q`/`e` tags.
        if value.count == 64,
           value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdef").contains($0) }) {
            return true
        }

        // Replaceable coordinates from `a`/`q` tags: "<kind>:<pubkey>:<identifier>".
        let pieces = value.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        if pieces.count == 3,
           Int(pieces[0]) != nil,
           pieces[1].count == 64 {
            return true
        }

        return false
    }

    private enum ParsedMediaType {
        case image
        case video
        case audio
    }

    private static func classifyMediaType(urlString: String, mimeType: String?) -> ParsedMediaType? {
        if let mimeType {
            if mimeType.hasPrefix("image/") { return .image }
            if mimeType.hasPrefix("video/") { return .video }
            if mimeType.hasPrefix("audio/") { return .audio }
        }

        guard let url = URL(string: urlString) else { return nil }
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        return nil
    }
}
