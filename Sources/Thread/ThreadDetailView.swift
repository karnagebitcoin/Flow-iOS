import SwiftUI
import UIKit

struct ThreadDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @EnvironmentObject private var toastCenter: AppToastCenter
    @StateObject private var viewModel: ThreadDetailViewModel
    @ObservedObject private var reactionStats = NoteReactionStatsService.shared
    @ObservedObject private var followStore = FollowStore.shared
    @ObservedObject private var muteStore = MuteStore.shared

    @State private var selectedThreadItem: FeedItem?
    @State private var activeReplyTarget: FeedItem?
    @State private var selectedHashtagRoute: HashtagRoute?
    @State private var selectedProfileRoute: ProfileRoute?
    @State private var selectedContentTab: ThreadDetailContentTab = .replies
    @State private var hasAppliedInitialReplyFocus = false
    @State private var hasAppliedInitialReplyScroll = false
    @State private var pendingReplyScrollTargetID: String?
    @State private var isShowingReshareSheet = false
    @State private var quoteDraft: ReshareQuoteDraft?
    @State private var isPublishingRepost = false
    @State private var repostStatusMessage: String?
    @State private var repostStatusIsError = false
    @State private var isShowingRootNoteOptionsSheet = false
    @State private var isShowingRootReportSheet = false
    @State private var isShowingRootTranslation = false

    private let reactionPublishService: NoteReactionPublishService
    private let reshareService: ResharePublishService
    private let reportPublishService: NoteReportPublishService
    private let initialReplyScrollTargetID: String?
    private let initiallyFocusReplyComposer: Bool

    init(
        initialItem: FeedItem,
        relayURL: URL,
        readRelayURLs: [URL]? = nil,
        initialReplyScrollTargetID: String? = nil,
        initiallyFocusReplyComposer: Bool = false,
        service: NostrFeedService = NostrFeedService(),
        reactionPublishService: NoteReactionPublishService = NoteReactionPublishService(),
        reshareService: ResharePublishService = ResharePublishService(),
        reportPublishService: NoteReportPublishService = NoteReportPublishService()
    ) {
        _viewModel = StateObject(
            wrappedValue: ThreadDetailViewModel(
                rootItem: initialItem,
                relayURL: relayURL,
                readRelayURLs: readRelayURLs,
                service: service
            )
        )
        self.reactionPublishService = reactionPublishService
        self.reshareService = reshareService
        self.reportPublishService = reportPublishService
        self.initialReplyScrollTargetID = initialReplyScrollTargetID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.initiallyFocusReplyComposer = initiallyFocusReplyComposer
    }

    var body: some View {
        Group {
            if let articleMetadata {
                articleDetailBody(articleMetadata: articleMetadata)
            } else {
                noteDetailBody
            }
        }
        .background(appSettings.themePalette.background)
        .navigationTitle(articleMetadata == nil ? "Note" : "Article")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: auth.currentAccount?.pubkey) { _, _ in
            configureStores()
        }
        .onChange(of: auth.currentNsec) { _, _ in
            configureStores()
        }
        .onChange(of: relaySettings.readRelays) { _, _ in
            configureStores()
        }
        .onChange(of: relaySettings.writeRelays) { _, _ in
            configureStores()
        }
        .onChange(of: appSettings.slowConnectionMode) { _, _ in
            configureStores()
        }
        .navigationDestination(item: $selectedHashtagRoute) { route in
            HashtagFeedView(
                hashtag: route.normalizedHashtag,
                relayURL: effectiveRelayURL,
                readRelayURLs: effectiveReadRelayURLs,
                seedItems: route.seedItems
            )
        }
        .navigationDestination(item: $selectedThreadItem) { item in
            ThreadDetailView(
                initialItem: item,
                relayURL: effectiveRelayURL,
                readRelayURLs: effectiveReadRelayURLs
            )
        }
        .navigationDestination(item: $selectedProfileRoute) { route in
            ProfileView(
                pubkey: route.pubkey,
                relayURL: effectiveRelayURL,
                readRelayURLs: effectiveReadRelayURLs,
                writeRelayURLs: effectiveWriteRelayURLs
            )
        }
        .sheet(isPresented: $isShowingReshareSheet) {
            ReshareActionSheetView(
                isWorking: isPublishingRepost,
                statusMessage: repostStatusMessage,
                statusIsError: repostStatusIsError,
                onRepost: {
                    Task {
                        await publishRootRepost()
                    }
                },
                onQuote: {
                    quoteDraft = reshareService.buildQuoteDraft(
                        for: viewModel.rootItem,
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
                quotedAvatarURLHint: draft.quotedAvatarURLHint,
                onPublished: {
                    Task {
                        await viewModel.refresh()
                    }
                }
            )
        }
        .sheet(item: $activeReplyTarget) { target in
            ComposeNoteSheet(
                currentAccountPubkey: auth.currentAccount?.pubkey,
                currentNsec: auth.currentNsec,
                writeRelayURLs: effectiveWriteRelayURLs,
                replyTargetEvent: target.displayEvent,
                replyTargetDisplayNameHint: target.displayName,
                replyTargetHandleHint: target.handle,
                replyTargetAvatarURLHint: target.avatarURL,
                onPublished: {
                    Task {
                        await viewModel.refresh()
                    }
                }
            )
        }
        .sheet(isPresented: $isShowingRootNoteOptionsSheet) {
            NoteOptionsBottomSheetView(
                canCopyText: rootHasCopyableNoteText,
                onCopyText: {
                    UIPasteboard.general.string = rootCopyableNoteText
                    toastCenter.show("Copied text")
                },
                onCopyLink: {
                    UIPasteboard.general.string = rootNoteShareLink
                    toastCenter.show("Copied link")
                },
                showsTranslateAction: rootCanTranslateNote,
                onTranslate: rootCanTranslateNote ? {
                    presentRootTranslation()
                } : nil,
                onMute: {
                    handleRootMuteAuthor()
                },
                onReport: {
                    presentRootReportFlow()
                }
            )
            .presentationDetents([.height(rootCanTranslateNote ? 490 : 435), .medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingRootReportSheet) {
            NoteReportSheetView(noteAuthorName: viewModel.rootItem.displayName) { type, details in
                try await submitRootReport(type: type, details: details)
            }
        }
        .noteTranslationPresentation(
            isPresented: $isShowingRootTranslation,
            text: rootNoteTranslationText
        )
        .safeAreaInset(edge: .bottom) {
            replyDockBar
        }
    }

    private var noteDetailBody: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    rootNoteCard

                    Divider()
                        .padding(.leading, 16)

                    threadDetailContentSection
                }
            }
            .refreshable {
                await viewModel.refresh(
                    includeNoteActivity: selectedContentTab == .reactions || viewModel.hasLoadedNoteActivity
                )
            }
            .task {
                await performInitialLoad(isArticle: false)
            }
            .onChange(of: pendingReplyScrollTargetID) { _, replyID in
                guard let replyID else { return }
                Task { @MainActor in
                    await scrollReplyIntoView(replyID: replyID, using: scrollProxy)
                    pendingReplyScrollTargetID = nil
                }
            }
            .onChange(of: selectedContentTab) { _, newValue in
                guard newValue == .reactions else { return }
                Task {
                    await viewModel.loadNoteActivityIfNeeded()
                }
            }
        }
    }

    private func articleDetailBody(articleMetadata: NostrLongFormArticleMetadata) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if hideNSFWEnabled && viewModel.rootItem.moderationEvents.contains(where: { $0.containsNSFWHashtag }) {
                    nsfwHiddenCard
                } else {
                    LongFormArticleReaderView(
                        item: viewModel.rootItem,
                        article: articleMetadata,
                        isOwnedByCurrentUser: isRootOwnedByCurrentAccount,
                        isFollowingAuthor: followStore.isFollowing(viewModel.rootItem.displayAuthorPubkey),
                        onFollowToggle: {
                            followStore.toggleFollow(viewModel.rootItem.displayAuthorPubkey)
                        },
                        onProfileTap: { pubkey in
                            openProfile(pubkey: pubkey)
                        },
                        onHashtagTap: { hashtag in
                            openHashtagFeed(hashtag: hashtag)
                        }
                    )

                    if appSettings.reactionsVisibleInFeeds {
                        VStack(alignment: .leading, spacing: 18) {
                            Divider()
                            rootInteractionRow
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .refreshable {
            await viewModel.refresh(includeNoteActivity: viewModel.hasLoadedNoteActivity)
        }
        .task {
            await performInitialLoad(isArticle: true)
        }
    }

    private var rootNoteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: rootNip05Label == nil ? .center : .top, spacing: 10) {
                Menu {
                    Button {
                        followStore.toggleFollow(viewModel.rootItem.displayAuthorPubkey)
                    } label: {
                        Label(
                            followStore.isFollowing(viewModel.rootItem.displayAuthorPubkey) ? "Unfollow" : "Follow",
                            systemImage: followStore.isFollowing(viewModel.rootItem.displayAuthorPubkey)
                                ? "person.crop.circle.badge.minus"
                                : "plus.circle"
                        )
                    }
                    Button {
                        openProfile(pubkey: viewModel.rootItem.displayAuthorPubkey)
                    } label: {
                        Label("View Profile", systemImage: "person")
                    }
                } label: {
                    rootAvatar
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile actions for \(viewModel.rootItem.displayName)")

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(viewModel.rootItem.displayName)
                            .font(.headline)
                            .lineLimit(1)

                        Text(viewModel.rootItem.handle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        if let clientName = viewModel.rootItem.displayEvent.clientName {
                            Text("via \(clientName)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text(RelativeTimestampFormatter.shortString(from: viewModel.rootItem.displayEvent.createdAtDate))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        rootNoteOptionsButton
                    }

                    if let rootNip05Label {
                        Text(rootNip05Label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

            }

            if hideNSFWEnabled && viewModel.rootItem.moderationEvents.contains(where: { $0.containsNSFWHashtag }) {
                nsfwHiddenCard
            } else {
                NoteContentView(
                    event: viewModel.rootItem.displayEvent,
                    mediaLayout: .feed,
                    reactionCount: appSettings.reactionsVisibleInFeeds ? rootReactionCount : 0,
                    commentCount: appSettings.reactionsVisibleInFeeds ? threadReplies.count : 0,
                    onHashtagTap: { hashtag in
                        openHashtagFeed(hashtag: hashtag)
                    },
                    onProfileTap: { pubkey in
                        openProfile(pubkey: pubkey)
                    },
                    onReferencedEventTap: { referencedItem in
                        selectedThreadItem = referencedItem.threadNavigationItem
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if appSettings.reactionsVisibleInFeeds {
                rootInteractionRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var rootInteractionRow: some View {
        HStack(spacing: 14) {
            Button {
                presentReplyComposer(for: viewModel.rootItem.canonicalDisplayItem)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.right")
                    if !threadReplies.isEmpty {
                        Text("\(threadReplies.count)")
                            .font(.footnote)
                    }
                }
                .frame(minWidth: 34, minHeight: 30, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Reply")

            Button {
                repostStatusMessage = nil
                repostStatusIsError = false
                isShowingReshareSheet = true
            } label: {
                Image(systemName: "arrow.2.squarepath")
                    .frame(minWidth: 34, minHeight: 30, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Re-share")

            ReactionButton(
                isLiked: isRootLikedByCurrentUser,
                isBonusReaction: isRootBonusReactionByCurrentUser,
                count: rootReactionCount,
                bonusActiveColor: appSettings.primaryColor,
                minHeight: 30
            ) { bonusCount in
                Task {
                    await handleRootReactionTap(bonusCount: bonusCount)
                }
            }

            ShareLink(item: rootNoteShareLink) {
                Image(systemName: "paperplane")
                    .frame(minWidth: 34, minHeight: 30, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Share")
        }
        .font(.headline)
    }

    private var rootNoteShareLink: String {
        if let externalURL = NoteContentParser.njumpURL(for: viewModel.rootItem.displayEventID) {
            return externalURL.absoluteString
        }
        return "https://nlink.to/\(viewModel.rootItem.displayEventID)"
    }

    private var rootAvatar: some View {
        AvatarView(url: viewModel.rootItem.avatarURL, fallback: viewModel.rootItem.displayName)
        .overlay(alignment: .bottomTrailing) {
            if let rootFollowStatusIconName {
                ZStack {
                    Circle()
                        .fill(appSettings.themePalette.background)
                        .frame(width: 18, height: 18)

                    Image(systemName: rootFollowStatusIconName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
                .offset(x: 3, y: 3)
                .accessibilityHidden(true)
            }
        }
    }

    private var rootNoteOptionsButton: some View {
        Button {
            isShowingRootNoteOptionsSheet = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(appSettings.themePalette.mutedForeground)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Note options")
    }

    private var replyDockBar: some View {
        Button {
            presentReplyComposer(for: viewModel.rootItem.canonicalDisplayItem)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(appSettings.primaryColor.opacity(colorScheme == .dark ? 0.2 : 0.12))
                        .frame(width: 28, height: 28)

                    Image(systemName: "bubble.right.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(appSettings.primaryColor)
                }

                Text("Post your reply")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.4), lineWidth: 0.9)
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.08), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var repliesSection: some View {
        Group {
            if viewModel.isLoading && threadReplies.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 16)
            } else if threadReplies.isEmpty {
                VStack(spacing: 6) {
                    Text("No replies yet")
                        .font(.headline)
                    Text("Tap below to post the first reply.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            } else {
                ForEach(threadReplies) { reply in
                    FeedRowView(
                        item: reply,
                        reactionCount: reactionStats.reactionCount(for: reply.displayEventID),
                        isLikedByCurrentUser: reactionStats.isReactedByCurrentUser(
                            for: reply.displayEventID,
                            currentPubkey: auth.currentAccount?.pubkey
                        ),
                        commentCount: replyCountsByTarget[reply.displayEventID.lowercased()] ?? 0,
                        showReactions: appSettings.reactionsVisibleInFeeds,
                        avatarMenuActions: .init(
                            followLabel: followStore.isFollowing(reply.displayAuthorPubkey) ? "Unfollow" : "Follow",
                            onFollowToggle: {
                                followStore.toggleFollow(reply.displayAuthorPubkey)
                            },
                            onViewProfile: {
                                openProfile(pubkey: reply.displayAuthorPubkey)
                            }
                        ),
                        onHashtagTap: { hashtag in
                            openHashtagFeed(hashtag: hashtag)
                        },
                        onProfileTap: { pubkey in
                            openProfile(pubkey: pubkey)
                        },
                        onOpenThread: {
                            selectedThreadItem = reply.threadNavigationItem
                        },
                        onRepostActorTap: { pubkey in
                            openProfile(pubkey: pubkey)
                        },
                        onReferencedEventTap: { referencedItem in
                            selectedThreadItem = referencedItem.threadNavigationItem
                        },
                        onReplyTap: {
                            presentReplyComposer(for: reply.canonicalDisplayItem)
                        },
                        suppressReplyContextForDirectReplyTargetEventID: viewModel.rootItem.displayEventID
                    )
                    .id(replyAnchorID(for: reply.id))
                    .padding(.horizontal, 16)
                    .onAppear {
                        if appSettings.reactionsVisibleInFeeds {
                            reactionStats.prefetch(events: [reply.displayEvent], relayURLs: effectiveReadRelayURLs)
                        }
                    }

                    Divider()
                        .padding(.leading, 72)
                }
            }
        }
    }

    private var reactionsSection: some View {
        Group {
            if viewModel.isLoadingNoteActivity && noteActivityRows.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 16)
            } else if noteActivityRows.isEmpty {
                VStack(spacing: 6) {
                    Text("No reactions yet")
                        .font(.headline)
                    Text("Likes, reposts, and quote shares will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            } else {
                ForEach(noteActivityRows) { activity in
                    ActivityRowCell(item: activity)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                    Divider()
                        .padding(.leading, 56)
                }
            }
        }
    }

    private var threadDetailContentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowCapsuleTabBar(
                selection: $selectedContentTab,
                items: ThreadDetailContentTab.allCases,
                title: { $0.title }
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)

            switch selectedContentTab {
            case .replies:
                repliesSection

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
            case .reactions:
                reactionsSection

                if let errorMessage = viewModel.noteActivityErrorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    private var rootReactionCount: Int {
        reactionStats.reactionCount(for: viewModel.rootItem.displayEventID)
    }

    private var articleMetadata: NostrLongFormArticleMetadata? {
        viewModel.rootItem.displayEvent.longFormArticleMetadata
    }

    private var isRootLikedByCurrentUser: Bool {
        reactionStats.isReactedByCurrentUser(
            for: viewModel.rootItem.displayEventID,
            currentPubkey: auth.currentAccount?.pubkey
        )
    }

    private var isRootBonusReactionByCurrentUser: Bool {
        reactionStats.currentUserReaction(
            for: viewModel.rootItem.displayEventID,
            currentPubkey: auth.currentAccount?.pubkey
        )?.bonusCount ?? 0 > 0
    }

    private var isRootOwnedByCurrentAccount: Bool {
        guard let currentPubkey = auth.currentAccount?.pubkey else {
            return false
        }
        return currentPubkey.lowercased() == viewModel.rootItem.displayAuthorPubkey.lowercased()
    }

    private var rootFollowStatusIconName: String? {
        guard !isRootOwnedByCurrentAccount else { return nil }
        return followStore.isFollowing(viewModel.rootItem.displayAuthorPubkey)
            ? "checkmark.circle.fill"
            : "plus.circle.fill"
    }

    private var rootNip05Label: String? {
        guard let nip05 = viewModel.rootItem.displayProfile?.nip05?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !nip05.isEmpty else {
            return nil
        }
        return nip05
    }

    private var rootNoteTranslationText: String {
        viewModel.rootItem.displayEvent.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var rootCopyableNoteText: String {
        viewModel.rootItem.displayEvent.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var rootHasCopyableNoteText: Bool {
        !rootCopyableNoteText.isEmpty
    }

    private var rootCanTranslateNote: Bool {
        guard !rootNoteTranslationText.isEmpty else { return false }
        #if canImport(Translation)
        if #available(iOS 18.0, *) {
            return true
        }
        #endif
        return false
    }

    private func presentRootTranslation() {
        guard rootCanTranslateNote else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            isShowingRootTranslation = true
        }
    }

    private func handleRootMuteAuthor() {
        let wasMuted = muteStore.isMuted(viewModel.rootItem.displayAuthorPubkey)
        muteStore.toggleMute(viewModel.rootItem.displayAuthorPubkey)
        let isMuted = muteStore.isMuted(viewModel.rootItem.displayAuthorPubkey)

        if !wasMuted && isMuted {
            toastCenter.show("Muted \(viewModel.rootItem.displayName)")
        } else if wasMuted && !isMuted {
            toastCenter.show("Unmuted \(viewModel.rootItem.displayName)", style: .info)
        } else if let errorMessage = muteStore.lastPublishError,
                  !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            toastCenter.show(errorMessage, style: .error, duration: 2.8)
        }
    }

    private func presentRootReportFlow() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            isShowingRootReportSheet = true
        }
    }

    private func submitRootReport(type: NoteReportType, details: String) async throws {
        try await reportPublishService.publishReport(
            for: viewModel.rootItem.displayEvent,
            type: type,
            details: details,
            currentNsec: auth.currentNsec,
            writeRelayURLs: effectiveWriteRelayURLs
        )
        await MainActor.run {
            toastCenter.show("Report sent")
        }
    }

    @MainActor
    private func applyInitialReplyPresentationIfNeeded() async {
        guard initiallyFocusReplyComposer, !hasAppliedInitialReplyFocus else { return }
        hasAppliedInitialReplyFocus = true
        try? await Task.sleep(nanoseconds: 220_000_000)
        presentReplyComposer(for: viewModel.rootItem.canonicalDisplayItem)
    }

    @MainActor
    private func applyInitialReplyScrollIfNeeded() async {
        guard let initialReplyScrollTargetID, !initialReplyScrollTargetID.isEmpty else { return }
        guard !hasAppliedInitialReplyScroll else { return }
        hasAppliedInitialReplyScroll = true

        let scrollRetryDelays: [UInt64] = [
            80_000_000,
            180_000_000,
            320_000_000
        ]

        for delay in scrollRetryDelays {
            try? await Task.sleep(nanoseconds: delay)
            pendingReplyScrollTargetID = initialReplyScrollTargetID
        }
    }

    @MainActor
    private func scrollReplyIntoView(replyID: String, using scrollProxy: ScrollViewProxy) async {
        let targetID = replyAnchorID(for: replyID)
        let scrollRetryDelays: [UInt64] = [
            0,
            140_000_000,
            280_000_000
        ]

        for delay in scrollRetryDelays {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            withAnimation(.easeInOut(duration: 0.22)) {
                scrollProxy.scrollTo(targetID, anchor: .bottom)
            }
        }
    }

    @MainActor
    private func presentReplyComposer(for item: FeedItem) {
        activeReplyTarget = item
    }

    @MainActor
    private func handleRootReactionTap(bonusCount: Int = 0) async {
        let eventID = viewModel.rootItem.displayEventID
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
                for: viewModel.rootItem.displayEvent,
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

    private func openHashtagFeed(hashtag: String) {
        selectedHashtagRoute = HashtagRoute(
            hashtag: hashtag,
            seedItems: matchingHashtagSeedItems(
                hashtag: hashtag,
                from: [viewModel.rootItem] + threadReplies
            )
        )
    }

    private func replyAnchorID(for replyID: String) -> String {
        "thread-detail-reply-\(replyID.lowercased())"
    }

    private func openProfile(pubkey: String) {
        selectedProfileRoute = ProfileRoute(pubkey: pubkey)
    }

    private var hideNSFWEnabled: Bool {
        appSettings.hideNSFWContent
    }

    private var threadReplies: [FeedItem] {
        filteredReplies
    }

    private var replyCountsByTarget: [String: Int] {
        ReplyCountEstimator.counts(for: threadReplies)
    }

    private var filteredReplies: [FeedItem] {
        viewModel.replies.filter { item in
            if muteStore.shouldHideAny(item.moderationEvents) {
                return false
            }
            if hideNSFWEnabled && item.moderationEvents.contains(where: { $0.containsNSFWHashtag }) {
                return false
            }
            return true
        }
    }

    private var noteActivityRows: [ActivityRow] {
        viewModel.noteActivityRows.filter { !muteStore.isMuted($0.actorPubkey) }
    }

    private var nsfwHiddenCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.slash")
                .foregroundStyle(.secondary)
            Text("Content hidden by NSFW filter.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(appSettings.themePalette.secondaryBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(appSettings.themePalette.separator.opacity(0.35), lineWidth: 0.5)
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

    private var effectiveRelayURL: URL {
        if appSettings.slowConnectionMode {
            return AppSettingsStore.slowModeRelayURL
        }
        return viewModel.relayURL
    }

    private func configureStores() {
        relaySettings.configure(
            accountPubkey: auth.currentAccount?.pubkey,
            nsec: auth.currentNsec
        )
        followStore.configure(
            accountPubkey: auth.currentAccount?.pubkey,
            nsec: auth.currentNsec,
            readRelayURLs: effectiveReadRelayURLs,
            writeRelayURLs: effectiveWriteRelayURLs
        )
        muteStore.configure(
            accountPubkey: auth.currentAccount?.pubkey,
            nsec: auth.currentNsec,
            readRelayURLs: effectiveReadRelayURLs,
            writeRelayURLs: effectiveWriteRelayURLs
        )
    }

    private func performInitialLoad(isArticle: Bool) async {
        configureStores()

        if appSettings.reactionsVisibleInFeeds {
            reactionStats.prefetch(events: [viewModel.rootItem.displayEvent], relayURLs: effectiveReadRelayURLs)
        }

        if !isArticle, initiallyFocusReplyComposer {
            Task { @MainActor in
                await applyInitialReplyPresentationIfNeeded()
            }
        }

        await viewModel.loadIfNeeded()

        if !isArticle, initialReplyScrollTargetID != nil {
            Task { @MainActor in
                await applyInitialReplyScrollIfNeeded()
            }
        }
    }

    @MainActor
    private func publishRootRepost() async {
        guard !isPublishingRepost else { return }
        isPublishingRepost = true
        repostStatusMessage = nil
        repostStatusIsError = false
        defer { isPublishingRepost = false }

        do {
            let relayCount = try await reshareService.publishRepost(
                of: viewModel.rootItem.displayEvent,
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
}

private enum ThreadDetailContentTab: String, CaseIterable, Hashable {
    case replies
    case reactions

    var title: String {
        switch self {
        case .replies:
            return "Replies"
        case .reactions:
            return "Reactions"
        }
    }
}
