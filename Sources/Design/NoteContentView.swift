import AVFoundation
import AVKit
import LinkPresentation
import NostrSDK
import SwiftUI
import UIKit

enum NoteContentMediaLayout {
    case feed
    case detailCarousel
}

struct NoteContentView: View {
    private enum RenderPart {
        case inlineTokens([NoteContentToken])
        case imageGallery([URL])
        case video(URL)
        case audio(URL)
        case nostrEventReference(String)
    }

    private struct MentionMetadataDecoder: MetadataCoding {}
    fileprivate struct ParsedContent {
        let tokens: [NoteContentToken]
        let websitePreviewURL: URL?
        let mentionIdentifiers: [String]
        let emojiTagURLs: [String: URL]
    }

    private let tokens: [NoteContentToken]
    private let parts: [RenderPart]
    private let websitePreviewURL: URL?
    private let sourceEvent: NostrEvent
    private let onHashtagTap: ((String) -> Void)?
    private let onReferencedEventTap: ((FeedItem) -> Void)?
    private let mediaLayout: NoteContentMediaLayout
    private let reactionCount: Int
    private let commentCount: Int
    private let embedDepth: Int
    private let mentionIdentifiers: [String]
    private let emojiTagURLs: [String: URL]
    @EnvironmentObject private var appSettings: AppSettingsStore

    @State private var mentionLabels: [String: String] = [:]
    @State private var emojiImages: [String: UIImage] = [:]
    @State private var isExpanded = false
    @State private var revealsMediaInTextOnlyMode = false

    private static let collapsedPreviewCharacterLimit = 520
    private static let collapsedPreviewLineLimit = 9
    private static let maxEmbeddedReferenceDepth = 1
    private static let parsedContentCache = NoteParsedContentCache.shared

    init(
        event: NostrEvent,
        mediaLayout: NoteContentMediaLayout = .feed,
        reactionCount: Int = 0,
        commentCount: Int = 0,
        embedDepth: Int = 0,
        onHashtagTap: ((String) -> Void)? = nil,
        onReferencedEventTap: ((FeedItem) -> Void)? = nil
    ) {
        sourceEvent = event
        let parsedContent = Self.parsedContentCache.parsedContent(for: event) {
            let renderEvent = Self.renderEvent(for: event)
            let parsedTokens = NoteContentParser.tokenize(event: renderEvent)
            return ParsedContent(
                tokens: parsedTokens,
                websitePreviewURL: NoteContentParser.lastWebsiteURL(in: parsedTokens),
                mentionIdentifiers: Self.collectMentionIdentifiers(tokens: parsedTokens),
                emojiTagURLs: Self.parseEmojiTagURLs(from: renderEvent.tags)
            )
        }

        tokens = parsedContent.tokens
        parts = Self.buildRenderParts(tokens: parsedContent.tokens)
        mentionIdentifiers = parsedContent.mentionIdentifiers
        emojiTagURLs = parsedContent.emojiTagURLs
        websitePreviewURL = parsedContent.websitePreviewURL
        self.onHashtagTap = onHashtagTap
        self.onReferencedEventTap = onReferencedEventTap
        self.mediaLayout = mediaLayout
        self.reactionCount = reactionCount
        self.commentCount = commentCount
        self.embedDepth = embedDepth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(renderedParts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .inlineTokens(let inlineTokens):
                    if mediaLayout == .detailCarousel {
                        inlineText(from: inlineTokens)
                            .font(.body)
                            .lineLimit(isCollapsedPreviewActive ? Self.collapsedPreviewLineLimit : nil)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                            .textSelection(.enabled)
                    } else {
                        inlineText(from: inlineTokens)
                            .font(.body)
                            .lineLimit(isCollapsedPreviewActive ? Self.collapsedPreviewLineLimit : nil)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                            .textSelection(.disabled)
                    }
                case .imageGallery(let imageURLs):
                    if appSettings.textOnlyMode && !revealsMediaInTextOnlyMode {
                        NoteMediaPlaceholderView(
                            systemImage: "photo.on.rectangle.angled",
                            text: imageURLs.count == 1 ? "Tap to load image" : "Tap to load \(imageURLs.count) images",
                            action: {
                                revealsMediaInTextOnlyMode = true
                            }
                        )
                    } else {
                        NoteImageGalleryView(
                            imageURLs: imageURLs,
                            layout: mediaLayout,
                            sourceEvent: sourceEvent,
                            reactionCount: reactionCount,
                            commentCount: commentCount
                        )
                    }
                case .video(let url):
                    if appSettings.textOnlyMode {
                        NoteMediaPlaceholderView(
                            systemImage: "video.slash",
                            text: "Video hidden in Text Only Mode"
                        )
                    } else {
                        NoteVideoPlayerView(url: url, layout: mediaLayout)
                    }
                case .audio(let url):
                    if appSettings.textOnlyMode {
                        NoteMediaPlaceholderView(
                            systemImage: "speaker.slash",
                            text: "Audio hidden in Text Only Mode"
                        )
                    } else {
                        NoteAudioPlayerView(url: url)
                    }
                case .nostrEventReference(let nostrURI):
                    if embedDepth < Self.maxEmbeddedReferenceDepth {
                        NostrEventReferenceCardView(
                            nostrURI: nostrURI,
                            embedDepth: embedDepth + 1,
                            onHashtagTap: onHashtagTap,
                            onOpenThread: onReferencedEventTap
                        )
                    } else {
                        NostrEventReferenceFallbackView(nostrURI: nostrURI)
                    }
                }
            }

            if !isCollapsedPreviewActive, let websitePreviewURL, !appSettings.textOnlyMode {
                WebsiteLinkCardView(url: websitePreviewURL)
            }

