import SwiftUI
import UIKit
#if canImport(Translation)
import Translation
#endif

struct FeedRowView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @ObservedObject private var reactionStats = NoteReactionStatsService.shared

    struct AvatarMenuActions {
        let followLabel: String
        let onFollowToggle: () -> Void
        let onViewProfile: () -> Void
    }

    let item: FeedItem
    var reactionCount: Int = 0
    var commentCount: Int = 0
    var showReactions: Bool = true
    var onAvatarTap: (() -> Void)? = nil
    var avatarMenuActions: AvatarMenuActions? = nil
    var onHashtagTap: ((String) -> Void)? = nil
    var onOpenThread: (() -> Void)? = nil
    var onRepostActorTap: ((String) -> Void)? = nil
    var onReferencedEventTap: ((FeedItem) -> Void)? = nil
    var onReplyTap: (() -> Void)? = nil
    var onMuteConversation: ((String) -> Void)? = nil

    @State private var isShowingReshareSheet = false
    @State private var quoteDraft: ReshareQuoteDraft?
    @State private var isPublishingRepost = false
    @State private var repostStatusMessage: String?
    @State private var repostStatusIsError = false
    @State private var isShowingNoteOptionsSheet = false
    @State private var isShowingTranslation = false
    private let reshareService = ResharePublishService()
    private let reactionPublishService = NoteReactionPublishService()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if item.isRepost {
                repostBanner
                    .padding(.leading, 56)
            }

            if item.displayEvent.isReplyNote, let snippet = item.replyTargetSnippet {
                replyContextRow(snippet: snippet)
                    .padding(.leading, 56)
            }

            HStack(alignment: .top, spacing: 12) {
                profileAvatar

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(item.displayName)
                                .font(.headline)
                                .lineLimit(1)

                            Text(item.handle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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

                        Text(RelativeTimestampFormatter.shortString(from: item.displayEvent.createdAtDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                        onReferencedEventTap: onReferencedEventTap
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onOpenThread?()
                        }

                    if showReactions {
                        HStack(spacing: 14) {
                            ReactionButton(
                                isLiked: isLikedByCurrentUser,
                                count: visibleReactionCount
                            ) {
                                Task {
                                    await handleReactionTap()
                                }
                            }

                            Button {
                                if let onReplyTap {
                                    onReplyTap()
                                } else {
                                    onOpenThread?()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "bubble.right")
                                    if commentCount > 0 {
                                        Text("\(commentCount)")
                                            .font(.footnote)
                                    }
                                }
                                .frame(minWidth: 34, minHeight: 28, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)

                            Button {
                                repostStatusMessage = nil
                                repostStatusIsError = false
                                isShowingReshareSheet = true
                            } label: {
                                Image(systemName: "arrow.2.squarepath")
                                    .frame(minWidth: 34, minHeight: 28, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Re-share")

                            ShareLink(item: "nostr:\(item.displayEventID)") {
                                Image(systemName: "paperplane")
                                    .frame(minWidth: 34, minHeight: 28, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Share")
                        }
                        .font(.headline)
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
                onCopyLink: {
                    UIPasteboard.general.string = copyableNoteLink
                },
                showsTranslateAction: canTranslateNote,
                onTranslate: canTranslateNote ? {
                    presentTranslation()
                } : nil,
                onMute: {
                    MuteStore.shared.toggleMute(item.displayAuthorPubkey)
                }
            )
            .presentationDetents([.height(canTranslateNote ? 390 : 335), .medium])
            .presentationDragIndicator(.visible)
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
    }

    private var visibleReactionCount: Int {
        reactionCount
    }

    private var isLikedByCurrentUser: Bool {
        reactionStats.isReactedByCurrentUser(
            for: item.displayEventID,
            currentPubkey: auth.currentAccount?.pubkey
        )
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
                            .fill(Color(.systemBackground))
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
                    .foregroundStyle(.secondary)

                AvatarView(url: item.actorAvatarURL, fallback: item.actorDisplayName, size: 18)

                Text("\(item.actorDisplayName) reposted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .disabled(onRepostActorTap == nil)
    }

    @ViewBuilder
    private func replyContextRow(snippet: String) -> some View {
        let content = HStack(spacing: 6) {
            Image(systemName: "arrow.turn.up.left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            (
                Text("Replying to ")
                    .foregroundStyle(.secondary)
                +
                Text(snippet)
                    .foregroundStyle(.secondary)
            )
            .font(.caption)
            .lineLimit(1)

            Spacer(minLength: 0)
        }

        if let parentItem = item.replyTargetFeedItem,
           let onReferencedEventTap {
            Button {
                onReferencedEventTap(parentItem.threadNavigationItem)
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var noteOptionsButton: some View {
        Button {
            isShowingNoteOptionsSheet = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Note options")
    }

    @MainActor
    private func handleReactionTap() async {
        let eventID = item.displayEventID
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
                for: item.displayEvent,
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
            repostStatusMessage = "Reposted to \(relayCount) relay\(relayCount == 1 ? "" : "s")."
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
        return "nostr:\(item.displayEventID)"
    }

    private var noteTranslationText: String {
        item.displayEvent.content.trimmingCharacters(in: .whitespacesAndNewlines)
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
}

private struct NoteOptionsBottomSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let onCopyLink: () -> Void
    let showsTranslateAction: Bool
    let onTranslate: (() -> Void)?
    let onMute: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                optionRow(
                    title: "Copy Link",
                    icon: "link",
                    isEnabled: true,
                    tint: .primary
                ) {
                    onCopyLink()
                }

                if showsTranslateAction {
                    Divider()
                        .padding(.leading, 16)

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
                    .fill(Color(.secondarySystemBackground))
            )

            VStack(spacing: 0) {
                optionRow(
                    title: "Bookmark",
                    icon: "bookmark",
                    isEnabled: false,
                    tint: .secondary
                )

                Divider()
                    .padding(.leading, 16)

                optionRow(
                    title: "Mute",
                    icon: "speaker.slash",
                    isEnabled: true,
                    tint: .primary
                ) {
                    onMute()
                }

                Divider()
                    .padding(.leading, 16)

                optionRow(
                    title: "Report",
                    icon: "exclamationmark.bubble",
                    isEnabled: false,
                    tint: .red
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(Color(.systemGroupedBackground))
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
                    .foregroundStyle(isEnabled ? tint : Color.secondary)

                Spacer(minLength: 0)

                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isEnabled ? tint : Color.secondary)
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

private extension View {
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
            Circle().stroke(Color(.separator), lineWidth: 0.5)
        }
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle().fill(Color(.secondarySystemFill))
            Text(String(fallback.prefix(1)).uppercased())
                .font(size >= 32 ? .headline : .caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
