import AVFoundation
import AVKit
import Combine
import ImageIO
import LinkPresentation
import NostrSDK
import SwiftUI
import UIKit

enum FlowLayoutGuardrails {
    private static let softBreakSeparators = CharacterSet(charactersIn: "/._-?&=#:%+")

    static func softWrapped(_ value: String, maxNonBreakingRunLength: Int = 24) -> String {
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
            if nonBreakingRunLength >= maxNonBreakingRunLength {
                wrapped.append(softBreak)
                nonBreakingRunLength = 0
            }
        }

        return wrapped
    }

    static func clampedAspectRatio(
        _ value: CGFloat?,
        min minRatio: CGFloat = 0.28,
        max maxRatio: CGFloat = 3.2
    ) -> CGFloat? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return Swift.min(Swift.max(value, minRatio), maxRatio)
    }
}

enum NoteContentMediaLayout {
    case feed
    case detailCarousel
}

enum NoteContentPollPlacement {
    static func insertionOffsets(
        partCount: Int,
        insertionIndex: Int,
        includesPoll: Bool
    ) -> Set<Int> {
        guard includesPoll else { return [] }

        let normalizedPartCount = max(partCount, 0)
        let normalizedInsertionIndex = min(max(insertionIndex, 0), normalizedPartCount)
        return [normalizedInsertionIndex]
    }
}

enum NoteContentLinkResolver {
    static func linkURL(
        for token: NoteContentToken,
        allowsInAppProfileRouting: Bool
    ) -> URL? {
        switch token.type {
        case .url:
            return URL(string: token.value)
        case .nostrMention:
            let normalized = NoteContentView.normalizeMentionIdentifier(token.value)
            if allowsInAppProfileRouting,
               let pubkey = NoteContentView.mentionedPubkey(from: normalized),
               let actionURL = NoteContentParser.profileActionURL(for: pubkey) {
                return actionURL
            }
            return NoteContentParser.njumpURL(for: normalized)
        case .hashtag:
            return NoteContentParser.hashtagActionURL(for: token.value)
        case .text, .websocketURL, .emoji, .nostrEvent, .image, .video, .audio:
            return nil
        }
    }
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
    private let articleMetadata: NostrLongFormArticleMetadata?
    private let pollEvent: NostrEvent
    private let pollMetadata: NostrPollMetadata?
    private let onHashtagTap: ((String) -> Void)?
    private let onProfileTap: ((String) -> Void)?
    private let onReferencedEventTap: ((FeedItem) -> Void)?
    private let mediaLayout: NoteContentMediaLayout
    private let reactionCount: Int
    private let commentCount: Int
    private let embedDepth: Int
    private let mentionIdentifiers: [String]
    private let emojiTagURLs: [String: URL]
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @ObservedObject private var followStore = FollowStore.shared