            if isCollapsedPreviewActive {
                collapseMoreOverlay
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            if let hashtag = NoteContentParser.hashtagFromActionURL(url) {
                onHashtagTap?(hashtag)
                return .handled
            }
            return .systemAction(url)
        })
        .task {
            async let mentionsTask: Void = resolveMentionLabelsIfNeeded()
            async let emojiTask: Void = loadCustomEmojiImagesIfNeeded()
            _ = await (mentionsTask, emojiTask)
        }
    }

    private var collapseMoreOverlay: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [
                    Color.clear,
                    collapseOverlayBackgroundColor.opacity(0.88),
                    collapseOverlayBackgroundColor
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 34)

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    isExpanded = true
                }
            } label: {
                Text("More")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color(.separator).opacity(0.3), lineWidth: 0.6)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show full note")
        }
        .padding(.top, -12)
    }

    private var isCollapsedPreviewActive: Bool {
        shouldCollapseLongNote && !isExpanded
    }

    private var collapseOverlayBackgroundColor: Color {
        if embedDepth > 0 {
            return Color(.secondarySystemBackground)
        }
        return Color(.systemBackground)
    }

    private var shouldCollapseLongNote: Bool {
        inlineCharacterCount > Self.collapsedPreviewCharacterLimit
    }

    private var inlineCharacterCount: Int {
        tokens.reduce(into: 0) { partialResult, token in
            switch token.type {
            case .image, .video, .audio, .nostrEvent:
                break
            case .text, .url, .websocketURL, .nostrMention, .hashtag, .emoji:
                partialResult += token.value.count
            }
        }
    }

    private var renderedParts: [RenderPart] {
        guard isCollapsedPreviewActive else { return parts }
        return Self.previewParts(
            from: parts,
            maxCharacters: Self.collapsedPreviewCharacterLimit
        )
    }

    private static func previewParts(
        from parts: [RenderPart],
        maxCharacters: Int
    ) -> [RenderPart] {
        var output: [RenderPart] = []
        var remaining = maxCharacters
        var renderedAny = false

        for part in parts {
            guard remaining > 0 else { break }

            switch part {
            case .inlineTokens(let inlineTokens):
                let preview = previewInlineTokens(inlineTokens, remainingCharacters: remaining)
                if !preview.tokens.isEmpty {
                    output.append(.inlineTokens(preview.tokens))
                    renderedAny = true
                    remaining -= preview.charactersUsed
                }
                if preview.didTruncate {
                    return output
                }
            case .imageGallery, .video, .audio, .nostrEventReference:
                if !renderedAny {
                    output.append(part)
                }
                return output
            }
        }

        return output
    }

    private static func previewInlineTokens(
        _ tokens: [NoteContentToken],
        remainingCharacters: Int
    ) -> (tokens: [NoteContentToken], charactersUsed: Int, didTruncate: Bool) {
        guard remainingCharacters > 0 else {
            return ([], 0, true)
        }

        var output: [NoteContentToken] = []
        var used = 0

        for token in tokens {
            let count = token.value.count
            guard count > 0 else { continue }

            if used + count <= remainingCharacters {
                output.append(token)
                used += count
                continue
            }

            let remaining = max(remainingCharacters - used, 0)
            if remaining > 0 {
                let prefix = String(token.value.prefix(remaining))
                let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedPrefix.isEmpty {
                    output.append(NoteContentToken(type: .text, value: "\(trimmedPrefix)…"))
                    used = remainingCharacters
                }
            }

            return (output, used, true)
        }

        return (output, used, false)
    }

    private static func buildRenderParts(tokens: [NoteContentToken]) -> [RenderPart] {
        var parts: [RenderPart] = []
        var inlineBuffer: [NoteContentToken] = []
        var index = 0

        func flushInlineBuffer(trimTrailingWhitespace: Bool = false) {
            guard !inlineBuffer.isEmpty else { return }
            let outputTokens = trimTrailingWhitespace
                ? trimTrailingInlineWhitespace(inlineBuffer)
                : inlineBuffer
            guard !outputTokens.isEmpty else {
                inlineBuffer.removeAll(keepingCapacity: true)
                return
            }
            parts.append(.inlineTokens(outputTokens))
            inlineBuffer.removeAll(keepingCapacity: true)
        }

        while index < tokens.count {
            let token = tokens[index]

            switch token.type {
            case .image:
                flushInlineBuffer(trimTrailingWhitespace: true)
                var imageURLs: [URL] = []
                while index < tokens.count {
                    let currentToken = tokens[index]

                    if currentToken.type == .image,
                       let url = URL(string: currentToken.value) {
                        imageURLs.append(url)
                        index += 1
                        continue
                    }

                    if currentToken.type == .text,
                       currentToken.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       index + 1 < tokens.count,
                       tokens[index + 1].type == .image {
                        index += 1
                        continue
                    }

                    break
                }
                if !imageURLs.isEmpty {
                    parts.append(.imageGallery(imageURLs))
                }
                continue
            case .video:
                flushInlineBuffer(trimTrailingWhitespace: true)
                if let url = URL(string: token.value) {
                    parts.append(.video(url))
                }
            case .audio:
                flushInlineBuffer(trimTrailingWhitespace: true)
                if let url = URL(string: token.value) {
                    parts.append(.audio(url))
                }
            case .nostrEvent:
                flushInlineBuffer(trimTrailingWhitespace: true)
                parts.append(.nostrEventReference(token.value))
            case .text, .url, .websocketURL, .nostrMention, .hashtag, .emoji:
                inlineBuffer.append(token)
            }

            index += 1
        }

        flushInlineBuffer()
        return parts
    }

    private static func trimTrailingInlineWhitespace(_ tokens: [NoteContentToken]) -> [NoteContentToken] {
        guard !tokens.isEmpty else { return [] }
        var trimmed = tokens

        while let last = trimmed.last {
            guard last.type == .text else { break }

            let stripped = last.value.replacingOccurrences(
                of: "\\s+$",
                with: "",
                options: .regularExpression
            )

            if stripped.isEmpty {
                trimmed.removeLast()
                continue
            }

            if stripped != last.value {
                trimmed[trimmed.count - 1] = NoteContentToken(type: .text, value: stripped)
            }
            break
        }

        return trimmed
    }

    private func inlineText(from tokens: [NoteContentToken]) -> Text {
        tokens.reduce(Text("")) { partial, token in
            partial + textSegment(for: token)
        }
    }

    private func textSegment(for token: NoteContentToken) -> Text {
        if token.type == .emoji, let inlineEmoji = emojiInlineText(for: token.value) {
            return inlineEmoji
        }

        return Text(attributedSegment(for: token))
    }

    private func attributedSegment(for token: NoteContentToken) -> AttributedString {
        var segment = AttributedString(displayValue(for: token))

        switch token.type {
        case .url:
            if let url = URL(string: token.value) {
                segment.link = url
                segment.foregroundColor = .accentColor
            }
        case .nostrMention:
            let normalized = Self.normalizeMentionIdentifier(token.value)
            if let url = NoteContentParser.njumpURL(for: normalized) {
                segment.link = url
                segment.foregroundColor = .accentColor
            }
        case .hashtag:
            if let url = NoteContentParser.hashtagActionURL(for: token.value) {
                segment.link = url
                segment.foregroundColor = .accentColor
            }
        case .websocketURL:
            segment.foregroundColor = .secondary
        case .text:
            break
        case .emoji:
            break
        case .nostrEvent, .image, .video, .audio:
            break
        }

        return segment
    }

    private func displayValue(for token: NoteContentToken) -> String {
        guard token.type == .nostrMention else { return Self.softWrapValue(token.value) }

        let normalized = Self.normalizeMentionIdentifier(token.value)
        if let label = mentionLabels[normalized] {
            return Self.softWrapValue(label)
        }
        return Self.softWrapValue("@\(Self.fallbackMentionToken(for: normalized))")
    }

    private static let softBreakSeparators = CharacterSet(charactersIn: "/._-?&=#:%+")

    private static func softWrapValue(_ value: String) -> String {
        guard value.count > 36 else { return value }

        let softBreak = "\u{200B}"
        var wrapped = ""
        var nonBreakingRunLength = 0

        for scalar in value.unicodeScalars {
            wrapped.append(String(scalar))

            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                nonBreakingRunLength = 0
                continue
            }

            if softBreakSeparators.contains(scalar) {
                wrapped.append(softBreak)
                nonBreakingRunLength = 0
                continue
            }

            nonBreakingRunLength += 1
            if nonBreakingRunLength >= 24 {
                wrapped.append(softBreak)
                nonBreakingRunLength = 0
            }
        }

        return wrapped
    }

    private func resolveMentionLabelsIfNeeded() async {
        guard !mentionIdentifiers.isEmpty else {
            await MainActor.run {
                mentionLabels = [:]
            }
            return
        }

        var resolvedLabels: [String: String] = [:]
        var pubkeyByIdentifier: [String: String] = [:]
        var pubkeys: [String] = []

        for identifier in mentionIdentifiers {
            resolvedLabels[identifier] = "@\(Self.fallbackMentionToken(for: identifier))"

            if let pubkey = Self.mentionedPubkey(from: identifier) {
                pubkeyByIdentifier[identifier] = pubkey
                pubkeys.append(pubkey)
            }
        }

        let uniquePubkeys = Array(Set(pubkeys))
        if !uniquePubkeys.isEmpty {
            var profilesByPubkey: [String: NostrProfile] = [:]
            let cached = await ProfileCache.shared.resolve(pubkeys: uniquePubkeys)
            profilesByPubkey.merge(cached.hits, uniquingKeysWith: { _, latest in latest })

            if !cached.missing.isEmpty {
                let relayURLs = await MainActor.run {
                    let relays = RelaySettingsStore.shared.readRelayURLs
                    return relays.isEmpty
                        ? RelaySettingsStore.defaultReadRelayURLs.compactMap(URL.init(string:))
                        : relays
                }

                let fetchedProfiles = await NostrFeedService().fetchProfiles(
                    relayURLs: relayURLs,
                    pubkeys: cached.missing
                )
                profilesByPubkey.merge(fetchedProfiles, uniquingKeysWith: { existing, _ in existing })
            }

            for (identifier, pubkey) in pubkeyByIdentifier {
                guard let profile = profilesByPubkey[pubkey] else { continue }
                resolvedLabels[identifier] = mentionLabel(from: profile, pubkey: pubkey)
            }
        }

        await MainActor.run {
            mentionLabels = resolvedLabels
        }
    }

    private func mentionLabel(from profile: NostrProfile, pubkey: String) -> String {
        if let name = profile.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return "@\(name)"
        }
        if let displayName = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            return "@\(displayName)"
        }
        return "@\(Self.fallbackMentionToken(for: pubkey))"
    }

    private static func collectMentionIdentifiers(tokens: [NoteContentToken]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for token in tokens where token.type == .nostrMention {
            let normalized = normalizeMentionIdentifier(token.value)
            guard !normalized.isEmpty else { continue }
            guard seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }

        return ordered
    }

    private static func parseEmojiTagURLs(from tags: [[String]]) -> [String: URL] {
        var result: [String: URL] = [:]

        for tag in tags {
            guard tag.count >= 3 else { continue }
            guard tag[0].lowercased() == "emoji" else { continue }

            let rawShortcode = tag[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let urlString = tag[2].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let shortcode = normalizedEmojiShortcode(from: rawShortcode), !urlString.isEmpty else { continue }
            guard let url = URL(string: urlString), url.scheme != nil else { continue }

            result[shortcode] = url
            result[shortcode.lowercased()] = url
        }

        return result
    }

    private func loadCustomEmojiImagesIfNeeded() async {
        guard !emojiTagURLs.isEmpty else {
            await MainActor.run {
                emojiImages = [:]
            }
            return
        }

        var nextImages = emojiImages
        for (shortcode, url) in emojiTagURLs where nextImages[shortcode] == nil {
            if let image = await CustomEmojiImageLoader.shared.image(for: url) {
                nextImages[shortcode] = image
            }
        }

        await MainActor.run {
            emojiImages = nextImages
        }
    }

    private func emojiInlineText(for tokenValue: String) -> Text? {
        guard let shortcode = Self.shortcode(from: tokenValue) else { return nil }

        let lowered = shortcode.lowercased()
        guard let baseImage = emojiImages[shortcode] ?? emojiImages[lowered] else { return nil }

        let lineHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
        let emojiSize = max(16, floor(lineHeight * 0.95))
        let scaledImage = baseImage.preparingThumbnail(
            of: CGSize(width: emojiSize, height: emojiSize)
        ) ?? baseImage
        return Text(Image(uiImage: scaledImage).renderingMode(.original))
            .baselineOffset(-2)
    }

    private static func shortcode(from tokenValue: String) -> String? {
        normalizedEmojiShortcode(from: tokenValue)
    }

    private static func normalizedEmojiShortcode(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix(":"), trimmed.hasSuffix(":"), trimmed.count >= 3 {
            let inner = trimmed.dropFirst().dropLast()
            let shortcode = String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
            return shortcode.isEmpty ? nil : shortcode
        }

        return trimmed
    }

    private static func renderEvent(for event: NostrEvent) -> NostrEvent {
        // Kind 6 reposts often carry a full JSON event in `content` (NIP-18).
        // We render the embedded event body/media so users don't see raw JSON text.
        guard event.kind == 6 || event.kind == 16 else { return event }
        guard let embedded = decodeEmbeddedEvent(from: event.content) else { return event }
        guard embedded.kind != 6 && embedded.kind != 16 else { return event }
        return embedded
    }

    private static func decodeEmbeddedEvent(from content: String) -> NostrEvent? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard let id = object["id"] as? String,
              let pubkey = object["pubkey"] as? String,
              let createdAt = object["created_at"] as? Int,
              let kind = object["kind"] as? Int,
              let content = object["content"] as? String,
              let sig = object["sig"] as? String else {
            return nil
        }

        let rawTags = object["tags"] as? [[Any]] ?? []
        let tags = rawTags.map { tag in
            tag.map { element in
                if let string = element as? String {
                    return string
                }
                return String(describing: element)
            }
        }

        return NostrEvent(
            id: id,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: sig
        )
    }

    private static func normalizeMentionIdentifier(_ raw: String) -> String {
        let lowered = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if lowered.hasPrefix("nostr:") {
            return String(lowered.dropFirst("nostr:".count))
        }
        return lowered
    }

    private static func mentionedPubkey(from identifier: String) -> String? {
        let normalized = normalizeMentionIdentifier(identifier)
        if normalized.hasPrefix("npub1") {
            return PublicKey(npub: normalized)?.hex.lowercased()
        }
        if normalized.hasPrefix("nprofile1") {
            let decoder = MentionMetadataDecoder()
            let metadata = try? decoder.decodedMetadata(from: normalized)
            return metadata?.pubkey?.lowercased()
        }
        return nil
    }

    private static func fallbackMentionToken(for identifier: String) -> String {
        if let pubkey = mentionedPubkey(from: identifier) {
            return String(pubkey.prefix(8))
        }

        let normalized = normalizeMentionIdentifier(identifier)
        if normalized.count > 14 {
            return "\(normalized.prefix(10))...\(normalized.suffix(4))"
        }
        return normalized
    }
}

