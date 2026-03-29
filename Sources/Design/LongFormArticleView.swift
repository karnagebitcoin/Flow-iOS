import NostrSDK
import SwiftUI

struct LongFormArticlePreviewView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    let article: NostrLongFormArticleMetadata
    let onHashtagTap: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                metadataBadge(title: "Article", systemImage: "doc.text.image")
                metadataBadge(title: "\(article.readingTimeMinutes) min read", systemImage: "clock")

                Text(previewDateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let imageURL = article.imageURL {
                LongFormArticleRemoteImage(
                    url: imageURL,
                    alt: article.title,
                    aspectRatio: 16 / 9,
                    maxHeight: 240
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(article.title)
                    .font(.title3.weight(.semibold))
                    .tracking(-0.2)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let summary = article.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !article.tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(article.tags, id: \.self) { tag in
                        hashtagChip(tag)
                    }
                }
            }

            HStack(spacing: 8) {
                Text("Read article")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(appSettings.primaryColor)

                Image(systemName: "arrow.right.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(appSettings.primaryColor)
            }
        }
        .padding(16)
        .background(previewBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(.separator).opacity(0.24), lineWidth: 0.8)
        }
    }

    private var previewDateLabel: String {
        article.publishedDate.formatted(
            Date.FormatStyle()
                .month(.abbreviated)
                .day()
                .year()
        )
    }

    private var previewBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(.secondarySystemBackground),
                Color(.systemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func metadataBadge(title: String, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }

    @ViewBuilder
    private func hashtagChip(_ tag: String) -> some View {
        if let onHashtagTap {
            Button {
                onHashtagTap(tag)
            } label: {
                chipLabel(tag)
            }
            .buttonStyle(.plain)
        } else {
            chipLabel(tag)
        }
    }

    private func chipLabel(_ tag: String) -> some View {
        Text("#\(tag)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color(.separator).opacity(0.2), lineWidth: 0.8)
            }
    }
}

struct LongFormArticleReaderView: View {
    private struct MentionMetadataDecoder: MetadataCoding {}

    @EnvironmentObject private var appSettings: AppSettingsStore

    let item: FeedItem
    let article: NostrLongFormArticleMetadata
    let isOwnedByCurrentUser: Bool
    let isFollowingAuthor: Bool
    let onFollowToggle: () -> Void
    let onProfileTap: ((String) -> Void)?
    let onHashtagTap: ((String) -> Void)?

    private let blocks: [LongFormArticleBlock]