    @State private var mentionLabels: [String: String] = [:]
    @State private var emojiImages: [String: UIImage] = [:]
    @State private var isExpanded = false
    @State private var revealsMediaInTextOnlyMode = false
    @State private var revealsBlurredMedia = false

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
        onProfileTap: ((String) -> Void)? = nil,
        onReferencedEventTap: ((FeedItem) -> Void)? = nil
    ) {
        sourceEvent = event
        let renderEvent = Self.renderEvent(for: event)
        articleMetadata = renderEvent.longFormArticleMetadata
        pollEvent = renderEvent
        pollMetadata = renderEvent.pollMetadata
        let parsedContent = Self.parsedContentCache.parsedContent(for: event) {
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
        self.onProfileTap = onProfileTap
        self.onReferencedEventTap = onReferencedEventTap
        self.mediaLayout = mediaLayout
        self.reactionCount = reactionCount
        self.commentCount = commentCount
        self.embedDepth = embedDepth
    }

    var body: some View {
        Group {
            if let articleMetadata {
                LongFormArticlePreviewView(
                    article: articleMetadata,
                    onHashtagTap: onHashtagTap
                )
            } else {
                let pollInsertionOffsets = NoteContentPollPlacement.insertionOffsets(
                    partCount: renderedParts.count,
                    insertionIndex: pollInsertionIndex,
                    includesPoll: pollMetadata != nil
                )

                VStack(alignment: .leading, spacing: 10) {
                    if let pollMetadata, pollInsertionOffsets.contains(0) {
                        pollCard(for: pollMetadata)
                    }

                    ForEach(Array(renderedParts.enumerated()), id: \.offset) { index, part in
                        switch part {
                        case .inlineTokens(let inlineTokens):
                            if mediaLayout == .detailCarousel {
                                inlineText(from: inlineTokens)
                                    .font(appSettings.appFont(.body))
                                    .lineLimit(isCollapsedPreviewActive ? Self.collapsedPreviewLineLimit : nil)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .layoutPriority(1)
                                    .textSelection(.enabled)
                            } else {
                                inlineText(from: inlineTokens)
                                    .font(appSettings.appFont(.body))
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
                                restrictedMediaView {
                                    NoteImageGalleryView(
                                        imageURLs: imageURLs,
                                        layout: mediaLayout,
                                        sourceEvent: sourceEvent,
                                        reactionCount: reactionCount,
                                        commentCount: commentCount
                                    )
                                }
                            }
                        case .video(let url):
                            if appSettings.textOnlyMode {
                                NoteMediaPlaceholderView(
                                    systemImage: "video.slash",
                                    text: "Video hidden in Text Only Mode"
                                )
                            } else {
                                restrictedMediaView {
                                    NoteVideoPlayerView(
                                        url: url,
                                        layout: mediaLayout
                                    )
                                }
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
                                    onProfileTap: onProfileTap,
                                    onOpenThread: onReferencedEventTap
                                )
                            } else {
                                NostrEventReferenceFallbackView(nostrURI: nostrURI)
                            }
                        }

                        if let pollMetadata, pollInsertionOffsets.contains(index + 1) {
                            pollCard(for: pollMetadata)
                        }
                    }

                    if !isCollapsedPreviewActive, let websitePreviewURL, !appSettings.textOnlyMode {
                        WebsiteLinkCardView(
                            url: websitePreviewURL,
                            backgroundColor: appSettings.themePalette.linkPreviewBackground,
                            borderColor: appSettings.themePalette.linkPreviewBorder
                        )
                    }

                    if isCollapsedPreviewActive {
                        collapseMoreOverlay
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            if let pubkey = NoteContentParser.profilePubkey(fromActionURL: url),
               let onProfileTap {
                onProfileTap(pubkey)
                return .handled
            }
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

    @ViewBuilder
    private func restrictedMediaView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if shouldBlurMediaFromUnfollowedAuthors {
            NoteBlurRevealContainer(
                cornerRadius: restrictedMediaCornerRadius,
                onReveal: {
                    revealsBlurredMedia = true
                }
            ) {
                content()
            }
        } else {
            content()
        }
    }

    private var collapseMoreOverlay: some View {
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
                .background(Capsule().fill(Color(.tertiarySystemFill)))
                .overlay(Capsule().stroke(Color(.separator).opacity(0.3), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show full note")
        .padding(.top, 10)
    }

    private var isCollapsedPreviewActive: Bool {
        shouldCollapseLongNote && !isExpanded
    }

    private var shouldCollapseLongNote: Bool {
        inlineCharacterCount > Self.collapsedPreviewCharacterLimit
    }

    private var restrictedMediaCornerRadius: CGFloat {
        mediaLayout == .feed ? 18 : 12
    }

    private var pollInsertionIndex: Int {
        Self.pollInsertionIndex(in: renderedParts)
    }

    private var shouldBlurMediaFromUnfollowedAuthors: Bool {
        guard appSettings.blurMediaFromUnfollowedAuthors else { return false }
        guard !revealsBlurredMedia else { return false }
        guard let currentPubkey = auth.currentAccount?.pubkey else { return false }

        let authorPubkey = normalizedMediaAuthorPubkey(sourceEvent.pubkey)
        let normalizedCurrentPubkey = normalizedMediaAuthorPubkey(currentPubkey)
        guard !authorPubkey.isEmpty, authorPubkey != normalizedCurrentPubkey else { return false }

        return !followStore.isFollowing(authorPubkey)
    }

    private func normalizedMediaAuthorPubkey(_ pubkey: String?) -> String {
        pubkey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
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

    private func pollCard(for metadata: NostrPollMetadata) -> some View {
        PollNoteView(event: pollEvent, poll: metadata)
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

    private static func pollInsertionIndex(in parts: [RenderPart]) -> Int {
        var index = 0

        while index < parts.count {
            guard case .inlineTokens = parts[index] else { break }
            index += 1
        }

        return index
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
            if let url = NoteContentLinkResolver.linkURL(
                for: token,
                allowsInAppProfileRouting: onProfileTap != nil
            ) {
                segment.link = url
                segment.foregroundColor = .accentColor
            }
        case .nostrMention:
            if let url = NoteContentLinkResolver.linkURL(
                for: token,
                allowsInAppProfileRouting: onProfileTap != nil
            ) {
                segment.link = url
                segment.foregroundColor = .accentColor
            }
        case .hashtag:
            if let url = NoteContentLinkResolver.linkURL(
                for: token,
                allowsInAppProfileRouting: onProfileTap != nil
            ) {
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

    private static func softWrapValue(_ value: String) -> String {
        FlowLayoutGuardrails.softWrapped(value)
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

        let lineHeight = appSettings.appUIFont(.body).lineHeight
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

    fileprivate static func normalizeMentionIdentifier(_ raw: String) -> String {
        let lowered = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if lowered.hasPrefix("nostr:") {
            return String(lowered.dropFirst("nostr:".count))
        }
        return lowered
    }

    fileprivate static func mentionedPubkey(from identifier: String) -> String? {
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

private struct NoteBlurRevealContainer<Content: View>: View {
    let cornerRadius: CGFloat
    let onReveal: () -> Void
    let content: Content

    init(
        cornerRadius: CGFloat,
        onReveal: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.onReveal = onReveal
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .compositingGroup()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .blur(radius: 22)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.22))
                }
                .allowsHitTesting(false)

            VStack(spacing: 8) {
                Image(systemName: "eye.slash.fill")
                    .font(.headline.weight(.semibold))
                Text("Tap to reveal")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.28),
                                    Color.white.opacity(0.08),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.18),
                                    Color.clear
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                }
            )
            .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture(perform: onReveal)
        .accessibilityLabel("Reveal media")
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
            if imageURLs.count == 1 {
                singleImageCell(url: imageURLs[0], index: 0)
            } else if layout == .feed {
                feedGallery
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
                        cornerRadius: mediaCornerRadius,
                        maxHeight: multiImageHeight,
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

    var body: some View {
        Button(action: onTap) {
            NoteRemoteMediaView(url: url) { asset in
                NoteMediaAssetContentView(asset: asset, scaling: .fill)
                    .frame(width: width, height: height)
            } placeholder: {
                ZStack {
                    Color(.secondarySystemBackground)
                        .frame(width: width, height: height)
                    ProgressView()
                }
            } failure: {
                ZStack {
                    Color(.secondarySystemBackground)
                        .frame(width: width, height: height)
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: width, height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(width: width, height: height)
    }
}

private struct NoteSingleImageCellView: View {
    let url: URL
    let cornerRadius: CGFloat
    var maxHeight: CGFloat? = nil
    let onTap: () -> Void
    @EnvironmentObject private var appSettings: AppSettingsStore

    private var placeholderHeight: CGFloat {
        maxHeight ?? 180
    }

    private var mediaBackgroundColor: Color {
        if appSettings.activeTheme == .dracula {
            return appSettings.themePalette.background
        }
        return Color(.secondarySystemBackground)
    }

    var body: some View {
        Button(action: onTap) {
            NoteRemoteMediaView(url: url) { asset in
                mediaContent(asset: asset)
            } placeholder: {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: placeholderHeight, alignment: .center)
                    .background(mediaBackgroundColor)
            } failure: {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: placeholderHeight, alignment: .center)
                    .background(mediaBackgroundColor)
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func mediaContent(asset: NoteMediaAsset) -> some View {
        let base = NoteMediaAssetContentView(asset: asset, scaling: .fit)

        if let maxHeight {
            base
                .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .center)
                .background(mediaBackgroundColor)
                .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .center)
        } else {
            base
                .background(mediaBackgroundColor)
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
    @EnvironmentObject private var composeSheetCoordinator: AppComposeSheetCoordinator
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @EnvironmentObject private var toastCenter: AppToastCenter
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reactionStats = NoteReactionStatsService.shared
    @State private var selectedIndex: Int
    @State private var isShowingInlineResharePanel = false
    @State private var isPublishingRepost = false
    @State private var repostStatusMessage: String?
    @State private var repostStatusIsError = false
    @State private var remixSourceImage: UIImage?
    @State private var pendingRemixComposeDraft: NoteImageRemixComposeDraft?
    @State private var isShowingRemixEditor = false
    @State private var isPreparingRemixEditor = false
    @State private var zoomedImageIndices = Set<Int>()
    @State private var swipeDismissOffset: CGSize = .zero
    @State private var isCompletingSwipeDismiss = false
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
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                viewerBackgroundColor
                    .opacity(viewerBackgroundOpacity(for: geometry.size))
                    .ignoresSafeArea()

                NavigationStack {
                    TabView(selection: $selectedIndex) {
                        ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                            ZStack {
                                viewerBackgroundColor.ignoresSafeArea()
                                NoteZoomableFullscreenImageView(
                                    url: url,
                                    chromeForegroundColor: chromeForegroundColor,
                                    onZoomStateChange: { isZoomed in
                                        updateZoomState(isZoomed, for: index)
                                    }
                                )
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
                .offset(swipeDismissOffset)
                .scaleEffect(viewerScale(for: geometry.size))
                .rotationEffect(.degrees(viewerRotationDegrees(for: geometry.size)))
                .simultaneousGesture(swipeToDismissGesture(containerSize: geometry.size))
                .allowsHitTesting(!isShowingInlineResharePanel)

                if isShowingInlineResharePanel {
                    fullscreenReshareOverlay
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .fullScreenCover(
            isPresented: $isShowingRemixEditor,
            onDismiss: handleRemixEditorDismissed
        ) {
            if let remixSourceImage {
                ImageRemixEditorView(
                    sourceImage: remixSourceImage,
                    sourceEvent: sourceEvent,
                    currentAccountPubkey: auth.currentAccount?.pubkey,
                    currentNsec: auth.currentNsec,
                    writeRelayURLs: effectiveWriteRelayURLs,
                    onComposeRequested: { attachment, replyTargetEvent in
                        pendingRemixComposeDraft = NoteImageRemixComposeDraft(
                            attachment: attachment,
                            replyTargetEvent: replyTargetEvent
                        )
                        isShowingRemixEditor = false
                    }
                )
            }
        }
        .task {
            reactionStats.prefetch(events: [sourceEvent], relayURLs: effectiveReadRelayURLs)
        }
    }

    private var mediaActionBar: some View {
        HStack(spacing: 16) {
            Button {
                presentReplyComposer()
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
            .accessibilityLabel("Reply")

            Button {
                repostStatusMessage = nil
                repostStatusIsError = false
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                    isShowingInlineResharePanel = true
                }
            } label: {
                Image(systemName: "arrow.2.squarepath")
                    .foregroundStyle(chromeForegroundColor)
                    .frame(minWidth: 36, minHeight: 28, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Re-share")

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

            ShareLink(item: urls[selectedIndex]) {
                Image(systemName: "paperplane")
                    .foregroundStyle(chromeForegroundColor)
                    .frame(minWidth: 36, minHeight: 28, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share")

            Button {
                Task {
                    await openRemixEditor()
                }
            } label: {
                Group {
                    if isPreparingRemixEditor {
                        ProgressView()
                            .controlSize(.small)
                            .tint(appSettings.primaryColor)
                            .frame(minWidth: 36, minHeight: 28, alignment: .leading)
                    } else {
                        Image(systemName: "paintbrush.pointed.fill")
                            .foregroundStyle(appSettings.primaryColor)
                            .frame(minWidth: 36, minHeight: 28, alignment: .leading)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isPreparingRemixEditor)
            .accessibilityLabel("Edit image")
        }
        .font(.headline)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .center)
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
        if appSettings.activeTheme == .dracula {
            return appSettings.themePalette.background
        }
        return colorScheme == .dark ? .black : Color(.systemBackground)
    }

    private var viewerNavigationBarColor: Color {
        if appSettings.activeTheme == .dracula {
            return appSettings.themePalette.background
        }
        return colorScheme == .dark ? .black : Color(.systemBackground)
    }

    private var chromeForegroundColor: Color {
        colorScheme == .dark ? .white : .primary
    }

    private var doneButtonForegroundColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var fullscreenReshareOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(colorScheme == .dark ? 0.42 : 0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        isShowingInlineResharePanel = false
                    }
                }

            VStack(alignment: .leading, spacing: 16) {
                Capsule()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.28 : 0.5))
                    .frame(width: 42, height: 5)
                    .frame(maxWidth: .infinity)

                HStack {
                    Text("Re-share")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            isShowingInlineResharePanel = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color(.tertiarySystemFill), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close re-share options")
                }

                VStack(spacing: 0) {
                    inlineReshareActionRow(
                        title: "Repost",
                        systemImage: "arrow.2.squarepath"
                    ) {
                        Task {
                            await publishRepost()
                        }
                    }

                    Divider()
                        .padding(.leading, 18)

                    inlineReshareActionRow(
                        title: "Quote",
                        systemImage: "quote.bubble"
                    ) {
                        presentQuoteComposer()
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemBackground).opacity(colorScheme == .dark ? 0.9 : 0.94))
                )

                if let repostStatusMessage, !repostStatusMessage.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: repostStatusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(repostStatusIsError ? .red : .green)
                        Text(repostStatusMessage)
                            .font(.footnote)
                            .foregroundStyle(repostStatusIsError ? .red : .secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill((repostStatusIsError ? Color.red : Color.green).opacity(0.1))
                    )
                } else {
                    Text("Share this note as a repost, or add your own context with a quote.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 16)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.35), lineWidth: 0.7)
                    )
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
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

    @ViewBuilder
    private func inlineReshareActionRow(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if isPublishingRepost && title == "Repost" {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPublishingRepost)
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
            repostStatusMessage = "Reposted to \(relayCount) source\(relayCount == 1 ? "" : "s")."
            repostStatusIsError = false

            try? await Task.sleep(nanoseconds: 450_000_000)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                isShowingInlineResharePanel = false
            }
        } catch {
            repostStatusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            repostStatusIsError = true
        }
    }

    @MainActor
    private func openRemixEditor() async {
        guard !isPreparingRemixEditor else { return }
        isPreparingRemixEditor = true
        defer {
            isPreparingRemixEditor = false
        }

        let currentURL = urls[selectedIndex]
        guard let image = await FlowImageCache.shared.image(for: currentURL) else {
            toastCenter.show("Couldn't load that image for editing.", style: .error, duration: 2.8)
            return
        }

        composeSheetCoordinator.dismiss()
        pendingRemixComposeDraft = nil
        remixSourceImage = image
        isShowingRemixEditor = true
    }

    @MainActor
    private func handleRemixEditorDismissed() {
        remixSourceImage = nil

        guard let draft = pendingRemixComposeDraft else { return }
        pendingRemixComposeDraft = nil

        Task { @MainActor in
            // Dismiss the fullscreen image viewer before asking the app shell to present compose.
            dismiss()
            try? await Task.sleep(nanoseconds: 320_000_000)
            composeSheetCoordinator.presentRemix(
                attachment: draft.attachment,
                replyTargetEvent: draft.replyTargetEvent
            )
        }
    }

    @MainActor
    private func presentReplyComposer() {
        Task { @MainActor in
            dismiss()
            try? await Task.sleep(nanoseconds: 320_000_000)
            composeSheetCoordinator.presentReply(to: sourceEvent)
        }
    }

    @MainActor
    private func presentQuoteComposer() {
        let draft = reshareService.buildQuoteDraft(
            for: sourceEvent,
            relayHintURL: effectiveReadRelayURLs.first
        )

        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            isShowingInlineResharePanel = false
        }

        Task { @MainActor in
            dismiss()
            try? await Task.sleep(nanoseconds: 320_000_000)
            composeSheetCoordinator.presentQuote(draft)
        }
    }

    private func swipeToDismissGesture(containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard !isShowingInlineResharePanel, !isShowingRemixEditor, !isPreparingRemixEditor else { return }
                guard !isCurrentImageZoomed else { return }
                guard shouldTrackSwipeDismiss(for: value.translation) else { return }
                swipeDismissOffset = value.translation
            }
            .onEnded { value in
                guard !isShowingInlineResharePanel, !isShowingRemixEditor else { return }
                guard !isCurrentImageZoomed else {
                    swipeDismissOffset = .zero
                    return
                }
                guard shouldTrackSwipeDismiss(for: value.translation) else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        swipeDismissOffset = .zero
                    }
                    return
                }

                let finalTranslation = projectedSwipeDismissOffset(for: value)
                if shouldCompleteSwipeDismiss(with: finalTranslation, in: containerSize) {
                    completeSwipeDismiss(using: finalTranslation, in: containerSize)
                } else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        swipeDismissOffset = .zero
                    }
                }
            }
    }

    private func shouldTrackSwipeDismiss(for translation: CGSize) -> Bool {
        guard !isCompletingSwipeDismiss else { return false }
        if urls.count <= 1 {
            return true
        }

        let horizontal = abs(translation.width)
        let vertical = abs(translation.height)
        if vertical >= max(horizontal * 0.7, 20) {
            return true
        }

        let isSwipingOutFromLeadingEdge = translation.width > 0 && selectedIndex == 0
        let isSwipingOutFromTrailingEdge = translation.width < 0 && selectedIndex == urls.count - 1
        return horizontal >= max(vertical * 1.25, 44) &&
            (isSwipingOutFromLeadingEdge || isSwipingOutFromTrailingEdge)
    }

    private func projectedSwipeDismissOffset(for value: DragGesture.Value) -> CGSize {
        CGSize(
            width: value.predictedEndTranslation.width,
            height: value.predictedEndTranslation.height
        )
    }

    private func shouldCompleteSwipeDismiss(with translation: CGSize, in size: CGSize) -> Bool {
        let distance = hypot(translation.width, translation.height)
        let threshold = max(150, min(size.width, size.height) * 0.18)
        return distance >= threshold
    }

    private func completeSwipeDismiss(using translation: CGSize, in size: CGSize) {
        guard !isCompletingSwipeDismiss else { return }
        isCompletingSwipeDismiss = true

        let targetOffset = swipeDismissCompletionOffset(for: translation, in: size)
        withAnimation(.easeOut(duration: 0.2)) {
            swipeDismissOffset = targetOffset
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 170_000_000)
            dismiss()
        }
    }

    private func swipeDismissCompletionOffset(for translation: CGSize, in size: CGSize) -> CGSize {
        let distance = max(hypot(translation.width, translation.height), 1)
        let direction = CGVector(dx: translation.width / distance, dy: translation.height / distance)
        let exitDistance = max(size.width, size.height) * 1.18
        return CGSize(
            width: direction.dx * exitDistance,
            height: direction.dy * exitDistance
        )
    }

    private func viewerBackgroundOpacity(for size: CGSize) -> Double {
        let distance = hypot(swipeDismissOffset.width, swipeDismissOffset.height)
        let maxDistance = max(min(size.width, size.height) * 0.75, 1)
        return max(0.35, 1 - (distance / maxDistance) * 0.75)
    }

    private func viewerScale(for size: CGSize) -> CGFloat {
        let distance = hypot(swipeDismissOffset.width, swipeDismissOffset.height)
        let maxDistance = max(max(size.width, size.height), 1)
        return max(0.9, 1 - (distance / maxDistance) * 0.09)
    }

    private func viewerRotationDegrees(for size: CGSize) -> Double {
        guard size.width > 0 else { return 0 }
        return Double(swipeDismissOffset.width / size.width) * 8
    }

    private var isCurrentImageZoomed: Bool {
        zoomedImageIndices.contains(selectedIndex)
    }

    private func updateZoomState(_ isZoomed: Bool, for index: Int) {
        if isZoomed {
            zoomedImageIndices.insert(index)
        } else {
            zoomedImageIndices.remove(index)
        }
    }
}

private struct NoteImageRemixComposeDraft: Identifiable {
    let id = UUID()
    let attachment: ComposeMediaAttachment
    let replyTargetEvent: NostrEvent?
}

private actor NoteVideoAspectRatioCache {
    static let shared = NoteVideoAspectRatioCache()

    private var cachedRatios: [URL: CGFloat] = [:]
    private var inFlight: [URL: Task<CGFloat?, Never>] = [:]

    func ratio(for url: URL) async -> CGFloat? {
        if let cached = cachedRatios[url] {
            return cached
        }

        if let existingTask = inFlight[url] {
            return await existingTask.value
        }

        let task = Task(priority: .utility) {
            await Self.loadRatio(for: url)
        }
        inFlight[url] = task

        let ratio = await task.value
        inFlight[url] = nil

        if let ratio {
            cachedRatios[url] = ratio
        }

        return ratio
    }

    private static func loadRatio(for url: URL) async -> CGFloat? {
        let asset = AVURLAsset(url: url)

        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return nil }

            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            let transformedSize = naturalSize.applying(preferredTransform)

            let width = abs(transformedSize.width)
            let height = abs(transformedSize.height)
            guard width > 0, height > 0 else { return nil }

            return max(0.4, min(width / height, 3.0))
        } catch {
            return nil
        }
    }
}

private final class NoteVideoThumbnailCache {
    static let shared = NoteVideoThumbnailCache()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 96
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

private struct NoteVideoPlayerView: View {
    let url: URL
    let layout: NoteContentMediaLayout
    @Environment(\.colorScheme) private var colorScheme
    @State private var videoAspectRatio: CGFloat = 16.0 / 9.0
    @State private var videoThumbnail: UIImage?
    @State private var isShowingPlayerInline = false

    init(
        url: URL,
        layout: NoteContentMediaLayout
    ) {
        self.url = url
        self.layout = layout
    }

    var body: some View {
        ZStack {
            if isShowingPlayerInline {
                NoteNativeVideoPlayerController(url: url)
                    .clipShape(
                        RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous)
                    )
            } else {
                Button {
                    isShowingPlayerInline = true
                } label: {
                    ZStack {
                        thumbnailLayer
                        playOverlayButton
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: maxVideoHeight, alignment: .leading)
        .aspectRatio(videoAspectRatio, contentMode: .fit)
        .clipShape(
            RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous)
        )
        .contentShape(
            RoundedRectangle(cornerRadius: mediaCornerRadius, style: .continuous)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: url, priority: .utility) {
            await loadVideoAspectRatio()
            await loadVideoThumbnailIfNeeded()
        }
    }

    @ViewBuilder
    private var thumbnailLayer: some View {
        if let videoThumbnail {
            Image(uiImage: videoThumbnail)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(.secondarySystemFill),
                        Color(.tertiarySystemFill)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var playOverlayButton: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .frame(width: 54, height: 54)
            .overlay {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .offset(x: 1)
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.24), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 6)
    }

    private var maxVideoHeight: CGFloat {
        min(UIScreen.main.bounds.height * 0.72, 620)
    }

    private var mediaCornerRadius: CGFloat {
        layout == .feed ? 18 : 12
    }

    private func loadVideoAspectRatio() async {
        if layout == .feed {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
        }

        guard let ratio = await NoteVideoAspectRatioCache.shared.ratio(for: url) else { return }
        guard !Task.isCancelled else { return }

        await MainActor.run {
            guard abs(videoAspectRatio - ratio) > 0.02 else { return }
            videoAspectRatio = ratio
        }
    }

    private func loadVideoThumbnailIfNeeded() async {
        if let cached = NoteVideoThumbnailCache.shared.image(for: url) {
            await MainActor.run {
                videoThumbnail = cached
            }
            return
        }

        let thumbnailPixelSize = await MainActor.run {
            CGSize(
                width: max(UIScreen.main.bounds.width - 28, 1) * UIScreen.main.scale,
                height: max(maxVideoHeight, 1) * UIScreen.main.scale
            )
        }

        let generatedThumbnail: UIImage? = await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = thumbnailPixelSize

            let time = CMTime(seconds: 0.15, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }.value

        guard let generatedThumbnail else { return }
        guard !Task.isCancelled else { return }

        NoteVideoThumbnailCache.shared.insert(generatedThumbnail, for: url)

        await MainActor.run {
            videoThumbnail = generatedThumbnail
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

private struct NoteNativeVideoPlayerController: UIViewControllerRepresentable {
    let url: URL

    final class Coordinator {
        let player = AVPlayer()
        private var currentURL: URL?

        func configure(url: URL, controller: AVPlayerViewController) {
            guard currentURL != url || controller.player !== player else { return }
            currentURL = url
            Self.activatePlaybackAudioSessionIfNeeded()
            controller.player = player
            player.isMuted = false
            player.volume = 1
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.play()
        }

        func stop() {
            player.pause()
            player.replaceCurrentItem(with: nil)
            currentURL = nil
        }

        private static func activatePlaybackAudioSessionIfNeeded() {
            let audioSession = AVAudioSession.sharedInstance()
            try? audioSession.setCategory(.playback, mode: .moviePlayback, options: [])
            try? audioSession.setActive(true, options: [])
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        context.coordinator.configure(url: url, controller: controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        context.coordinator.configure(url: url, controller: uiViewController)
    }

    static func dismantleUIViewController(
        _ uiViewController: AVPlayerViewController,
        coordinator: Coordinator
    ) {
        uiViewController.player = nil
        coordinator.stop()
    }
}

private actor EmbeddedReferencedNoteCache {
    static let shared = EmbeddedReferencedNoteCache()

    private enum CachedResult {
        case value(FeedItem?)
    }

    private let maxResolvedEntries = 512
    private var resolvedItems: [String: CachedResult] = [:]
    private var resolvedOrder: [String] = []
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
        if resolvedItems[key] == nil {
            resolvedOrder.append(key)
        } else {
            resolvedOrder.removeAll { $0 == key }
            resolvedOrder.append(key)
        }
        resolvedItems[key] = .value(item)
        inFlightTasks[key] = nil

        let overflow = resolvedOrder.count - maxResolvedEntries
        guard overflow > 0 else { return }

        for _ in 0..<overflow {
            let removedKey = resolvedOrder.removeFirst()
            resolvedItems.removeValue(forKey: removedKey)
        }
    }
}

private struct NostrEventReferenceFallbackView: View {
    let nostrURI: String
    @EnvironmentObject private var appSettings: AppSettingsStore

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
                .fill(appSettings.themePalette.quoteBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(appSettings.themePalette.separator, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func fallbackLabel(showExternalIcon: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "quote.bubble")
                .foregroundStyle(appSettings.themePalette.mutedForeground)
            VStack(alignment: .leading, spacing: 2) {
                Text("Open referenced note")
                    .font(.subheadline.weight(.semibold))
                Text(shortIdentifier(identifier))
                    .font(.caption)
                    .foregroundStyle(appSettings.themePalette.mutedForeground)
                    .lineLimit(1)
            }
            Spacer()
            if showExternalIcon {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(appSettings.themePalette.mutedForeground)
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
    let onProfileTap: ((String) -> Void)?
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
                    .foregroundStyle(appSettings.themePalette.mutedForeground)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(appSettings.themePalette.quoteBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(appSettings.themePalette.separator, lineWidth: 0.5)
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
                        .foregroundStyle(appSettings.themePalette.mutedForeground)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let clientName = item.displayEvent.clientName {
                    Text("via \(clientName)")
                        .font(.caption2)
                        .foregroundStyle(appSettings.themePalette.mutedForeground)
                        .lineLimit(1)
                }

                Text(RelativeTimestampFormatter.shortString(from: item.displayEvent.createdAtDate))
                    .font(.caption2)
                    .foregroundStyle(appSettings.themePalette.mutedForeground)
                    .lineLimit(1)
            }

            NoteContentView(
                event: item.displayEvent,
                embedDepth: embedDepth,
                onHashtagTap: onHashtagTap,
                onProfileTap: onProfileTap,
                onReferencedEventTap: onOpenThread
            )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(appSettings.themePalette.quoteBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(appSettings.themePalette.separator, lineWidth: 0.5)
        )
    }

    private func cardAvatar(for item: FeedItem) -> some View {
        Group {
            if appSettings.textOnlyMode {
                fallbackAvatar(for: item)
            } else if let url = item.avatarURL {
                CachedAsyncImage(url: url) { phase in
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
            Circle().stroke(appSettings.themePalette.separator, lineWidth: 0.5)
        }
    }

    private func fallbackAvatar(for item: FeedItem) -> some View {
        ZStack {
            Circle().fill(appSettings.themePalette.secondaryFill)
            Text(String(item.displayName.prefix(1)).uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(appSettings.themePalette.mutedForeground)
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

            let rawRelayHints: [String] = metadata.relays ?? []
            let relayHints = rawRelayHints.compactMap { relay -> URL? in
                let trimmed = relay.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                guard Self.isSupportedRelayHint(trimmed) else { return nil }
                return URL(string: trimmed)
            }

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
            guard Self.isSupportedRelayHint(relayURL.absoluteString) else { continue }
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

    private static func isSupportedRelayHint(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("ws://") || normalized.hasPrefix("wss://")
    }
}

private struct WebsiteLinkCardView: View {
    let url: URL
    let backgroundColor: Color
    let borderColor: Color
    @StateObject private var loader: LinkMetadataLoader

    init(url: URL, backgroundColor: Color, borderColor: Color) {
        self.url = url
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
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
                    Text(FlowLayoutGuardrails.softWrapped(loader.title ?? fallbackTitle))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let summary = loader.summary, !summary.isEmpty {
                        Text(FlowLayoutGuardrails.softWrapped(summary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Text(FlowLayoutGuardrails.softWrapped(loader.hostDisplay, maxNonBreakingRunLength: 18))
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
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .task(id: url) {
            await loader.startIfNeeded()
        }
        .onDisappear {
            loader.cancelPendingLoad()
        }
    }

    private var fallbackTitle: String {
        if url.absoluteString.count > 100 {
            return String(url.absoluteString.prefix(97)) + "..."
        }
        return url.absoluteString
    }
}

private actor LinkPreviewLoadCoordinator {
    enum BeginDecision: Sendable, Equatable {
        case started
        case atCapacity
        case blockedByBackoff
    }

    enum Completion: Sendable, Equatable {
        case success
        case failure
        case cancelled
    }

    static let shared = LinkPreviewLoadCoordinator()

    private struct FailureEntry {
        var failureCount: Int
        var retryAfter: Date
    }

    private let maxConcurrentLoads = 2
    private let maxTrackedHosts = 256
    private var activeLoads = 0
    private var hostFailures: [String: FailureEntry] = [:]
    private var hostOrder: [String] = []

    func beginLoad(for url: URL, now: Date = Date()) -> BeginDecision {
        clearExpiredFailures(now: now)

        if let host = normalizedHost(for: url),
           let entry = hostFailures[host],
           entry.retryAfter > now {
            return .blockedByBackoff
        }

        guard activeLoads < maxConcurrentLoads else {
            return .atCapacity
        }

        activeLoads += 1
        return .started
    }

    func finishLoad(for url: URL, completion: Completion) {
        activeLoads = max(0, activeLoads - 1)

        guard let host = normalizedHost(for: url) else { return }

        switch completion {
        case .success:
            hostFailures.removeValue(forKey: host)
            hostOrder.removeAll { $0 == host }
        case .failure:
            let nextFailureCount = (hostFailures[host]?.failureCount ?? 0) + 1
            let multiplier = pow(2.0, Double(min(nextFailureCount - 1, 4)))
            let retryDelay = min(90 * multiplier, 30 * 60)
            hostFailures[host] = FailureEntry(
                failureCount: nextFailureCount,
                retryAfter: Date().addingTimeInterval(retryDelay)
            )
            hostOrder.removeAll { $0 == host }
            hostOrder.append(host)
            trimHostsIfNeeded()
        case .cancelled:
            break
        }
    }

    private func clearExpiredFailures(now: Date) {
        let expiredHosts = hostFailures.compactMap { host, entry in
            entry.retryAfter <= now ? host : nil
        }
        guard !expiredHosts.isEmpty else { return }

        let expiredSet = Set(expiredHosts)
        expiredHosts.forEach { hostFailures.removeValue(forKey: $0) }
        hostOrder.removeAll { expiredSet.contains($0) }
    }

    private func trimHostsIfNeeded() {
        while hostOrder.count > maxTrackedHosts {
            let removedHost = hostOrder.removeFirst()
            hostFailures.removeValue(forKey: removedHost)
        }
    }

    private func normalizedHost(for url: URL) -> String? {
        let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return host?.isEmpty == false ? host : nil
    }
}

@MainActor
private final class LinkMetadataLoader: ObservableObject {
    @Published var title: String?
    @Published var summary: String?
    @Published var image: UIImage?

    let hostDisplay: String
    private let url: URL
    private var metadataProvider: LPMetadataProvider?
    private var isLoading = false
    private static let metadataLoadTimeoutNanoseconds: UInt64 = 8_000_000_000
    private static let imageLoadTimeoutNanoseconds: UInt64 = 6_000_000_000

    private static let metadataCache: NSCache<NSURL, LPLinkMetadata> = {
        let cache = NSCache<NSURL, LPLinkMetadata>()
        cache.countLimit = 96
        return cache
    }()

    private static let imageCache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 24 * 1_024 * 1_024
        return cache
    }()

    init(url: URL) {
        self.url = url
        hostDisplay = url.host ?? url.absoluteString
    }

    func startIfNeeded() async {
        let cacheKey = url as NSURL
        if let cachedMetadata = Self.metadataCache.object(forKey: cacheKey) {
            apply(metadata: cachedMetadata)
            if let cachedImage = Self.imageCache.object(forKey: cacheKey) {
                image = cachedImage
            } else {
                await loadImageIfNeeded(metadata: cachedMetadata, cacheKey: cacheKey)
            }
            return
        }

        guard !isLoading else { return }

        var decision = await Self.coordinator.beginLoad(for: url)
        while decision == .atCapacity && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 200_000_000)
            decision = await Self.coordinator.beginLoad(for: url)
        }

        guard !Task.isCancelled else { return }
        guard decision == .started else { return }

        isLoading = true
        var completion: LinkPreviewLoadCoordinator.Completion = .failure
        defer {
            isLoading = false
            metadataProvider = nil
            let url = self.url
            Task {
                await Self.coordinator.finishLoad(for: url, completion: completion)
            }
        }

        let provider = LPMetadataProvider()
        metadataProvider = provider

        guard let metadata = await fetchMetadata(with: provider) else {
            completion = Task.isCancelled ? .cancelled : .failure
            return
        }

        guard !Task.isCancelled else {
            completion = .cancelled
            return
        }

        Self.metadataCache.setObject(metadata, forKey: cacheKey)
        apply(metadata: metadata)
        completion = .success
        await loadImageIfNeeded(metadata: metadata, cacheKey: cacheKey)
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

    func cancelPendingLoad() {
        metadataProvider?.cancel()
    }

    private func fetchMetadata(with provider: LPMetadataProvider) async -> LPLinkMetadata? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<LPLinkMetadata?, Never>) in
                var didResume = false
                func finish(_ metadata: LPLinkMetadata?) {
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume(returning: metadata)
                }
                let timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: Self.metadataLoadTimeoutNanoseconds)
                    await MainActor.run {
                        provider.cancel()
                        finish(nil)
                    }
                }
                provider.startFetchingMetadata(for: url) { metadata, _ in
                    Task { @MainActor in
                        timeoutTask.cancel()
                        finish(metadata)
                    }
                }
            }
        } onCancel: {
            provider.cancel()
        }
    }

    private func loadImageIfNeeded(metadata: LPLinkMetadata, cacheKey: NSURL) async {
        if let cachedImage = Self.imageCache.object(forKey: cacheKey) {
            image = cachedImage
            return
        }
        guard let provider = metadata.imageProvider else { return }
        guard provider.canLoadObject(ofClass: UIImage.self) else { return }

        let loadedImage = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            var didResume = false
            func finish(_ image: UIImage?) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: image)
            }
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: Self.imageLoadTimeoutNanoseconds)
                await MainActor.run {
                    finish(nil)
                }
            }
            _ = provider.loadObject(ofClass: UIImage.self) { object, _ in
                let loadedImage = object as? UIImage
                Task { @MainActor in
                    timeoutTask.cancel()
                    finish(loadedImage)
                }
            }
        }
        guard let loadedImage, !Task.isCancelled else { return }

        Self.imageCache.setObject(
            loadedImage,
            forKey: cacheKey,
            cost: Self.imageMemoryCost(for: loadedImage)
        )
        image = loadedImage
    }

    private static let coordinator = LinkPreviewLoadCoordinator.shared

    private static func imageMemoryCost(for image: UIImage) -> Int {
        let scale = image.scale
        let width = Int(image.size.width * scale)
        let height = Int(image.size.height * scale)
        guard width > 0, height > 0 else { return 1 }
        return width * height * 4
    }
}

private actor CustomEmojiImageLoader {
    static let shared = CustomEmojiImageLoader()

    func image(for url: URL) async -> UIImage? {
        await FlowImageCache.shared.image(for: url)
    }
}

enum NoteMediaAsset {
    case still(UIImage)
    case gif(NoteGIFPayload)

    var size: CGSize {
        switch self {
        case .still(let image):
            return image.size
        case .gif(let payload):
            return payload.size
        }
    }

    var aspectRatio: CGFloat? {
        let resolvedSize = size
        guard resolvedSize.width > 0, resolvedSize.height > 0 else { return nil }
        return resolvedSize.width / resolvedSize.height
    }
}

enum NoteMediaScaling {
    case fill
    case fit

    var swiftUIContentMode: ContentMode {
        switch self {
        case .fill:
            return .fill
        case .fit:
            return .fit
        }
    }

    var uiKitContentMode: UIView.ContentMode {
        switch self {
        case .fill:
            return .scaleAspectFill
        case .fit:
            return .scaleAspectFit
        }
    }
}

struct NoteMediaAssetContentView: View {
    let asset: NoteMediaAsset
    let scaling: NoteMediaScaling

    private var boundedAspectRatio: CGFloat? {
        FlowLayoutGuardrails.clampedAspectRatio(asset.aspectRatio)
    }

    var body: some View {
        Group {
            switch asset {
            case .still(let image):
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: scaling.swiftUIContentMode)
            case .gif(let payload):
                NoteAnimatedGIFView(
                    payload: payload,
                    contentMode: scaling.uiKitContentMode
                )
            }
        }
        .aspectRatio(boundedAspectRatio, contentMode: scaling.swiftUIContentMode)
        .frame(maxWidth: .infinity, alignment: .center)
        .clipped()
    }
}

private struct NoteZoomableFullscreenImageView: View {
    let url: URL
    let chromeForegroundColor: Color
    let onZoomStateChange: (Bool) -> Void

    var body: some View {
        NoteRemoteMediaView(url: url) { asset in
            switch asset {
            case .still:
                NoteZoomableImageView(
                    asset: asset,
                    onZoomStateChange: onZoomStateChange
                )
                .padding(16)
            case .gif(let payload):
                NoteAnimatedGIFView(
                    payload: payload,
                    contentMode: .scaleAspectFit
                )
                .padding(16)
                .onAppear {
                    onZoomStateChange(false)
                }
            }
        } placeholder: {
            ProgressView()
                .tint(chromeForegroundColor)
        } failure: {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(chromeForegroundColor.opacity(0.75))
                .onAppear {
                    onZoomStateChange(false)
                }
        }
        .onDisappear {
            onZoomStateChange(false)
        }
    }
}

struct NoteRemoteMediaView<Content: View, Placeholder: View, Failure: View>: View {
    let url: URL
    @ViewBuilder let content: (NoteMediaAsset) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    @ViewBuilder let failure: () -> Failure

    @State private var asset: NoteMediaAsset?
    @State private var loadedURL: URL?
    @State private var didFailLoading = false

    var body: some View {
        Group {
            if let asset {
                content(asset)
            } else if didFailLoading {
                failure()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loadIfNeeded()
        }
    }

    @MainActor
    private func loadIfNeeded() async {
        if loadedURL != url {
            loadedURL = url
            asset = nil
            didFailLoading = false
        }

        guard asset == nil, !didFailLoading else { return }

        if let loadedAsset = await NoteMediaAssetLoader.shared.asset(for: url) {
            asset = loadedAsset
            didFailLoading = false
        } else {
            didFailLoading = true
        }
    }
}

private struct NoteZoomableImageView: UIViewRepresentable {
    let asset: NoteMediaAsset
    let onZoomStateChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onZoomStateChange: onZoomStateChange)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = LayoutAwareZoomScrollView()
        scrollView.backgroundColor = .clear
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = context.coordinator.imageView
        imageView.backgroundColor = .clear
        imageView.clipsToBounds = false
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        scrollView.addGestureRecognizer(doubleTap)
        context.coordinator.doubleTapRecognizer = doubleTap
        context.coordinator.scrollView = scrollView
        scrollView.onLayout = { [weak coordinator = context.coordinator] scrollView in
            coordinator?.handleLayout(in: scrollView)
        }

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.onZoomStateChange = onZoomStateChange
        context.coordinator.updateAsset(asset, in: scrollView)
    }

    static func dismantleUIView(_ scrollView: UIScrollView, coordinator: Coordinator) {
        coordinator.onZoomStateChange(false)
        coordinator.imageView.stopAnimating()
        coordinator.imageView.image = nil
        coordinator.scrollView = nil
        coordinator.doubleTapRecognizer = nil
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        let imageView = UIImageView()
        weak var scrollView: UIScrollView?
        weak var doubleTapRecognizer: UITapGestureRecognizer?
        var onZoomStateChange: (Bool) -> Void

        private var currentAsset: NoteMediaAsset?
        private var currentAssetIdentifier: ObjectIdentifier?
        private var lastReportedZoomedState = false
        private var lastBoundsSize: CGSize = .zero

        init(onZoomStateChange: @escaping (Bool) -> Void) {
            self.onZoomStateChange = onZoomStateChange
        }

        func updateAsset(_ asset: NoteMediaAsset, in scrollView: UIScrollView) {
            self.scrollView = scrollView
            currentAsset = asset

            applyLayout(for: asset, in: scrollView)
        }

        func handleLayout(in scrollView: UIScrollView) {
            guard let currentAsset else { return }
            applyLayout(for: currentAsset, in: scrollView)
        }

        private func applyLayout(for asset: NoteMediaAsset, in scrollView: UIScrollView) {
            let assetIdentifier = Self.assetIdentifier(for: asset)
            let boundsSize = scrollView.bounds.size
            let assetChanged = currentAssetIdentifier != assetIdentifier
            if assetChanged {
                currentAssetIdentifier = assetIdentifier
                configureImageView(for: asset)
                scrollView.zoomScale = 1
                reportZoomState(false)
            }

            guard boundsSize.width > 0, boundsSize.height > 0 else { return }

            if assetChanged ||
                lastBoundsSize != boundsSize ||
                scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 {
                imageView.frame = scrollView.bounds
                scrollView.contentSize = scrollView.bounds.size
                lastBoundsSize = boundsSize
            }

            centerImage(in: scrollView)
            updatePanGestureState(for: scrollView)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage(in: scrollView)
            updatePanGestureState(for: scrollView)
            reportZoomState(scrollView.zoomScale > scrollView.minimumZoomScale + 0.01)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            reportZoomState(scale > scrollView.minimumZoomScale + 0.01)
        }

        @objc
        func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }

            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }

            let tapPoint = gesture.location(in: imageView)
            let targetScale = min(scrollView.maximumZoomScale, 2.5)
            let zoomRect = zoomRect(
                for: targetScale,
                centeredAt: tapPoint,
                in: scrollView
            )
            scrollView.zoom(to: zoomRect, animated: true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        private func configureImageView(for asset: NoteMediaAsset) {
            imageView.stopAnimating()
            imageView.image = nil

            switch asset {
            case .still(let image):
                imageView.image = image
            case .gif(let payload):
                imageView.image = payload.previewImage
            }
        }

        private func centerImage(in scrollView: UIScrollView) {
            let boundsSize = scrollView.bounds.size
            var frameToCenter = imageView.frame

            frameToCenter.origin.x = frameToCenter.size.width < boundsSize.width
                ? (boundsSize.width - frameToCenter.size.width) / 2
                : 0
            frameToCenter.origin.y = frameToCenter.size.height < boundsSize.height
                ? (boundsSize.height - frameToCenter.size.height) / 2
                : 0

            imageView.frame = frameToCenter
        }

        private func updatePanGestureState(for scrollView: UIScrollView) {
            scrollView.panGestureRecognizer.isEnabled = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
        }

        private func reportZoomState(_ isZoomed: Bool) {
            guard lastReportedZoomedState != isZoomed else { return }
            lastReportedZoomedState = isZoomed
            onZoomStateChange(isZoomed)
        }

        private func zoomRect(for scale: CGFloat, centeredAt center: CGPoint, in scrollView: UIScrollView) -> CGRect {
            let bounds = scrollView.bounds
            let width = bounds.width / scale
            let height = bounds.height / scale
            return CGRect(
                x: center.x - (width / 2),
                y: center.y - (height / 2),
                width: width,
                height: height
            )
        }

        private static func assetIdentifier(for asset: NoteMediaAsset) -> ObjectIdentifier {
            switch asset {
            case .still(let image):
                return ObjectIdentifier(image)
            case .gif(let payload):
                return ObjectIdentifier(payload.previewImage)
            }
        }
    }
}

private final class LayoutAwareZoomScrollView: UIScrollView {
    var onLayout: ((UIScrollView) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}

struct NoteGIFPayload {
    let url: URL
    let data: Data
    let previewImage: UIImage
    let frameDurations: [TimeInterval]

    var frameCount: Int {
        frameDurations.count
    }

    var size: CGSize {
        previewImage.size
    }

    static func make(from data: Data, url: URL) -> NoteGIFPayload? {
        guard data.starts(with: [0x47, 0x49, 0x46]),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1 else { return nil }

        let previewOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: 2_048
        ]

        guard let previewCGImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            previewOptions as CFDictionary
        ) ?? CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let previewImage = UIImage(cgImage: previewCGImage)
        let frameDurations = (0..<frameCount).map {
            Self.frameDuration(forFrameAt: $0, source: source)
        }

        return NoteGIFPayload(
            url: url,
            data: data,
            previewImage: previewImage,
            frameDurations: frameDurations
        )
    }

    private static func frameDuration(forFrameAt index: Int, source: CGImageSource) -> TimeInterval {
        let defaultDelay = 0.1
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return defaultDelay
        }

        let unclampedDelay = (gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
        let delay = (gifProperties[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
        let frameDelay = unclampedDelay ?? delay ?? defaultDelay
        return frameDelay < 0.02 ? defaultDelay : frameDelay
    }
}

private struct NoteAnimatedGIFView: UIViewRepresentable {
    let payload: NoteGIFPayload
    let contentMode: UIView.ContentMode

    func makeUIView(context: Context) -> GIFPlayerImageView {
        let imageView = GIFPlayerImageView(frame: .zero)
        imageView.backgroundColor = UIColor.clear
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = false
        return imageView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: GIFPlayerImageView, context: Context) -> CGSize? {
        let aspectRatio = max(payload.size.width / max(payload.size.height, 1), 0.01)

        if let width = proposal.width, let height = proposal.height {
            return CGSize(width: width, height: height)
        }

        if let width = proposal.width {
            return CGSize(width: width, height: width / aspectRatio)
        }

        if let height = proposal.height {
            return CGSize(width: height * aspectRatio, height: height)
        }

        return payload.size
    }

    func updateUIView(_ imageView: GIFPlayerImageView, context: Context) {
        imageView.contentMode = contentMode
        imageView.configure(with: payload)
    }

    static func dismantleUIView(_ imageView: GIFPlayerImageView, coordinator: ()) {
        imageView.stopAnimatingGIF()
        imageView.image = nil
    }
}

private final class GIFPlayerImageView: UIImageView {
    private var payload: NoteGIFPayload?
    private var source: CGImageSource?
    private var displayLink: CADisplayLink?
    private let frameCache = NSCache<NSNumber, UIImage>()
    private var currentFrameIndex = 0
    private var accumulatedTime: TimeInterval = 0
    private var lastTimestamp: CFTimeInterval?
    private var maxPixelSize: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        frameCache.countLimit = 24
        frameCache.totalCostLimit = 24 * 1_024 * 1_024
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        frameCache.countLimit = 24
        frameCache.totalCostLimit = 24 * 1_024 * 1_024
    }

    func configure(with payload: NoteGIFPayload) {
        if self.payload?.url != payload.url || self.payload?.data != payload.data {
            self.payload = payload
            source = CGImageSourceCreateWithData(payload.data as CFData, nil)
            currentFrameIndex = 0
            accumulatedTime = 0
            lastTimestamp = nil
            frameCache.removeAllObjects()
            image = payload.previewImage
        } else if image == nil {
            image = payload.previewImage
        }

        updateFrameDecodingScaleIfNeeded()
        restartIfNeeded()
    }

    override var intrinsicContentSize: CGSize {
        .zero
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateFrameDecodingScaleIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        restartIfNeeded()
    }

    func stopAnimatingGIF() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        accumulatedTime = 0
    }

    private func restartIfNeeded() {
        guard window != nil,
              let payload,
              payload.frameCount > 1 else {
            stopAnimatingGIF()
            return
        }

        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    private func updateFrameDecodingScaleIfNeeded() {
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let candidate = max(bounds.width, bounds.height) * scale
        let resolved = max(1, min(candidate, 2_048))
        guard abs(resolved - maxPixelSize) > 1 else { return }
        maxPixelSize = resolved
        frameCache.removeAllObjects()
        if let payload {
            image = payload.previewImage
        }
    }

    @objc
    private func step(_ displayLink: CADisplayLink) {
        guard let payload,
              payload.frameCount > 1 else {
            stopAnimatingGIF()
            return
        }

        if lastTimestamp == nil {
            lastTimestamp = displayLink.timestamp
            return
        }

        let elapsed = displayLink.timestamp - (lastTimestamp ?? displayLink.timestamp)
        lastTimestamp = displayLink.timestamp
        accumulatedTime += elapsed

        let frameDuration = payload.frameDurations[currentFrameIndex]
        guard accumulatedTime >= frameDuration else { return }

        accumulatedTime.formTruncatingRemainder(dividingBy: frameDuration)
        currentFrameIndex = (currentFrameIndex + 1) % payload.frameCount
        image = decodedFrame(at: currentFrameIndex) ?? payload.previewImage
    }

    private func decodedFrame(at index: Int) -> UIImage? {
        let key = NSNumber(value: index)
        if let cached = frameCache.object(forKey: key) {
            return cached
        }

        guard let source,
              let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                index,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: false,
                    kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 1)
                ] as CFDictionary
              ) ?? CGImageSourceCreateImageAtIndex(source, index, nil) else {
            return nil
        }

        let image = UIImage(cgImage: cgImage)
        frameCache.setObject(image, forKey: key, cost: Self.imageMemoryCost(for: image))
        return image
    }

    private static func imageMemoryCost(for image: UIImage) -> Int {
        let scale = image.scale
        let width = Int(image.size.width * scale)
        let height = Int(image.size.height * scale)
        guard width > 0, height > 0 else { return 1 }
        return width * height * 4
    }
}

private actor NoteMediaAssetLoader {
    static let shared = NoteMediaAssetLoader()

    func asset(for url: URL) async -> NoteMediaAsset? {
        if isLikelyGIF(url),
           let data = await FlowImageCache.shared.data(for: url),
           let payload = NoteGIFPayload.make(from: data, url: url) {
            return .gif(payload)
        }

        guard let image = await FlowImageCache.shared.image(for: url) else {
            return nil
        }
        return .still(image)
    }

    private func isLikelyGIF(_ url: URL) -> Bool {
        url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "gif"
    }
}