private final class NoteParsedContentCache {
    static let shared = NoteParsedContentCache()

    private let maxEntries = 2_000
    private var entries: [String: NoteContentView.ParsedContent] = [:]
    private var recency: [String] = []
    private let lock = NSLock()

    func parsedContent(
        for event: NostrEvent,
        builder: () -> NoteContentView.ParsedContent
    ) -> NoteContentView.ParsedContent {
        let cacheKey = event.id.lowercased()

        lock.lock()
        if let cached = entries[cacheKey] {
            touch(cacheKey)
            lock.unlock()
            return cached
        }
        lock.unlock()

        let parsed = builder()

        lock.lock()
        entries[cacheKey] = parsed
        touch(cacheKey)
        if recency.count > maxEntries, let oldest = recency.first {
            recency.removeFirst()
            entries[oldest] = nil
        }
        lock.unlock()

        return parsed
    }

    private func touch(_ key: String) {
        recency.removeAll(where: { $0 == key })
        recency.append(key)
    }
}

private struct NoteMediaPlaceholderView: View {
    let systemImage: String
    let text: String
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    placeholderContent(isActionable: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Loads media for this note")
            } else {
                placeholderContent(isActionable: false)
            }
        }
    }

    private func placeholderContent(isActionable: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(isActionable ? Color.accentColor : Color.secondary)
            Text(text)
                .font(.footnote.weight(isActionable ? .semibold : .regular))
                .foregroundStyle(isActionable ? Color.accentColor : Color.secondary)
                .lineLimit(nil)
            Spacer(minLength: 0)
            if isActionable {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    (isActionable ? Color.accentColor.opacity(0.35) : Color(.separator).opacity(0.35)),
                    lineWidth: 0.5
                )
        )
    }
}