    init(
        item: FeedItem,
        article: NostrLongFormArticleMetadata,
        isOwnedByCurrentUser: Bool,
        isFollowingAuthor: Bool,
        onFollowToggle: @escaping () -> Void,
        onProfileTap: ((String) -> Void)? = nil,
        onHashtagTap: ((String) -> Void)? = nil
    ) {
        self.item = item
        self.article = article
        self.isOwnedByCurrentUser = isOwnedByCurrentUser
        self.isFollowingAuthor = isFollowingAuthor
        self.onFollowToggle = onFollowToggle
        self.onProfileTap = onProfileTap
        self.onHashtagTap = onHashtagTap
        self.blocks = LongFormArticleMarkdownParser.parseBlocks(from: item.displayEvent.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            headerSection

            if let imageURL = article.imageURL {
                LongFormArticleRemoteImage(
                    url: imageURL,
                    alt: article.title,
                    aspectRatio: 16 / 9,
                    maxHeight: 420
                )
            }

            articleBody

            if !article.tags.isEmpty {
                footerTagsSection
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            handleOpenURL(url)
        })
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                readerMetaBadge(title: "Article", systemImage: "doc.text")
                readerMetaBadge(title: "\(article.readingTimeMinutes) min read", systemImage: "clock")

                Text(publishedDateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(article.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .tracking(-0.8)
                    .fixedSize(horizontal: false, vertical: true)

                if let summary = article.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            authorRow
        }
    }

    private var authorRow: some View {
        HStack(alignment: .center, spacing: 12) {
            authorIdentity

            Spacer(minLength: 12)

            if isOwnedByCurrentUser {
                Text("You")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemFill), in: Capsule())
            } else {
                Button(isFollowingAuthor ? "Following" : "Follow") {
                    onFollowToggle()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isFollowingAuthor ? Color.secondary : Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isFollowingAuthor ? Color(.secondarySystemFill) : appSettings.primaryColor,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            isFollowingAuthor
                                ? Color(.separator).opacity(0.3)
                                : appSettings.primaryColor.opacity(0.7),
                            lineWidth: 0.9
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(.separator).opacity(0.2), lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private var authorIdentity: some View {
        if let onProfileTap {
            Button {
                onProfileTap(item.displayAuthorPubkey)
            } label: {
                authorIdentityContent
            }
            .buttonStyle(.plain)
        } else {
            authorIdentityContent
        }
    }

    private var authorIdentityContent: some View {
        HStack(alignment: .center, spacing: 12) {
            AvatarView(url: item.avatarURL, fallback: item.displayName, size: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(item.handle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let nip05 = item.displayProfile?.nip05?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !nip05.isEmpty {
                    Text(nip05)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var articleBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(for block: LongFormArticleBlock) -> some View {
        switch block {
        case .heading(let level, let markdown):
            ArticleMarkdownText(
                markdown: markdown,
                font: headingFont(for: level),
                fontDesign: .rounded
            )
            .tracking(level <= 2 ? -0.4 : -0.2)
        case .paragraph(let markdown):
            ArticleMarkdownText(
                markdown: markdown,
                font: .body,
                fontDesign: .serif
            )
            .lineSpacing(4)
        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("•")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ArticleMarkdownText(
                            markdown: item,
                            font: .body,
                            fontDesign: .serif
                        )
                        .lineSpacing(4)
                    }
                }
            }
        case .orderedList(let start, let items):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(start + index).")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 28, alignment: .leading)

                        ArticleMarkdownText(
                            markdown: item,
                            font: .body,
                            fontDesign: .serif
                        )
                        .lineSpacing(4)
                    }
                }
            }
        case .blockquote(let markdown):
            HStack(alignment: .top, spacing: 14) {
                Capsule()
                    .fill(appSettings.primaryColor.opacity(0.35))
                    .frame(width: 4)

                ArticleMarkdownText(
                    markdown: markdown,
                    font: .body,
                    fontDesign: .serif
                )
                .foregroundStyle(.secondary)
                .lineSpacing(4)
            }
            .padding(18)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 10) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(.separator).opacity(0.18), lineWidth: 0.8)
            }
        case .image(let url, let alt):
            VStack(alignment: .leading, spacing: 8) {
                LongFormArticleRemoteImage(url: url, alt: alt, maxHeight: 520)

                if let alt, !alt.isEmpty {
                    Text(alt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .divider:
            Divider()
                .padding(.vertical, 2)
        }
    }

    private var footerTagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Topics")
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(article.tags, id: \.self) { tag in
                    if let onHashtagTap {
                        Button {
                            onHashtagTap(tag)
                        } label: {
                            Text("#\(tag)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(appSettings.primaryColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(appSettings.primaryColor.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("#\(tag)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(appSettings.primaryColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(appSettings.primaryColor.opacity(0.08), in: Capsule())
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private var publishedDateLabel: String {
        article.publishedDate.formatted(
            Date.FormatStyle()
                .month(.abbreviated)
                .day()
                .year()
        )
    }

    private func readerMetaBadge(title: String, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .system(.title, design: .rounded, weight: .bold)
        case 2:
            return .system(.title2, design: .rounded, weight: .bold)
        case 3:
            return .system(.title3, design: .rounded, weight: .semibold)
        default:
            return .headline
        }
    }

    private func handleOpenURL(_ url: URL) -> OpenURLAction.Result {
        if let pubkey = NoteContentParser.profilePubkey(fromActionURL: url),
           let onProfileTap {
            onProfileTap(pubkey)
            return .handled
        }

        if let hashtag = NoteContentParser.hashtagFromActionURL(url) {
            onHashtagTap?(hashtag)
            return .handled
        }

        if let nostrIdentifier = nostrIdentifier(from: url) {
            if let pubkey = profilePubkey(from: nostrIdentifier),
               let onProfileTap {
                onProfileTap(pubkey)
                return .handled
            }

            if let externalURL = NoteContentParser.njumpURL(for: nostrIdentifier) {
                return .systemAction(externalURL)
            }
        }

        return .systemAction(url)
    }

    private func nostrIdentifier(from url: URL) -> String? {
        let absoluteString = url.absoluteString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if absoluteString.hasPrefix("nostr:") {
            let identifier = String(absoluteString.dropFirst("nostr:".count))
            return identifier.isEmpty ? nil : identifier
        }

        if absoluteString.hasPrefix("npub1") || absoluteString.hasPrefix("nprofile1") {
            return absoluteString
        }

        return nil
    }

    private func profilePubkey(from identifier: String) -> String? {
        if identifier.hasPrefix("npub1") {
            return PublicKey(npub: identifier)?.hex.lowercased()
        }

        guard identifier.hasPrefix("nprofile1") else { return nil }
        let decoder = MentionMetadataDecoder()
        return try? decoder.decodedMetadata(from: identifier).pubkey?.lowercased()
    }
}

private struct ArticleMarkdownText: View {
    let markdown: String
    let font: Font
    let fontDesign: Font.Design?

    var body: some View {
        Text(attributedString)
            .font(font)
            .fontDesign(fontDesign)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributedString: AttributedString {
        if let parsed = try? AttributedString(markdown: markdown) {
            return parsed
        }
        return AttributedString(markdown)
    }
}

private struct LongFormArticleRemoteImage: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    let url: URL
    let alt: String?
    var aspectRatio: CGFloat? = nil
    var maxHeight: CGFloat? = nil

    var body: some View {
        Group {
            if appSettings.textOnlyMode {
                hiddenImagePlaceholder
            } else {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        renderedImage(image)
                    case .failure:
                        hiddenImagePlaceholder
                    default:
                        loadingPlaceholder
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(.separator).opacity(0.18), lineWidth: 0.8)
        }
    }

    private func renderedImage(_ image: Image) -> some View {
        Group {
            if let aspectRatio {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(aspectRatio, contentMode: .fill)
            } else {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: maxHeight ?? 520)
            }
        }
        .background(Color(.secondarySystemBackground))
    }

    private var loadingPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            ProgressView()
        }
        .frame(maxWidth: .infinity)
        .frame(height: aspectRatio == nil ? 220 : nil)
        .aspectRatio(aspectRatio, contentMode: .fit)
    }

    private var hiddenImagePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: appSettings.textOnlyMode ? "photo.slash" : "photo")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(appSettings.textOnlyMode ? "Image hidden in Text Only Mode" : (alt ?? "Image unavailable"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: aspectRatio == nil ? 160 : nil)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .background(Color(.secondarySystemBackground))
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let availableWidth = proposal.width ?? .greatestFiniteMagnitude
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX > 0, currentX + size.width > availableWidth {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }

        return CGSize(
            width: proposal.width ?? currentX,
            height: currentY + rowHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX > bounds.minX, currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
