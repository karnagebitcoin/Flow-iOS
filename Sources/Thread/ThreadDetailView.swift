import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ThreadDetailView: View {
    private static let replyComposerAnchorID = "thread-detail-reply-composer"
    private static let repliesBottomSpacerHeight: CGFloat = 96

    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: ThreadDetailViewModel
    @ObservedObject private var reactionStats = NoteReactionStatsService.shared
    @ObservedObject private var followStore = FollowStore.shared
    @ObservedObject private var muteStore = MuteStore.shared

    @State private var selectedThreadItem: FeedItem?
    @State private var selectedHashtagRoute: HashtagRoute?
    @State private var selectedProfileRoute: ProfileRoute?
    @State private var shouldAutoFocusReplyInNestedThread = false
    @State private var hasAppliedInitialReplyFocus = false
    @State private var hasAppliedInitialReplyScroll = false
    @State private var pendingReplyScrollTargetID: String?

    @State private var composerText = ""
    @FocusState private var isComposerFocused: Bool
    @StateObject private var speechTranscriber = ComposeSpeechTranscriber()
    @State private var selectedReplyMediaItems: [PhotosPickerItem] = []
    @State private var attachedReplyMedia: [ReplyComposerAttachment] = []
    @State private var isUploadingReplyMedia = false
    @State private var uploadingReplyMediaCount = 0
    @State private var composerAvatarURL: URL?
    @State private var composerAvatarFallback = "U"
    @State private var isReplyPublishing = false
    @State private var replyPublishErrorMessage: String?
    @State private var isShowingReshareSheet = false
    @State private var quoteDraft: ReshareQuoteDraft?
    @State private var isPublishingRepost = false
    @State private var repostStatusMessage: String?
    @State private var repostStatusIsError = false

    private let replyPublishService: ThreadReplyPublishService
    private let reactionPublishService: NoteReactionPublishService
    private let reshareService: ResharePublishService
    private let mediaUploadService: MediaUploadService
    private let profileService: NostrFeedService
    private let initialReplyScrollTargetID: String?
    private let initiallyFocusReplyComposer: Bool

    init(
        initialItem: FeedItem,
        relayURL: URL,
        readRelayURLs: [URL]? = nil,
        initialReplyScrollTargetID: String? = nil,
        initiallyFocusReplyComposer: Bool = false,
        service: NostrFeedService = NostrFeedService(),
        replyPublishService: ThreadReplyPublishService = ThreadReplyPublishService(),
        reactionPublishService: NoteReactionPublishService = NoteReactionPublishService(),
        reshareService: ResharePublishService = ResharePublishService(),
        mediaUploadService: MediaUploadService = .shared
    ) {
        _viewModel = StateObject(
            wrappedValue: ThreadDetailViewModel(
                rootItem: initialItem,
                relayURL: relayURL,
                readRelayURLs: readRelayURLs,
                service: service
            )
        )
        self.replyPublishService = replyPublishService
        self.reactionPublishService = reactionPublishService
        self.reshareService = reshareService
        self.mediaUploadService = mediaUploadService
        self.profileService = service
        self.initialReplyScrollTargetID = initialReplyScrollTargetID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.initiallyFocusReplyComposer = initiallyFocusReplyComposer
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    rootNoteCard(scrollProxy: scrollProxy)

                    replyComposerSection
                        .id(Self.replyComposerAnchorID)

                    Divider()
                        .padding(.leading, 16)

                    repliesSection

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }

                    Color.clear
                        .frame(height: Self.repliesBottomSpacerHeight)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("Thread")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                configureStores()
                if appSettings.reactionsVisibleInFeeds {
                    reactionStats.prefetch(events: [viewModel.rootItem.displayEvent], relayURLs: effectiveReadRelayURLs)
                }
                if initiallyFocusReplyComposer {
                    Task { @MainActor in
                        await applyInitialReplyFocusIfNeeded()
                    }
                }
                await viewModel.loadIfNeeded()
                await refreshComposerAvatar()
                if initialReplyScrollTargetID != nil {
                    Task { @MainActor in
                        await applyInitialReplyScrollIfNeeded()
                    }
                }
            }
            .onChange(of: isComposerFocused) { _, isFocused in
                guard isFocused else { return }
                Task { @MainActor in
                    await scrollReplyComposerIntoView(using: scrollProxy)
                }
            }
            .onChange(of: selectedReplyMediaItems) { _, newValue in
                guard !newValue.isEmpty else { return }
                let items = newValue
                selectedReplyMediaItems = []
                Task {
                    await handleReplyMediaSelection(items)
                }
            }
            .onChange(of: pendingReplyScrollTargetID) { _, replyID in
                guard let replyID else { return }
                Task { @MainActor in
                    await scrollReplyIntoView(replyID: replyID, using: scrollProxy)
                    pendingReplyScrollTargetID = nil
                }
            }
            .onChange(of: auth.currentAccount?.pubkey) { _, _ in
                configureStores()
                Task {
                    await refreshComposerAvatar()
                }
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
            .onDisappear {
                speechTranscriber.stopRecording()
            }
            .onReceive(NotificationCenter.default.publisher(for: .profileMetadataUpdated)) { notification in
                guard let updatedPubkey = (notification.userInfo?["pubkey"] as? String)?.lowercased(),
                      let currentPubkey = auth.currentAccount?.pubkey.lowercased(),
                      updatedPubkey == currentPubkey else {
                    return
                }
                Task {
                    await refreshComposerAvatar()
                }
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
                    readRelayURLs: effectiveReadRelayURLs,
                    initiallyFocusReplyComposer: shouldAutoFocusReplyInNestedThread
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
        }
    }

    private func rootNoteCard(scrollProxy: ScrollViewProxy) -> some View {
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

                        Text(RelativeTimestampFormatter.shortString(from: viewModel.rootItem.displayEvent.createdAtDate))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let rootNip05Label {
                        Text(rootNip05Label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                rootFollowButton
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
                        shouldAutoFocusReplyInNestedThread = false
                        selectedThreadItem = referencedItem.threadNavigationItem
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if appSettings.reactionsVisibleInFeeds {
                HStack(spacing: 14) {
                    ReactionButton(
                        isLiked: isRootLikedByCurrentUser,
                        count: rootReactionCount,
                        minHeight: 30
                    ) {
                        Task {
                            await handleRootReactionTap()
                        }
                    }

                    Button {
                        Task { @MainActor in
                            focusReplyComposer(using: scrollProxy)
                        }
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
                    .accessibilityLabel("Comment")

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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var replyComposerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.leading, 16)

            replyComposerBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
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
                        .fill(Color(.systemBackground))
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

    private var fallbackRootAvatar: some View {
        ZStack {
            Circle().fill(Color(.secondarySystemFill))
            Text(String(viewModel.rootItem.displayName.prefix(1)).uppercased())
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var rootFollowButton: some View {
        Group {
            if isRootOwnedByCurrentAccount {
                Text("You")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemFill))
                    .clipShape(Capsule())
            } else {
                let isFollowing = followStore.isFollowing(viewModel.rootItem.displayAuthorPubkey)

                Button(isFollowing ? "Following" : "Follow") {
                    followStore.toggleFollow(viewModel.rootItem.displayAuthorPubkey)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(
                    isFollowing
                        ? Color.secondary
                        : Color.white
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isFollowing
                        ? Color(.secondarySystemFill)
                        : Color.accentColor,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            isFollowing
                                ? Color(.separator).opacity(0.45)
                                : Color.accentColor.opacity(0.85),
                            lineWidth: 0.9
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var repliesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Replies")
                    .font(.headline)

                if !threadReplies.isEmpty {
                    Text("\(threadReplies.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.6)
                        }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

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
                    Text("Use the reply field below to join this thread.")
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
                            shouldAutoFocusReplyInNestedThread = false
                            selectedThreadItem = reply.threadNavigationItem
                        },
                        onRepostActorTap: { pubkey in
                            openProfile(pubkey: pubkey)
                        },
                        onReferencedEventTap: { referencedItem in
                            shouldAutoFocusReplyInNestedThread = false
                            selectedThreadItem = referencedItem.threadNavigationItem
                        },
                        onReplyTap: {
                            shouldAutoFocusReplyInNestedThread = true
                            selectedThreadItem = reply.threadNavigationItem
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

    private var replyComposerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                replyComposerAvatar
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 12) {
                    ZStack(alignment: .topLeading) {
                        if composerText.isEmpty {
                            Text("Reply to \(viewModel.rootItem.displayName)...")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }

                        TextEditor(text: $composerText)
                            .focused($isComposerFocused)
                            .frame(minHeight: 104)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .accessibilityLabel("Reply text")
                    }

                    if !attachedReplyMedia.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(attachedReplyMedia) { attachment in
                                    ZStack(alignment: .topTrailing) {
                                        CompactMediaAttachmentPreview(
                                            url: attachment.url,
                                            mimeType: attachment.mimeType,
                                            fileSizeBytes: attachment.fileSizeBytes,
                                            colorScheme: colorScheme
                                        )

                                        Button {
                                            removeReplyAttachment(attachment)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(.secondary)
                                                .padding(6)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Remove attachment")
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                        }
                    }

                    HStack(spacing: 12) {
                        PhotosPicker(
                            selection: $selectedReplyMediaItems,
                            selectionBehavior: .ordered,
                            matching: .any(of: [.images, .videos])
                        ) {
                            Group {
                                if isUploadingReplyMedia {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "photo")
                                        .font(.title3)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(isReplyPublishing || isUploadingReplyMedia)

                        Button {
                            // GIF picker flow is pending.
                        } label: {
                            Text("GIF")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                        Button {
                            Task {
                                await handleReplySpeechToggle()
                            }
                        } label: {
                            Group {
                                if speechTranscriber.isRecording {
                                    Image(systemName: "stop.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                } else if speechTranscriber.isTranscribing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 17, weight: .medium))
                                }
                            }
                            .foregroundStyle(speechTranscriber.isRecording ? Color.white : Color.secondary)
                            .frame(width: 32, height: 32)
                            .background(
                                speechTranscriber.isRecording ? Color.accentColor : Color(.tertiarySystemFill),
                                in: Circle()
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isReplyPublishing || isUploadingReplyMedia)

                        if speechTranscriber.isRecording {
                            Text(formatReplyVoiceDuration(milliseconds: speechTranscriber.elapsedMs))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Button {
                            submitReply()
                        } label: {
                            Group {
                                if isReplyPublishing {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(Color.white)
                                } else {
                                    Text("Reply")
                                }
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(canSubmitReply ? Color.white : Color.secondary)
                            .frame(minWidth: 42)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                canSubmitReply
                                    ? Color.accentColor
                                    : Color(.tertiarySystemFill),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmitReply || isReplyPublishing || isUploadingReplyMedia)
                    }

                    replyComposerStatusSection
                }
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var replyComposerStatusSection: some View {
        if isUploadingReplyMedia {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)

                Text("Uploading \(uploadingReplyMediaCount) attachment\(uploadingReplyMediaCount == 1 ? "" : "s")...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
        } else if speechTranscriber.isTranscribing {
            HStack(spacing: 10) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .foregroundStyle(.secondary)

                Text("Transcribing speech...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
        } else if let replyPublishErrorMessage, !replyPublishErrorMessage.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)

                Text(replyPublishErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                Color.red.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
    }

    private var rootReactionCount: Int {
        reactionStats.reactionCount(for: viewModel.rootItem.displayEventID)
    }

    private var isRootLikedByCurrentUser: Bool {
        reactionStats.isReactedByCurrentUser(
            for: viewModel.rootItem.displayEventID,
            currentPubkey: auth.currentAccount?.pubkey
        )
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

    private var trimmedComposerText: String {
        composerText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmitReply: Bool {
        (!trimmedComposerText.isEmpty || !attachedReplyMedia.isEmpty)
            && !speechTranscriber.isRecording
            && !speechTranscriber.isTranscribing
    }

    @MainActor
    private func applyInitialReplyFocusIfNeeded() async {
        guard initiallyFocusReplyComposer, !hasAppliedInitialReplyFocus else { return }
        hasAppliedInitialReplyFocus = true

        // Focus can race with navigation and ScrollView/TextEditor layout, so
        // retry a few times while the thread view is settling in.
        let focusRetryDelays: [UInt64] = [
            120_000_000,
            180_000_000,
            260_000_000
        ]

        for delay in focusRetryDelays {
            try? await Task.sleep(nanoseconds: delay)
            isComposerFocused = false
            await Task.yield()
            isComposerFocused = true
        }
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
    private func focusReplyComposer(using scrollProxy: ScrollViewProxy) {
        if isComposerFocused {
            Task { @MainActor in
                await scrollReplyComposerIntoView(using: scrollProxy)
            }
            return
        }

        isComposerFocused = true
    }

    @MainActor
    private func scrollReplyComposerIntoView(using scrollProxy: ScrollViewProxy) async {
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
                scrollProxy.scrollTo(Self.replyComposerAnchorID, anchor: .top)
            }
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
    private func handleRootReactionTap() async {
        let eventID = viewModel.rootItem.displayEventID
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
                for: viewModel.rootItem.displayEvent,
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

    private func submitReply() {
        guard !isReplyPublishing else { return }
        let draft = trimmedComposerText
        guard canSubmitReply else { return }

        isComposerFocused = false
        replyPublishErrorMessage = nil

        Task { @MainActor in
            isReplyPublishing = true
            defer {
                isReplyPublishing = false
            }

            do {
                let publishedReply = try await replyPublishService.publishReply(
                    content: draft,
                    replyingTo: viewModel.rootItem.displayEvent,
                    currentAccountPubkey: auth.currentAccount?.pubkey,
                    currentNsec: auth.currentNsec,
                    writeRelayURLs: effectiveWriteRelayURLs,
                    additionalTags: attachedReplyMedia.map(\.imetaTag)
                )

                composerText = ""
                attachedReplyMedia.removeAll()
                selectedReplyMediaItems.removeAll()
                viewModel.appendLocalReply(publishedReply)
                pendingReplyScrollTargetID = publishedReply.id
                if appSettings.reactionsVisibleInFeeds {
                    reactionStats.prefetch(events: [publishedReply.event], relayURLs: effectiveReadRelayURLs)
                }
            } catch {
                replyPublishErrorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't send reply right now."
            }
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

    private func handleReplySpeechToggle() async {
        replyPublishErrorMessage = nil

        let errorMessage = await speechTranscriber.toggleRecording { transcript in
            appendSpeechToReplyDraft(transcript)
        }

        if let errorMessage {
            replyPublishErrorMessage = errorMessage
        }
    }

    private func appendSpeechToReplyDraft(_ transcript: String) {
        let normalized = transcript
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        if composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            composerText = normalized
        } else {
            let needsSeparator = !(composerText.hasSuffix(" ") || composerText.hasSuffix("\n"))
            composerText += needsSeparator ? " \(normalized)" : normalized
        }
        isComposerFocused = true
    }

    private func formatReplyVoiceDuration(milliseconds: Int) -> String {
        let safeMilliseconds = max(milliseconds, 0)
        let totalSeconds = safeMilliseconds / 1_000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
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
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.35), lineWidth: 0.5)
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

    private var replyComposerAvatar: some View {
        Group {
            if appSettings.textOnlyMode {
                composerAvatarFallbackView
            } else if let composerAvatarURL {
                CachedAsyncImage(url: composerAvatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        composerAvatarFallbackView
                    }
                }
            } else {
                composerAvatarFallbackView
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(Color(.separator), lineWidth: 0.5)
        }
    }

    private var composerAvatarFallbackView: some View {
        ZStack {
            Circle().fill(Color(.secondarySystemFill))
            Text(String(composerAvatarFallback.prefix(1)).uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func refreshComposerAvatar() async {
        guard let currentPubkey = auth.currentAccount?.pubkey.lowercased() else {
            composerAvatarURL = nil
            composerAvatarFallback = "U"
            return
        }

        let cachedResult = await ProfileCache.shared.resolve(pubkeys: [currentPubkey])
        if let cachedProfile = cachedResult.hits[currentPubkey] {
            updateComposerAvatar(using: cachedProfile, fallbackPubkey: currentPubkey)
            if composerAvatarURL != nil {
                return
            }
        }

        if let fetchedProfile = await profileService.fetchProfile(relayURLs: effectiveReadRelayURLs, pubkey: currentPubkey) {
            updateComposerAvatar(using: fetchedProfile, fallbackPubkey: currentPubkey)
        } else if composerAvatarURL == nil {
            composerAvatarFallback = String(currentPubkey.prefix(1)).uppercased()
        }
    }

    @MainActor
    private func updateComposerAvatar(using profile: NostrProfile, fallbackPubkey: String) {
        if let picture = profile.picture?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: picture),
           !picture.isEmpty {
            composerAvatarURL = url
        } else {
            composerAvatarURL = nil
        }

        if let displayName = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !displayName.isEmpty {
            composerAvatarFallback = String(displayName.prefix(1)).uppercased()
        } else if let name = profile.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            composerAvatarFallback = String(name.prefix(1)).uppercased()
        } else {
            composerAvatarFallback = String(fallbackPubkey.prefix(1)).uppercased()
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
            repostStatusMessage = "Reposted to \(relayCount) relay\(relayCount == 1 ? "" : "s")."
            repostStatusIsError = false

            try? await Task.sleep(nanoseconds: 450_000_000)
            isShowingReshareSheet = false
        } catch {
            repostStatusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            repostStatusIsError = true
        }
    }

    @MainActor
    private func handleReplyMediaSelection(_ items: [PhotosPickerItem]) async {
        guard !isUploadingReplyMedia else { return }
        replyPublishErrorMessage = nil

        guard let normalizedNsec = auth.currentNsec?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalizedNsec.isEmpty else {
            replyPublishErrorMessage = "Sign in with a private key to upload media."
            return
        }

        isUploadingReplyMedia = true
        uploadingReplyMediaCount = items.count
        defer {
            isUploadingReplyMedia = false
            uploadingReplyMediaCount = 0
        }

        var failedUploads = 0
        var firstError: Error?

        for item in items {
            do {
                let attachment = try await uploadReplyAttachment(from: item, normalizedNsec: normalizedNsec)

                if !attachedReplyMedia.contains(where: { $0.url == attachment.url }) {
                    attachedReplyMedia.append(attachment)
                    removeUploadedMediaURLIfPresent(attachment.url)
                }
            } catch {
                failedUploads += 1
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if failedUploads > 0 {
            let successfulUploads = items.count - failedUploads
            let detailedMessage = (firstError as? LocalizedError)?.errorDescription ?? firstError?.localizedDescription
            if successfulUploads > 0 {
                if let detailedMessage, !detailedMessage.isEmpty {
                    replyPublishErrorMessage = "Uploaded \(successfulUploads) attachment\(successfulUploads == 1 ? "" : "s"), but \(failedUploads) failed: \(detailedMessage)"
                } else {
                    replyPublishErrorMessage = "Uploaded \(successfulUploads) attachment\(successfulUploads == 1 ? "" : "s"), but \(failedUploads) failed."
                }
            } else {
                replyPublishErrorMessage = detailedMessage ?? "Couldn't upload media right now."
            }
        }

        if failedUploads < items.count {
            isComposerFocused = true
        }
    }

    private func uploadReplyAttachment(from item: PhotosPickerItem, normalizedNsec: String) async throws -> ReplyComposerAttachment {
        let preparedMedia = try await MediaUploadPreparation.prepareUploadMedia(from: item)
        let filename = "reply-\(UUID().uuidString).\(preparedMedia.fileExtension)"

        let result = try await mediaUploadService.uploadMedia(
            data: preparedMedia.data,
            mimeType: preparedMedia.mimeType,
            filename: filename,
            nsec: normalizedNsec,
            provider: .blossom
        )

        return ReplyComposerAttachment(
            url: result.url,
            imetaTag: result.imetaTag,
            mimeType: preparedMedia.mimeType,
            fileSizeBytes: preparedMedia.data.count
        )
    }

    @MainActor
    private func removeUploadedMediaURLIfPresent(_ url: URL) {
        let urlString = url.absoluteString
        guard composerText.contains(urlString) else { return }

        composerText = composerText
            .replacingOccurrences(of: "\n\(urlString)", with: "")
            .replacingOccurrences(of: urlString, with: "")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removeReplyAttachment(_ attachment: ReplyComposerAttachment) {
        attachedReplyMedia.removeAll { $0.id == attachment.id }
    }

    private func defaultFileExtension(for mimeType: String) -> String {
        let normalized = mimeType.lowercased()
        if normalized.contains("jpeg") || normalized.contains("jpg") {
            return "jpg"
        }
        if normalized.contains("png") {
            return "png"
        }
        if normalized.contains("heic") {
            return "heic"
        }
        if normalized.contains("gif") {
            return "gif"
        }
        if normalized.contains("webp") {
            return "webp"
        }
        if normalized.contains("quicktime") || normalized.contains("mov") {
            return "mov"
        }
        if normalized.contains("mp4") {
            return "mp4"
        }
        if normalized.contains("mpeg") || normalized.contains("mp3") {
            return "mp3"
        }
        if normalized.contains("m4a") {
            return "m4a"
        }
        return "bin"
    }
}

private struct ReplyComposerAttachment: Identifiable {
    let id = UUID()
    let url: URL
    let imetaTag: [String]
    let mimeType: String
    let fileSizeBytes: Int?
}