private struct NoteImageGalleryView: View {
    private struct SelectedImage: Identifiable {
        let id: Int
    }

    let imageURLs: [URL]
    let layout: NoteContentMediaLayout
    let sourceEvent: NostrEvent
    let reactionCount: Int
    let commentCount: Int
    @State private var selectedImage: SelectedImage?
    @State private var visibleImageIndex = 0

    var body: some View {
        Group {
            if layout == .feed {
                feedGallery
            } else if imageURLs.count == 1 {
                singleImageCell(url: imageURLs[0], index: 0)
            } else {
                pagedGallery
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fullScreenCover(item: $selectedImage) { selected in
            NoteImageFullscreenViewer(
                urls: imageURLs,
                sourceEvent: sourceEvent,
                initialIndex: selected.id,
                reactionCount: reactionCount,
                commentCount: commentCount
            )
        }
    }

    private var singleImageMaxHeight: CGFloat {
        layout == .detailCarousel ? 620 : 520
    }

    private var multiImageHeight: CGFloat {
        layout == .detailCarousel ? 460 : 340
    }

    private var mediaCornerRadius: CGFloat {
        layout == .feed ? 18 : 12
    }

    private var feedGalleryHeight: CGFloat {
        imageURLs.count == 1 ? 360 : 340
    }

    private var feedGallerySpacing: CGFloat {
        6
    }

    private var feedGallery: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let tileWidth = feedTileWidth(availableWidth: width)

            if imageURLs.count == 1, let url = imageURLs.first {
                feedTile(
                    url: url,
                    index: 0,
                    width: width,
                    height: feedGalleryHeight
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: feedGallerySpacing) {
                        ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, url in
                            feedTile(
                                url: url,
                                index: index,
                                width: tileWidth,
                                height: feedGalleryHeight
                            )
                        }
                    }
                    .frame(height: feedGalleryHeight, alignment: .leading)
                }
            }
        }
        .frame(height: feedGalleryHeight)
    }

    private func feedTileWidth(availableWidth: CGFloat) -> CGFloat {
        let proposedWidth = availableWidth * 0.74
        return max(min(proposedWidth, 360), 220)
    }

    private func feedTile(url: URL, index: Int, width: CGFloat, height: CGFloat) -> some View {
        NoteFeedImageTileView(
            url: url,
            cornerRadius: mediaCornerRadius,
            width: width,
            height: height,
            onTap: {
                selectedImage = SelectedImage(id: index)
            }
        )
    }

    private var pagedGallery: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)

            TabView(selection: $visibleImageIndex) {
                ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, url in
                    NoteSingleImageCellView(
                        url: url,
                        maxHeight: multiImageHeight,
                        cornerRadius: mediaCornerRadius,
                        onTap: {
                            selectedImage = SelectedImage(id: index)
                        }
                    )
                    .frame(width: width, height: multiImageHeight)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(width: width, height: multiImageHeight, alignment: .top)
        }
        .frame(height: multiImageHeight)
    }

    private func singleImageCell(url: URL, index: Int) -> some View {
        NoteSingleImageCellView(
            url: url,
            maxHeight: singleImageMaxHeight,
            cornerRadius: mediaCornerRadius,
            onTap: {
                selectedImage = SelectedImage(id: index)
            }
        )
    }

}

private struct NoteFeedImageTileView: View {
    let url: URL
    let cornerRadius: CGFloat
    let width: CGFloat
    let height: CGFloat
    let onTap: () -> Void

