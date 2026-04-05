import SwiftUI
import UIKit
#if canImport(Translation)
import Translation
#endif

struct FeedRowView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @EnvironmentObject private var toastCenter: AppToastCenter
    private let reactionStats = NoteReactionStatsService.shared
    private let muteStore = MuteStore.shared

    struct AvatarMenuActions {
        let followLabel: String
        let onFollowToggle: () -> Void
        let onViewProfile: () -> Void
    }

    let item: FeedItem
    var reactionCount: Int = 0
    var isLikedByCurrentUser: Bool = false
    var commentCount: Int = 0
    var showReactions: Bool = true
    var onAvatarTap: (() -> Void)? = nil
    var avatarMenuActions: AvatarMenuActions? = nil
    var onHashtagTap: ((String) -> Void)? = nil
    var onProfileTap: ((String) -> Void)? = nil
    var onOpenThread: (() -> Void)? = nil
    var onRepostActorTap: ((String) -> Void)? = nil
    var onReferencedEventTap: ((FeedItem) -> Void)? = nil
    var onReplyTap: (() -> Void)? = nil
    var onMuteConversation: ((String) -> Void)? = nil
    var suppressReplyContextForDirectReplyTargetEventID: String? = nil

    @State private var isShowingReshareSheet = false
    @State private var quoteDraft: ReshareQuoteDraft?
    @State private var isShowingReplyComposer = false
    @State private var isPublishingRepost = false
    @State private var repostStatusMessage: String?
    @State private var repostStatusIsError = false
    @State private var isShowingNoteOptionsSheet = false
    @State private var isShowingReportSheet = false
    @State private var isShowingTranslation = false
    private let reshareService = ResharePublishService()
    private let reactionPublishService = NoteReactionPublishService()
    private let reportPublishService = NoteReportPublishService()

    private struct ReplyContextPresentation {
        let parentItem: FeedItem
        let snippet: String?
        let hasImageBadge: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if item.isRepost {
                repostBanner
                    .padding(.leading, 56)
            }

            if shouldShowReplyContext, let replyContextPresentation {
                replyContextRow(replyContextPresentation)
                    .padding(.leading, 56)
            }

            HStack(alignment: .top, spacing: 12) {
                profileAvatar

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(item.displayName)
                                .font(appSettings.appFont(.headline, weight: .semibold))
                                .lineLimit(1)

                            Text(item.handle)
                                .font(appSettings.appFont(.subheadline))
                                .foregroundStyle(mutedChromeColor)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleAuthorTap()
                        }

                        Spacer(minLength: 8)
                            .frame(height: 28)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onOpenThread?()
                            }

                        clientAttributionLabel

                        Text(RelativeTimestampFormatter.shortString(from: item.displayEvent.createdAtDate))
                            .font(appSettings.appFont(.caption1))
                            .foregroundStyle(mutedChromeColor)
                            .lineLimit(1)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onOpenThread?()
                            }

                        noteOptionsButton
                    }

                    NoteContentView(
                        event: item.displayEvent,
                        reactionCount: showReactions ? visibleReactionCount : 0,
                        commentCount: showReactions ? commentCount : 0,
                        onHashtagTap: onHashtagTap,
                        onProfileTap: onProfileTap,
                        onReferencedEventTap: onReferencedEventTap
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .gesture(
                            TapGesture().onEnded {
                                onOpenThread?()
                            },
                            including: .gesture
                        )

                    if showReactions {
                        HStack(spacing: 14) {
                            Button {
                                if let onReplyTap {
                                    onReplyTap()
                                } else {
                                    isShowingReplyComposer = true
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "bubble.right")
                                    if commentCount > 0 {
                                        Text("\(commentCount)")
                                            .font(appSettings.appFont(.footnote))
                                    }
                                }
                                .frame(minWidth: 34, minHeight: 28, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(mutedChromeColor)
                            .accessibilityLabel("Reply")

                            Button {
                                repostStatusMessage = nil
                                repostStatusIsError = false
                                isShowingReshareSheet = true
                            } label: {
                                Image(systemName: "arrow.2.squarepath")
                                    .frame(minWidth: 34, minHeight: 28, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(mutedChromeColor)
                            .accessibilityLabel("Re-share")

                            ReactionButton(
                                isLiked: isLikedByCurrentUser,
                                isBonusReaction: isBonusReactionByCurrentUser,
                                count: visibleReactionCount,
                                bonusActiveColor: appSettings.primaryColor,
                                inactiveColor: mutedChromeColor
                            ) { bonusCount in
                                Task {
                                    await handleReactionTap(bonusCount: bonusCount)
                                }
                            }

                            ShareLink(item: copyableNoteLink) {
                                Image(systemName: "paperplane")
                                    .frame(minWidth: 34, minHeight: 28, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(mutedChromeColor)
                            .accessibilityLabel("Share")
                        }
                        .font(appSettings.appFont(.headline))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, 7)
        .noteTranslationPresentation(
            isPresented: $isShowingTranslation,
            text: noteTranslationText
        )
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
                        for: item,
                        relayHintURL: effectiveReadRelayURLs.first
                    )
                    isShowingReshareSheet = false
                }
            )
        }
        .sheet(isPresented: $isShowingNoteOptionsSheet) {
            NoteOptionsBottomSheetView(
                canCopyText: hasCopyableNoteText,
                onCopyText: {
                    UIPasteboard.general.string = copyableNoteText
                    toastCenter.show("Copied text")
                },
                onCopyLink: {
                    UIPasteboard.general.string = copyableNoteLink
                    toastCenter.show("Copied link")
                },
                showsTranslateAction: canTranslateNote,
                onTranslate: canTranslateNote ? {
                    presentTranslation()
                } : nil,
                onMute: {
                    handleMuteAuthor()
                },
                onReport: {
                    presentReportFlow()
                }
            )
            .presentationDetents([.height(canTranslateNote ? 490 : 435), .medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingReportSheet) {
            NoteReportSheetView(noteAuthorName: item.displayName) { type, details in
                try await submitReport(type: type, details: details)
            }
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
        .sheet(isPresented: $isShowingReplyComposer) {
            ComposeNoteSheet(
                currentAccountPubkey: auth.currentAccount?.pubkey,
                currentNsec: auth.currentNsec,
                writeRelayURLs: effectiveWriteRelayURLs,
                replyTargetEvent: item.displayEvent,
                replyTargetDisplayNameHint: item.displayName,
                replyTargetHandleHint: item.handle,
                replyTargetAvatarURLHint: item.avatarURL
            )
        }
    }

    private var visibleReactionCount: Int {
        reactionCount
    }

    private var isBonusReactionByCurrentUser: Bool {
        reactionStats.currentUserReaction(
            for: item.displayEventID,
            currentPubkey: auth.currentAccount?.pubkey
        )?.bonusCount ?? 0 > 0
    }

    private var mutedChromeColor: Color {
        appSettings.themePalette.mutedForeground
    }

    @ViewBuilder
    private var clientAttributionLabel: some View {
        if let clientName = item.displayEvent.clientName {
            Text("via \(clientName)")
                .font(appSettings.appFont(.caption1))
                .foregroundStyle(mutedChromeColor)
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture {
                    onOpenThread?()
                }
        }
    }

    private var followBadgeIconName: String? {
        guard !isAuthoredByCurrentAccount, let avatarMenuActions else { return nil }
        let normalized = avatarMenuActions.followLabel
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.contains("unfollow") ? "checkmark.circle.fill" : "plus.circle.fill"
    }

    private var isAuthoredByCurrentAccount: Bool {
        guard let currentPubkey = auth.currentAccount?.pubkey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !currentPubkey.isEmpty else {
            return false
        }
        return currentPubkey == item.displayAuthorPubkey.lowercased()
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let avatarMenuActions {
            Menu {
                Button {
                    avatarMenuActions.onFollowToggle()
                } label: {
                    Label(avatarMenuActions.followLabel, systemImage: followMenuIcon(for: avatarMenuActions.followLabel))
                }
                Button {
                    avatarMenuActions.onViewProfile()
                } label: {
                    Label("View Profile", systemImage: "person")
                }
            } label: {
                avatarWithFollowBadge
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile actions for \(item.displayName)")
        } else if let onAvatarTap {
            Button {
                onAvatarTap()
            } label: {
                avatarWithFollowBadge
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile options")
        } else {
            avatarWithFollowBadge
        }
    }

    private var avatarWithFollowBadge: some View {
        AvatarView(url: item.avatarURL, fallback: item.displayName)
            .overlay(alignment: .bottomTrailing) {
                if let followBadgeIconName {
                    ZStack {
                        Circle()
                            .fill(appSettings.themePalette.background)
                            .frame(width: 18, height: 18)

                        Image(systemName: followBadgeIconName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .offset(x: 3, y: 3)
                    .accessibilityHidden(true)
                }
            }
    }

    private var repostBanner: some View {
        Button {
            onRepostActorTap?(item.actorPubkey)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.2.squarepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(mutedChromeColor)

                AvatarView(url: item.actorAvatarURL, fallback: item.actorDisplayName, size: 18)

                Text("\(item.actorDisplayName) reposted")
                    .font(.caption)
                    .foregroundStyle(mutedChromeColor)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .disabled(onRepostActorTap == nil)
    }

    private var shouldShowReplyContext: Bool {
        guard item.displayEvent.isReplyNote, replyContextPresentation != nil else { return false }

        guard let suppressedTargetID = normalizedEventID(suppressReplyContextForDirectReplyTargetEventID) else {
            return true
        }

        let directReplyTargetID = normalizedEventID(item.displayEvent.directReplyEventReferenceID)
        return directReplyTargetID != suppressedTargetID
    }

    private var replyContextPresentation: ReplyContextPresentation? {
        guard let parentItem = item.replyTargetFeedItem else { return nil }

        let imageURLs = NoteContentParser.imageURLs(in: parentItem.displayEvent)
        let hasImageBadge = !imageURLs.isEmpty
        let snippet = replyContextSnippet(for: parentItem.displayEvent, imageURLs: imageURLs)

        guard snippet != nil || hasImageBadge else { return nil }
        return ReplyContextPresentation(
            parentItem: parentItem,
            snippet: snippet,
            hasImageBadge: hasImageBadge
        )
    }

    private var shouldAllowReplyContextNavigation: Bool {
        guard let suppressedTargetID = normalizedEventID(suppressReplyContextForDirectReplyTargetEventID) else {
            return true
        }

        let directReplyTargetID = normalizedEventID(item.displayEvent.directReplyEventReferenceID)
        return directReplyTargetID != suppressedTargetID
    }

    @ViewBuilder
    private func replyContextRow(_ presentation: ReplyContextPresentation) -> some View {
        let content = HStack(spacing: 6) {
            Image(systemName: "arrow.turn.up.left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(mutedChromeColor)

            Text("Replying to")
                .font(.caption)
                .foregroundStyle(mutedChromeColor)
                .lineLimit(1)

            AvatarView(
                url: presentation.parentItem.avatarURL,
                fallback: presentation.parentItem.displayName,
                size: 18
            )

            if let snippet = presentation.snippet {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(mutedChromeColor)
                    .lineLimit(1)
            }

            if presentation.hasImageBadge {
                Text("image")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(mutedChromeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(appSettings.themePalette.tertiaryFill)
                    )
            }

            Spacer(minLength: 0)
        }

        if let onReferencedEventTap,
           shouldAllowReplyContextNavigation {
            Button {
                onReferencedEventTap(presentation.parentItem.threadNavigationItem)
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func replyContextSnippet(for event: NostrEvent, imageURLs: [URL]) -> String? {
        var cleanedContent = event.content
        for imageURL in imageURLs {
            cleanedContent = cleanedContent.replacingOccurrences(of: imageURL.absoluteString, with: " ")
        }

        let normalized = cleanedContent
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }
        guard normalized.count > 72 else { return normalized }

        let endIndex = normalized.index(normalized.startIndex, offsetBy: 72)
        return String(normalized[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private var noteOptionsButton: some View {
        Button {
            isShowingNoteOptionsSheet = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(mutedChromeColor)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Note options")
    }

    private func normalizedEventID(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    @MainActor
    private func handleReactionTap(bonusCount: Int = 0) async {
        let eventID = item.displayEventID
        guard reactionStats.beginPublishingReaction(for: eventID) else { return }
        let existingReaction = reactionStats.currentUserReaction(
            for: eventID,
            currentPubkey: auth.currentAccount?.pubkey
        )
        let optimisticToggle = reactionStats.applyOptimisticToggle(
            for: eventID,
            currentPubkey: auth.currentAccount?.pubkey,
            bonusCount: bonusCount
        )
        defer {
            reactionStats.endPublishingReaction(for: eventID)
        }

        do {
            let result = try await reactionPublishService.toggleReaction(
                for: item.displayEvent,
                existingReactionID: existingReaction?.id,
                bonusCount: bonusCount,
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

    private func handleAuthorTap() {
        if let avatarMenuActions {
            avatarMenuActions.onViewProfile()
            return
        }

        if let onAvatarTap {
            onAvatarTap()
            return
        }

        onOpenThread?()
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
                of: item.displayEvent,
                currentNsec: auth.currentNsec,
                writeRelayURLs: effectiveWriteRelayURLs,
                relayHintURL: effectiveReadRelayURLs.first
            )
            repostStatusMessage = "Reposted to \(relayCount) source\(relayCount == 1 ? "" : "s")."
            repostStatusIsError = false

            try? await Task.sleep(nanoseconds: 450_000_000)
            isShowingReshareSheet = false
        } catch {
            repostStatusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            repostStatusIsError = true
        }
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

    private var copyableNoteLink: String {
        if let externalURL = NoteContentParser.njumpURL(for: item.displayEventID) {
            return externalURL.absoluteString
        }
        return "https://nlink.to/\(item.displayEventID)"
    }

    private var noteTranslationText: String {
        item.displayEvent.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var copyableNoteText: String {
        item.displayEvent.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasCopyableNoteText: Bool {
        !copyableNoteText.isEmpty
    }

    private var canTranslateNote: Bool {
        guard !noteTranslationText.isEmpty else { return false }
        #if canImport(Translation)
        if #available(iOS 18.0, *) {
            return true
        }
        #endif
        return false
    }

    private func followMenuIcon(for label: String) -> String {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("unfollow") {
            return "person.crop.circle.badge.minus"
        }
        return "plus.circle"
    }

    private func presentTranslation() {
        guard canTranslateNote else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            isShowingTranslation = true
        }
    }

    private func handleMuteAuthor() {
        let wasMuted = muteStore.isMuted(item.displayAuthorPubkey)
        muteStore.toggleMute(item.displayAuthorPubkey)
        let isMuted = muteStore.isMuted(item.displayAuthorPubkey)

        if !wasMuted && isMuted {
            toastCenter.show("Muted \(item.displayName)")
        } else if wasMuted && !isMuted {
            toastCenter.show("Unmuted \(item.displayName)", style: .info)
        } else if let errorMessage = muteStore.lastPublishError,
                  !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            toastCenter.show(errorMessage, style: .error, duration: 2.8)
        }
    }

    private func presentReportFlow() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            isShowingReportSheet = true
        }
    }

    private func submitReport(type: NoteReportType, details: String) async throws {
        try await reportPublishService.publishReport(
            for: item.displayEvent,
            type: type,
            details: details,
            currentNsec: auth.currentNsec,
            writeRelayURLs: effectiveWriteRelayURLs
        )
        await MainActor.run {
            toastCenter.show("Report sent")
        }
    }
}

struct NoteOptionsBottomSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettingsStore

    let canCopyText: Bool
    let onCopyText: () -> Void
    let onCopyLink: () -> Void
    let showsTranslateAction: Bool
    let onTranslate: (() -> Void)?
    let onMute: () -> Void
    let onReport: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                optionRow(
                    title: "Copy Text",
                    icon: "text.alignleft",
                    isEnabled: canCopyText,
                    tint: .primary
                ) {
                    onCopyText()
                }

                sheetDivider

                optionRow(
                    title: "Copy Link",
                    icon: "link",
                    isEnabled: true,
                    tint: .primary
                ) {
                    onCopyLink()
                }

                if showsTranslateAction {
                    sheetDivider

                    optionRow(
                        title: "Translate Note",
                        icon: "globe",
                        isEnabled: true,
                        tint: .primary
                    ) {
                        onTranslate?()
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(appSettings.themePalette.secondaryGroupedBackground)
            )

            VStack(spacing: 0) {
                optionRow(
                    title: "Bookmark",
                    icon: "bookmark",
                    isEnabled: false,
                    tint: .secondary
                )

                sheetDivider

                optionRow(
                    title: "Mute",
                    icon: "speaker.slash",
                    isEnabled: true,
                    tint: .primary
                ) {
                    onMute()
                }

                sheetDivider

                optionRow(
                    title: "Report",
                    icon: "exclamationmark.bubble",
                    isEnabled: true,
                    tint: .red
                ) {
                    onReport()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(appSettings.themePalette.secondaryGroupedBackground)
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(appSettings.themePalette.groupedBackground)
    }

    private var sheetDivider: some View {
        Rectangle()
            .fill(appSettings.themePalette.separator)
            .frame(height: 0.75)
            .padding(.leading, 16)
    }

    @ViewBuilder
    private func optionRow(
        title: String,
        icon: String,
        isEnabled: Bool,
        tint: Color,
        action: (() -> Void)? = nil
    ) -> some View {
        Button {
            guard isEnabled else { return }
            action?()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isEnabled ? tint : appSettings.themePalette.mutedForeground)

                Spacer(minLength: 0)

                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isEnabled ? tint : appSettings.themePalette.mutedForeground)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

extension View {
    @ViewBuilder
    func noteTranslationPresentation(
        isPresented: Binding<Bool>,
        text: String
    ) -> some View {
        #if canImport(Translation)
        if #available(iOS 18.0, *) {
            self.translationPresentation(isPresented: isPresented, text: text)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

struct AvatarView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    let url: URL?
    let fallback: String
    var size: CGFloat = 44

    var body: some View {
        Group {
            if appSettings.textOnlyMode {
                fallbackAvatar
            } else if let url {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(appSettings.themePalette.separator, lineWidth: 0.5)
        }
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle().fill(appSettings.themePalette.secondaryFill)
            Text(String(fallback.prefix(1)).uppercased())
                .font(size >= 32 ? .headline : .caption.weight(.semibold))
                .foregroundStyle(appSettings.themePalette.mutedForeground)
        }
    }
}