    @State private var loadedImage: UIImage?
    @State private var didFailLoading = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let loadedImage {
                    Image(uiImage: loadedImage)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .frame(width: width, height: height)
                } else if didFailLoading {
                    Color(.secondarySystemBackground)
                        .frame(width: width, height: height)
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else {
                    Color(.secondarySystemBackground)
                        .frame(width: width, height: height)
                    ProgressView()
                }
            }
            .frame(width: width, height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(width: width, height: height)
        .task(id: url) {
            await loadImageIfNeeded()
        }
    }

    @MainActor
    private func loadImageIfNeeded() async {
        guard loadedImage == nil, !didFailLoading else { return }
        if let image = await NoteMediaImageLoader.shared.image(for: url) {
            loadedImage = image
            didFailLoading = false
        } else {
            didFailLoading = true
        }
    }
}

private struct NoteSingleImageCellView: View {
    let url: URL
    let maxHeight: CGFloat
    let cornerRadius: CGFloat
    let onTap: () -> Void

    @State private var loadedImage: UIImage?
    @State private var didFailLoading = false

    var body: some View {
        Button(action: onTap) {
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
                    .frame(
                        maxWidth: preferredImageMaxWidth,
                        maxHeight: maxHeight,
                        alignment: .center
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else if didFailLoading {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: url) {
            await loadImageIfNeeded()
        }
    }

    private var preferredImageMaxWidth: CGFloat {
        guard let loadedImage else { return .infinity }
        return loadedImage.size.width > 0 ? loadedImage.size.width : .infinity
    }

    @MainActor
    private func loadImageIfNeeded() async {
        guard loadedImage == nil, !didFailLoading else { return }
        if let image = await NoteMediaImageLoader.shared.image(for: url) {
            loadedImage = image
            didFailLoading = false
        } else {
            didFailLoading = true
        }
    }
}

private struct NoteImageFullscreenViewer: View {
    let urls: [URL]
    let sourceEvent: NostrEvent
    let reactionCount: Int
    let commentCount: Int
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reactionStats = NoteReactionStatsService.shared
    @State private var selectedIndex: Int
    @State private var isShowingReshareSheet = false
    @State private var quoteDraft: ReshareQuoteDraft?
    @State private var isPublishingRepost = false
    @State private var repostStatusMessage: String?
    @State private var repostStatusIsError = false
    private let reshareService = ResharePublishService()
    private let reactionPublishService = NoteReactionPublishService()

    init(urls: [URL], sourceEvent: NostrEvent, initialIndex: Int, reactionCount: Int, commentCount: Int) {
        self.urls = urls
        self.sourceEvent = sourceEvent
        self.reactionCount = reactionCount
        self.commentCount = commentCount
        _selectedIndex = State(initialValue: max(0, min(initialIndex, max(urls.count - 1, 0))))
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedIndex) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    ZStack {
                        viewerBackgroundColor.ignoresSafeArea()
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .padding(16)
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(chromeForegroundColor.opacity(0.75))
                            case .empty:
                                ProgressView()
                                    .tint(chromeForegroundColor)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(doneButtonForegroundColor)
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(viewerNavigationBarColor, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                mediaActionBar
            }
        }
        .sheet(isPresented: $isShowingReshareSheet) {
            ReshareActionSheetView(
                isWorking: isPublishingRepost,
                statusMessage: repostStatusMessage,
                statusIsError: repostStatusIsError,
                onRepost: {
                    Task {
                        await publishRepost()
                    }
                },
                onQuote: {
                    quoteDraft = reshareService.buildQuoteDraft(
                        for: sourceEvent,
                        relayHintURL: effectiveReadRelayURLs.first
                    )
                    isShowingReshareSheet = false
                }
            )
        }
        .sheet(item: $quoteDraft) { draft in
            ComposeNoteSheet(
                currentAccountPubkey: auth.currentAccount?.pubkey,
                currentNsec: auth.currentNsec,
                writeRelayURLs: effectiveWriteRelayURLs,
                initialText: draft.initialText,
                initialAdditionalTags: draft.additionalTags,
                quotedEvent: draft.quotedEvent,
                quotedDisplayNameHint: draft.quotedDisplayNameHint,
                quotedHandleHint: draft.quotedHandleHint,
                quotedAvatarURLHint: draft.quotedAvatarURLHint
            )
        }
        .task {
            reactionStats.prefetch(events: [sourceEvent], relayURLs: effectiveReadRelayURLs)
        }
    }

    private var mediaActionBar: some View {
        HStack(spacing: 16) {
            ReactionButton(
                isLiked: isLikedByCurrentUser,
                count: visibleReactionCount,
                inactiveColor: chromeForegroundColor,
                minWidth: 36
            ) {
                Task {
                    await handleReactionTap()
                }
            }

            Button {
                // Thread-comment shortcut can be wired from parent context in a later pass.
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.right")
                    if commentCount > 0 {
                        Text("\(commentCount)")
                            .font(.footnote)
                    }
                }
                .foregroundStyle(chromeForegroundColor)
                .frame(minWidth: 36, minHeight: 28, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Comment")

            Button {
                repostStatusMessage = nil
                repostStatusIsError = false
                isShowingReshareSheet = true
            } label: {
                Image(systemName: "arrow.2.squarepath")
                    .foregroundStyle(chromeForegroundColor)
                    .frame(minWidth: 36, minHeight: 28, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Re-share")

            ShareLink(item: urls[selectedIndex]) {
                Image(systemName: "paperplane")
                    .foregroundStyle(chromeForegroundColor)
                    .frame(minWidth: 36, minHeight: 28, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share")
        }
        .font(.headline)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(actionBarBackground)
    }

    private var visibleReactionCount: Int {
        reactionStats.reactionCount(for: sourceEvent.id)
    }

    private var isLikedByCurrentUser: Bool {
        reactionStats.isReactedByCurrentUser(
            for: sourceEvent.id,
            currentPubkey: auth.currentAccount?.pubkey
        )
    }

    private var effectiveReadRelayURLs: [URL] {
        appSettings.effectiveReadRelayURLs(from: relaySettings.readRelayURLs)
    }

    private var effectiveWriteRelayURLs: [URL] {
        appSettings.effectiveWriteRelayURLs(
            from: relaySettings.writeRelayURLs,
            fallbackReadRelayURLs: effectiveReadRelayURLs
        )
    }

    private var viewerBackgroundColor: Color {
        colorScheme == .dark ? .black : Color(.systemBackground)
    }

    private var viewerNavigationBarColor: Color {
        colorScheme == .dark ? .black : Color(.systemBackground)
    }

    private var chromeForegroundColor: Color {
        colorScheme == .dark ? .white : .primary
    }

    private var doneButtonForegroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    @ViewBuilder
    private var actionBarBackground: some View {
        if colorScheme == .dark {
            Color.black.opacity(0.7)
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color(.systemGray6).opacity(0.5))
                )
        }
    }

    @MainActor
    private func handleReactionTap() async {
        let eventID = sourceEvent.id
        guard reactionStats.beginPublishingReaction(for: eventID) else { return }
        let existingReaction = reactionStats.currentUserReaction(
            for: eventID,
            currentPubkey: auth.currentAccount?.pubkey
        )
        let optimisticToggle = reactionStats.applyOptimisticToggle(
            for: eventID,
            currentPubkey: auth.currentAccount?.pubkey
        )
        if optimisticToggle != nil {
            AppHaptics.reactionTap()
        }
        defer {
            reactionStats.endPublishingReaction(for: eventID)
        }

        do {
            let result = try await reactionPublishService.toggleReaction(
                for: sourceEvent,
                existingReactionID: existingReaction?.id,
                currentNsec: auth.currentNsec,
                writeRelayURLs: effectiveWriteRelayURLs,
                relayHintURL: effectiveReadRelayURLs.first
            )

            switch result {
            case .liked(let reactionEvent):
                reactionStats.registerPublishedReaction(
                    reactionEvent,
                    targetEventID: eventID
                )
            case .unliked(let reactionID):
                reactionStats.registerDeletedReaction(
                    reactionID: reactionID,
                    targetEventID: eventID
                )
            }
        } catch {
            reactionStats.rollbackOptimisticToggle(for: eventID, snapshot: optimisticToggle)
            return
        }
    }

    @MainActor
    private func publishRepost() async {
        guard !isPublishingRepost else { return }
        isPublishingRepost = true
        repostStatusMessage = nil
        repostStatusIsError = false
        defer { isPublishingRepost = false }

        do {
            let relayCount = try await reshareService.publishRepost(
                of: sourceEvent,
                currentNsec: auth.currentNsec,
                writeRelayURLs: effectiveWriteRelayURLs,
                relayHintURL: effectiveReadRelayURLs.first
            )
            repostStatusMessage = "Reposted to \(relayCount) relay\(relayCount == 1 ? "" : "s")."
            repostStatusIsError = false

            try? await Task.sleep(nanoseconds: 450_000_000)
            isShowingReshareSheet = false
        } catch {
            repostStatusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            repostStatusIsError = true
        }
    }
}

private struct NoteVideoPlayerView: View {
    let url: URL
    let layout: NoteContentMediaLayout
    @EnvironmentObject private var appSettings: AppSettingsStore
    @State private var player: AVPlayer
    @State private var videoAspectRatio: CGFloat = 16.0 / 9.0
    @State private var videoNaturalWidth: CGFloat?

    init(url: URL, layout: NoteContentMediaLayout) {
        self.url = url
        self.layout = layout
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .aspectRatio(videoAspectRatio, contentMode: .fit)
            .frame(
                maxWidth: preferredVideoMaxWidth,
                maxHeight: maxVideoHeight,
                alignment: .leading
            )
            .clipShape(RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous))
            .task(id: url) {
                await loadVideoAspectRatio()
            }
            .onAppear {
                applyPlaybackPolicy()
            }
            .onChange(of: appSettings.autoplayVideos) { _, _ in
                applyPlaybackPolicy()
            }
            .onDisappear {
                player.pause()
            }
    }

    private var maxVideoHeight: CGFloat {
        min(UIScreen.main.bounds.height * 0.72, 620)
    }

    private var preferredVideoMaxWidth: CGFloat {
        if let videoNaturalWidth, videoNaturalWidth > 0 {
            return videoNaturalWidth
        }
        return .infinity
    }

    private var mediaCornerRadius: CGFloat {
        layout == .feed ? 18 : 12
    }

    private func loadVideoAspectRatio() async {
        let asset = AVURLAsset(url: url)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return }

            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            let transformedSize = naturalSize.applying(preferredTransform)

            let width = abs(transformedSize.width)
            let height = abs(transformedSize.height)
            guard width > 0, height > 0 else { return }

            let ratio = max(0.4, min(width / height, 3.0))
            await MainActor.run {
                videoAspectRatio = ratio
                videoNaturalWidth = width
            }
        } catch {
            // Keep default fallback ratio when metadata cannot be loaded.
        }
    }

    private func applyPlaybackPolicy() {
        if appSettings.autoplayVideos {
            player.isMuted = true
            player.play()
        } else {
            player.pause()
        }
    }
}

private struct NoteAudioPlayerView: View {
    let url: URL
    @State private var player: AVPlayer
    @State private var isPlaying = false

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayFileName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(url.host ?? "Audio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Link(destination: url) {
                Image(systemName: "arrow.up.right.square")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open audio in browser")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .onReceive(
            NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
        ) { notification in
            guard let endedItem = notification.object as? AVPlayerItem,
                  endedItem == player.currentItem else { return }
            isPlaying = false
            player.seek(to: .zero)
        }
        .onDisappear {
            player.pause()
            isPlaying = false
        }
    }

    private var displayFileName: String {
        let candidate = url.lastPathComponent
        if candidate.isEmpty {
            return "Audio"
        }
        return candidate
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }
}

private actor EmbeddedReferencedNoteCache {
    static let shared = EmbeddedReferencedNoteCache()

    private enum CachedResult {
        case value(FeedItem?)
    }

    private var resolvedItems: [String: CachedResult] = [:]
    private var inFlightTasks: [String: Task<FeedItem?, Never>] = [:]

    func cachedValue(for key: String) -> (found: Bool, item: FeedItem?) {
        if let cached = resolvedItems[key] {
            switch cached {
            case .value(let item):
                return (true, item)
            }
        }
        return (false, nil)
    }

    func inFlightTask(for key: String) -> Task<FeedItem?, Never>? {
        inFlightTasks[key]
    }

    func storeInFlightTask(_ task: Task<FeedItem?, Never>, for key: String) {
        inFlightTasks[key] = task
    }

    func storeResolvedValue(_ item: FeedItem?, for key: String) {
        resolvedItems[key] = .value(item)
        inFlightTasks[key] = nil
    }
}

private struct NostrEventReferenceFallbackView: View {
    let nostrURI: String

    private var identifier: String {
        let normalized = nostrURI
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.hasPrefix("nostr:") {
            return String(normalized.dropFirst("nostr:".count))
        }
        return normalized
    }

    var body: some View {
        Group {
            if let externalURL = NoteContentParser.njumpURL(for: identifier) {
                Link(destination: externalURL) {
                    fallbackLabel(showExternalIcon: true)
                }
                .buttonStyle(.plain)
            } else {
                fallbackLabel(showExternalIcon: false)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func fallbackLabel(showExternalIcon: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "quote.bubble")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Open referenced note")
                    .font(.subheadline.weight(.semibold))
                Text(shortIdentifier(identifier))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if showExternalIcon {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func shortIdentifier(_ value: String) -> String {
        guard value.count > 22 else { return value }
        return "\(value.prefix(12))...\(value.suffix(8))"
    }
}

private struct NostrEventReferenceCardView: View {
    private enum LoadState {
        case idle
        case loading
        case loaded(FeedItem)
        case failed
    }

    private enum ReferenceTarget {
        case eventID(String)
        case replaceable(kind: Int, pubkey: String, identifier: String)
    }

    private struct ParsedReference {
        let target: ReferenceTarget
        let relayHints: [URL]
    }

    private struct ReferenceMetadataDecoder: MetadataCoding {}

    let nostrURI: String
    let embedDepth: Int
    let onHashtagTap: ((String) -> Void)?
    let onOpenThread: ((FeedItem) -> Void)?
    @EnvironmentObject private var appSettings: AppSettingsStore

    @State private var state: LoadState = .idle

    private let relayClient = NostrRelayClient()
    private let feedService = NostrFeedService()

    private var normalizedIdentifier: String {
        let trimmed = nostrURI
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if trimmed.hasPrefix("nostr:") {
            return String(trimmed.dropFirst("nostr:".count))
        }
        return trimmed
    }

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                loadingCard
            case .loaded(let item):
                embeddedCard(for: item)
            case .failed:
                NostrEventReferenceFallbackView(nostrURI: nostrURI)
            }
        }
        .task(id: normalizedIdentifier) {
            await loadReferencedEvent()
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Loading referenced note")
                    .font(.subheadline.weight(.semibold))
                Text(shortIdentifier(normalizedIdentifier))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func embeddedCard(for item: FeedItem) -> some View {
        if let onOpenThread {
            Button {
                onOpenThread(item.threadNavigationItem)
            } label: {
                embeddedCardContent(for: item)
            }
            .buttonStyle(.plain)
        } else {
            embeddedCardContent(for: item)
        }
    }

    private func embeddedCardContent(for item: FeedItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                cardAvatar(for: item)

                VStack(alignment: .leading, spacing: 0) {
                    Text(item.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(item.handle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(RelativeTimestampFormatter.shortString(from: item.displayEvent.createdAtDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            NoteContentView(
                event: item.displayEvent,
                embedDepth: embedDepth,
                onHashtagTap: onHashtagTap,
                onReferencedEventTap: onOpenThread
            )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    private func cardAvatar(for item: FeedItem) -> some View {
        Group {
            if appSettings.textOnlyMode {
                fallbackAvatar(for: item)
            } else if let url = item.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackAvatar(for: item)
                    }
                }
            } else {
                fallbackAvatar(for: item)
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(Color(.separator), lineWidth: 0.5)
        }
    }

    private func fallbackAvatar(for item: FeedItem) -> some View {
        ZStack {
            Circle().fill(Color(.secondarySystemFill))
            Text(String(item.displayName.prefix(1)).uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func loadReferencedEvent() async {
        let key = normalizedIdentifier
        guard !key.isEmpty else {
            await MainActor.run { state = .failed }
            return
        }

        await MainActor.run { state = .loading }

        let cache = EmbeddedReferencedNoteCache.shared
        let cached = await cache.cachedValue(for: key)
        if cached.found {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if let item = cached.item {
                    state = .loaded(item)
                } else {
                    state = .failed
                }
            }
            return
        }

        let item: FeedItem?
        if let inFlight = await cache.inFlightTask(for: key) {
            item = await inFlight.value
        } else {
            let task = Task {
                await fetchReferencedFeedItem(identifier: key)
            }
            await cache.storeInFlightTask(task, for: key)
            item = await task.value
            await cache.storeResolvedValue(item, for: key)
        }

        guard !Task.isCancelled else { return }

        await MainActor.run {
            if let item {
                state = .loaded(item)
            } else {
                state = .failed
            }
        }
    }

    private func fetchReferencedFeedItem(identifier: String) async -> FeedItem? {
        guard let parsed = parseReference(from: identifier) else {
            return nil
        }

        let relayURLs = await effectiveRelayURLs(with: parsed.relayHints)
        guard !relayURLs.isEmpty else { return nil }

        let event: NostrEvent?
        switch parsed.target {
        case .eventID(let eventID):
            event = await fetchEventByID(eventID, relayURLs: relayURLs)
        case .replaceable(let kind, let pubkey, let replaceableIdentifier):
            event = await fetchReplaceableEvent(
                kind: kind,
                pubkey: pubkey,
                identifier: replaceableIdentifier,
                relayURLs: relayURLs
            )
        }

        guard let event else { return nil }
        let hydrated = await feedService.buildFeedItems(relayURLs: relayURLs, events: [event])
        return hydrated.first ?? FeedItem(event: event, profile: nil)
    }

    private func parseReference(from identifier: String) -> ParsedReference? {
        let normalized = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }

        if Self.isHex64(normalized) {
            return ParsedReference(target: .eventID(normalized), relayHints: [])
        }

        if let coordinate = parseReplaceableCoordinate(from: normalized) {
            return ParsedReference(
                target: .replaceable(
                    kind: coordinate.kind,
                    pubkey: coordinate.pubkey,
                    identifier: coordinate.identifier
                ),
                relayHints: []
            )
        }

        if normalized.hasPrefix("nevent1") || normalized.hasPrefix("naddr1") {
            let decoder = ReferenceMetadataDecoder()
            guard let metadata = try? decoder.decodedMetadata(from: normalized) else {
                return nil
            }

            let relayHints = (metadata.relays ?? [])
                .compactMap(URL.init(string:))

            if let eventID = metadata.eventId?.lowercased(),
               Self.isHex64(eventID) {
                return ParsedReference(target: .eventID(eventID), relayHints: relayHints)
            }

            if let kind = metadata.kind,
               let pubkey = metadata.pubkey?.lowercased(),
               Self.isHex64(pubkey),
               let replaceableIdentifier = metadata.identifier?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !replaceableIdentifier.isEmpty {
                return ParsedReference(
                    target: .replaceable(
                        kind: Int(kind),
                        pubkey: pubkey,
                        identifier: replaceableIdentifier
                    ),
                    relayHints: relayHints
                )
            }
        }

        return nil
    }

    private func parseReplaceableCoordinate(from value: String) -> (kind: Int, pubkey: String, identifier: String)? {
        let parts = value.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard let kind = Int(parts[0]), kind >= 0 else { return nil }

        let pubkey = String(parts[1]).lowercased()
        guard Self.isHex64(pubkey) else { return nil }

        let identifier = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { return nil }

        return (kind: kind, pubkey: pubkey, identifier: identifier)
    }

    private func effectiveRelayURLs(with hints: [URL]) async -> [URL] {
        let configuredReadRelays = await MainActor.run {
            RelaySettingsStore.shared.readRelayURLs
        }

        let defaults = RelaySettingsStore.defaultReadRelayURLs.compactMap(URL.init(string:))
        let base = configuredReadRelays.isEmpty ? defaults : configuredReadRelays
        return deduplicatedRelayURLs(hints + base)
    }

    private func deduplicatedRelayURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var deduped: [URL] = []
        for relayURL in urls {
            let key = relayURL.absoluteString.lowercased()
            guard seen.insert(key).inserted else { continue }
            deduped.append(relayURL)
        }
        return deduped
    }

    private func fetchEventByID(_ eventID: String, relayURLs: [URL]) async -> NostrEvent? {
        let filter = NostrFilter(ids: [eventID], limit: 1)
        let events = await fetchEvents(relayURLs: relayURLs, filter: filter)
        return deduplicateAndSort(events)
            .first(where: { $0.id.lowercased() == eventID.lowercased() })
    }

    private func fetchReplaceableEvent(
        kind: Int,
        pubkey: String,
        identifier: String,
        relayURLs: [URL]
    ) async -> NostrEvent? {
        let filter = NostrFilter(
            authors: [pubkey],
            kinds: [kind],
            limit: 40,
            tagFilters: ["d": [identifier]]
        )
        let events = await fetchEvents(relayURLs: relayURLs, filter: filter)
        return deduplicateAndSort(events).first(where: { event in
            guard event.kind == kind else { return false }
            guard event.pubkey.lowercased() == pubkey.lowercased() else { return false }
            return event.tags.contains { tag in
                guard let name = tag.first?.lowercased(), name == "d" else { return false }
                guard tag.count > 1 else { return false }
                return tag[1].trimmingCharacters(in: .whitespacesAndNewlines) == identifier
            }
        })
    }

    private func fetchEvents(
        relayURLs: [URL],
        filter: NostrFilter,
        timeout: TimeInterval = 8
    ) async -> [NostrEvent] {
        await withTaskGroup(of: [NostrEvent].self) { group in
            for relayURL in relayURLs {
                group.addTask {
                    (try? await relayClient.fetchEvents(
                        relayURL: relayURL,
                        filter: filter,
                        timeout: timeout
                    )) ?? []
                }
            }

            var merged: [NostrEvent] = []
            for await events in group {
                merged.append(contentsOf: events)
            }
            return merged
        }
    }

    private func deduplicateAndSort(_ events: [NostrEvent]) -> [NostrEvent] {
        var seen = Set<String>()
        var unique: [NostrEvent] = []
        for event in events {
            let key = event.id.lowercased()
            guard seen.insert(key).inserted else { continue }
            unique.append(event)
        }

        return unique.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id > rhs.id
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func shortIdentifier(_ value: String) -> String {
        guard value.count > 22 else { return value }
        return "\(value.prefix(12))...\(value.suffix(8))"
    }

    private static func isHex64(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }
}

private struct WebsiteLinkCardView: View {
    let url: URL
    @StateObject private var loader: LinkMetadataLoader

    init(url: URL) {
        self.url = url
        _loader = StateObject(wrappedValue: LinkMetadataLoader(url: url))
    }

    var body: some View {
        Link(destination: url) {
            HStack(alignment: .top, spacing: 10) {
                if let image = loader.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(loader.title ?? fallbackTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let summary = loader.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Text(loader.hostDisplay)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var fallbackTitle: String {
        if url.absoluteString.count > 100 {
            return String(url.absoluteString.prefix(97)) + "..."
        }
        return url.absoluteString
    }
}

@MainActor
private final class LinkMetadataLoader: ObservableObject {
    @Published var title: String?
    @Published var summary: String?
    @Published var image: UIImage?

    let hostDisplay: String
    private let url: URL

    private static let metadataCache = NSCache<NSURL, LPLinkMetadata>()
    private static let imageCache = NSCache<NSURL, UIImage>()

    init(url: URL) {
        self.url = url
        hostDisplay = url.host ?? url.absoluteString
        load()
    }

    private func load() {
        let cacheKey = url as NSURL
        if let cachedMetadata = Self.metadataCache.object(forKey: cacheKey) {
            apply(metadata: cachedMetadata)
            if let cachedImage = Self.imageCache.object(forKey: cacheKey) {
                image = cachedImage
            }
            return
        }

        let provider = LPMetadataProvider()
        provider.startFetchingMetadata(for: url) { metadata, _ in
            guard let metadata else { return }
            Task { @MainActor in
                Self.metadataCache.setObject(metadata, forKey: cacheKey)
                self.apply(metadata: metadata)
                self.loadImageIfNeeded(metadata: metadata, cacheKey: cacheKey)
            }
        }
    }

    private func apply(metadata: LPLinkMetadata) {
        if let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            self.title = title
        }
        if let summary = metadata.url?.absoluteString,
           summary != url.absoluteString,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.summary = summary
        }
    }

    private func loadImageIfNeeded(metadata: LPLinkMetadata, cacheKey: NSURL) {
        if let cachedImage = Self.imageCache.object(forKey: cacheKey) {
            image = cachedImage
            return
        }
        guard let provider = metadata.imageProvider else { return }
        guard provider.canLoadObject(ofClass: UIImage.self) else { return }

        provider.loadObject(ofClass: UIImage.self) { object, _ in
            guard let uiImage = object as? UIImage else { return }
            Task { @MainActor in
                Self.imageCache.setObject(uiImage, forKey: cacheKey)
                self.image = uiImage
            }
        }
    }
}

private actor CustomEmojiImageLoader {
    static let shared = CustomEmojiImageLoader()

    private var cache: [URL: UIImage] = [:]

    func image(for url: URL) async -> UIImage? {
        if let cached = cache[url] {
            return cached
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...399).contains(httpResponse.statusCode) {
                return nil
            }
            guard let image = UIImage(data: data) else {
                return nil
            }
            cache[url] = image
            return image
        } catch {
            return nil
        }
    }
}

private actor NoteMediaImageLoader {
    static let shared = NoteMediaImageLoader()

    private var cache: [URL: UIImage] = [:]

    func image(for url: URL) async -> UIImage? {
        if let cached = cache[url] {
            return cached
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...399).contains(httpResponse.statusCode) {
                return nil
            }
            guard let image = UIImage(data: data) else {
                return nil
            }
            cache[url] = image
            return image
        } catch {
            return nil
        }
    }
}
