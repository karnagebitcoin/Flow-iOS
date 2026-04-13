import SwiftUI
import UIKit

struct ProfileView: View {
    private static let feedHorizontalInset: CGFloat = 14
    private static let bottomScrollClearance: CGFloat = 110

    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var toastCenter: AppToastCenter
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: ProfileViewModel

    @ObservedObject private var reactionStats = NoteReactionStatsService.shared
    @ObservedObject private var followStore = FollowStore.shared
    @ObservedObject private var muteStore = MuteStore.shared

    @State private var selectedThreadItem: FeedItem?
    @State private var selectedHashtagRoute: HashtagRoute?
    @State private var selectedProfileRoute: ProfileRoute?
    @State private var selectedFollowingRoute: FollowingListRoute?
    @State private var isShowingProfileEditor = false
    @State private var isShowingProfileQR = false
    @State private var isShowingAvatarViewer = false
    @State private var shouldAutoFocusReplyInThread = false

    private var profileHeaderContent: ProfileHeaderContent {
        ProfileHeaderContent(
            displayName: viewModel.displayName,
            handle: viewModel.handle,
            about: viewModel.about,
            avatarURL: viewModel.avatarURL,
            bannerURL: viewModel.bannerURL,
            websiteURL: viewModel.websiteURL,
            websiteDisplayText: viewModel.websiteURL.map(websiteDisplayText(for:)),
            lightningAddress: viewModel.lightningAddress,
            followsCurrentUser: viewModel.followsCurrentUser,
            followingCountText: "\(displayedFollowingCount) following",
            followStatusIconName: profileFollowStatusIconName,
            knownFollowers: isOwnProfile ? [] : viewModel.knownFollowers,
            actionMessage: actionMessage
        )
    }

    private var primaryActionDisabled: Bool {
        if isOwnProfile {
            return viewModel.isSavingProfile || auth.currentNsec == nil
        }
        return false
    }

    private var isOwnProfile: Bool {
        normalizePubkey(auth.currentAccount?.pubkey) == normalizePubkey(viewModel.pubkey)
    }

    private var actionMessage: String? {
        if let profileSaveError = viewModel.profileSaveError, !profileSaveError.isEmpty, !isShowingProfileEditor {
            return profileSaveError
        }
        if let muteError = muteStore.lastPublishError, !muteError.isEmpty {
            return muteError
        }
        if let followError = followStore.lastPublishError, !followError.isEmpty {
            return followError
        }
        return nil
    }

    private var displayedFollowingCount: Int {
        guard let currentPubkey = auth.currentAccount?.pubkey.lowercased(),
              currentPubkey == viewModel.pubkey.lowercased() else {
            return viewModel.followingCount
        }

        return followStore.followedPubkeys.count
    }

    private var isInitialProfileMetadataLoading: Bool {
        viewModel.profile == nil && !viewModel.hasCompletedInitialLoad
    }

    private var profileBannerButtonForeground: Color {
        appSettings.themePalette.profileActionStyle?.bannerForeground ?? appSettings.themePalette.foreground
    }

    private var profileBannerButtonBorder: Color {
        appSettings.themePalette.profileActionStyle?.bannerBorder ?? appSettings.themePalette.separator.opacity(0.88)
    }

    private var profileBannerButtonBackground: Color {
        appSettings.themePalette.profileActionStyle?.bannerBackground ?? appSettings.themePalette.modalBackground
    }

    private var profileFollowStatusIconName: String? {
        guard !isOwnProfile else { return nil }
        return followStore.isFollowing(viewModel.pubkey)
            ? "checkmark.circle.fill"
            : "plus.circle.fill"
    }

    private var effectiveReadRelayURLs: [URL] {
        appSettings.effectiveReadRelayURLs(from: viewModel.readRelayURLs)
    }

    private var effectiveWriteRelayURLs: [URL] {
        appSettings.effectiveWriteRelayURLs(from: viewModel.writeRelayURLs, fallbackReadRelayURLs: effectiveReadRelayURLs)
    }

    private var effectivePrimaryRelayURL: URL {
        effectiveReadRelayURLs.first ?? AppSettingsStore.slowModeRelayURL
    }

    init(
        pubkey: String,
        relayURL: URL,
        readRelayURLs: [URL]? = nil,
        writeRelayURLs: [URL]? = nil,
        service: NostrFeedService = NostrFeedService()
    ) {
        _viewModel = StateObject(
            wrappedValue: ProfileViewModel(
                pubkey: pubkey,
                relayURL: relayURL,
                readRelayURLs: readRelayURLs,
                writeRelayURLs: writeRelayURLs,
                service: service
            )
        )
    }

    var body: some View {
        let visibleItems = viewModel.visibleItems
        let visibleReplyCounts = ReplyCountEstimator.counts(for: visibleItems)

        ZStack {
            AppThemeBackgroundView()
                .ignoresSafeArea()

            List {
                Section {
                    ProfileHeaderSection(
                        isLoading: isInitialProfileMetadataLoading,
                        content: profileHeaderContent,
                        onFollowingTap: {
                            selectedFollowingRoute = FollowingListRoute(pubkey: viewModel.pubkey)
                        },
                        onProfileTap: { pubkey in
                            openProfile(pubkey: pubkey)
                        },
                        onHashtagTap: { hashtag in
                            openHashtagFeed(hashtag: hashtag)
                        },
                        onAvatarTap: {
                            isShowingAvatarViewer = true
                        },
                        backButton: {
                            profileBackButton
                        },
                        menuButton: {
                            profileMenuButton
                        },
                        actionRow: {
                            actionRow
                        }
                    )
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        FlowCapsuleTabBar(
                            selection: $viewModel.mode,
                            items: FeedMode.allCases,
                            title: { $0.title }
                        )
                    }
                    .padding(.vertical, 4)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                if viewModel.isLoading && visibleItems.isEmpty {
                    ForEach(0..<6, id: \.self) { _ in
                        ProfileFeedLoadingRow()
                            .listRowInsets(
                                EdgeInsets(
                                    top: 0,
                                    leading: Self.feedHorizontalInset,
                                    bottom: 0,
                                    trailing: Self.feedHorizontalInset
                                )
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                } else if visibleItems.isEmpty {
                    VStack(spacing: 8) {
                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(.body)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(appSettings.themePalette.secondaryForeground)
                        } else {
                            Text(viewModel.mode == .posts ? "No posts yet" : "No replies yet")
                                .font(.body)
                                .foregroundStyle(appSettings.themePalette.secondaryForeground)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowInsets(
                        EdgeInsets(
                            top: 0,
                            leading: Self.feedHorizontalInset,
                            bottom: 0,
                            trailing: Self.feedHorizontalInset
                        )
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(visibleItems) { item in
                        FeedRowView(
                            item: item,
                            reactionCount: reactionStats.reactionCount(for: item.displayEventID),
                            isLikedByCurrentUser: reactionStats.isReactedByCurrentUser(
                                for: item.displayEventID,
                                currentPubkey: auth.currentAccount?.pubkey
                            ),
                            commentCount: visibleReplyCounts[item.displayEventID.lowercased()] ?? 0,
                            showReactions: appSettings.reactionsVisibleInFeeds,
                            avatarMenuActions: .init(
                                followLabel: followStore.isFollowing(item.displayAuthorPubkey) ? "Unfollow" : "Follow",
                                onFollowToggle: {
                                    followStore.toggleFollow(item.displayAuthorPubkey)
                                },
                                onViewProfile: {
                                    openProfile(pubkey: item.displayAuthorPubkey)
                                }
                            ),
                            onHashtagTap: { hashtag in
                                openHashtagFeed(hashtag: hashtag)
                            },
                            onProfileTap: { pubkey in
                                openProfile(pubkey: pubkey)
                            },
                            onOpenThread: {
                                shouldAutoFocusReplyInThread = false
                                selectedThreadItem = item.threadNavigationItem
                            },
                            onRepostActorTap: { pubkey in
                                openProfile(pubkey: pubkey)
                            },
                            onReferencedEventTap: { referencedItem in
                                shouldAutoFocusReplyInThread = false
                                selectedThreadItem = referencedItem.threadNavigationItem
                            }
                        )
                        .listRowInsets(
                            EdgeInsets(
                                top: 0,
                                leading: Self.feedHorizontalInset,
                                bottom: 0,
                                trailing: Self.feedHorizontalInset
                            )
                        )
                        .listRowSeparator(.visible)
                        .listRowSeparatorTint(appSettings.themePalette.separator)
                        .listRowBackground(Color.clear)
                        .onAppear {
                            if appSettings.reactionsVisibleInFeeds {
                                reactionStats.prefetch(events: [item.displayEvent], relayURLs: effectiveReadRelayURLs)
                            }
                            Task {
                                await viewModel.loadMoreIfNeeded(currentItem: item)
                            }
                        }
                    }
                }

                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .listRowInsets(
                        EdgeInsets(
                            top: 0,
                            leading: Self.feedHorizontalInset,
                            bottom: 0,
                            trailing: Self.feedHorizontalInset
                        )
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                if !visibleItems.isEmpty || viewModel.isLoadingMore {
                    Color.clear
                        .frame(height: Self.bottomScrollClearance)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .refreshable {
                await viewModel.refresh()
                await viewModel.refreshFollowRelationship(currentAccountPubkey: auth.currentAccount?.pubkey)
                await viewModel.refreshKnownFollowers(
                    currentAccountPubkey: auth.currentAccount?.pubkey,
                    followedPubkeys: followStore.followedPubkeys
                )
                muteStore.refreshFromRelay()
            }
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            configureStores()
            await viewModel.loadIfNeeded()
            await viewModel.refreshFollowRelationship(currentAccountPubkey: auth.currentAccount?.pubkey)
            await viewModel.refreshKnownFollowers(
                currentAccountPubkey: auth.currentAccount?.pubkey,
                followedPubkeys: followStore.followedPubkeys
            )
        }
        .sheet(isPresented: $isShowingProfileEditor) {
            ProfileEditorSheet(
                initialFields: viewModel.editableFields,
                previewHandle: viewModel.handle,
                followingCount: viewModel.followingCount,
                isSaving: viewModel.isSavingProfile,
                errorMessage: viewModel.profileSaveError,
                onSave: { fields in
                    await viewModel.saveProfile(
                        fields: fields,
                        currentAccountPubkey: auth.currentAccount?.pubkey,
                        currentNsec: auth.currentNsec
                    )
                },
                onUploadAvatar: { data, mimeType, filename in
                    try await viewModel.uploadProfileImage(
                        data: data,
                        mimeType: mimeType,
                        filename: filename,
                        currentAccountPubkey: auth.currentAccount?.pubkey,
                        currentNsec: auth.currentNsec
                    )
                },
                onUploadBanner: { data, mimeType, filename in
                    try await viewModel.uploadProfileImage(
                        data: data,
                        mimeType: mimeType,
                        filename: filename,
                        currentAccountPubkey: auth.currentAccount?.pubkey,
                        currentNsec: auth.currentNsec
                    )
                }
            )
        }
        .navigationDestination(item: $selectedThreadItem) { item in
            ThreadDetailView(
                initialItem: item,
                relayURL: effectivePrimaryRelayURL,
                readRelayURLs: effectiveReadRelayURLs,
                initiallyFocusReplyComposer: shouldAutoFocusReplyInThread
            )
        }
        .navigationDestination(item: $selectedHashtagRoute) { route in
            HashtagFeedView(
                hashtag: route.normalizedHashtag,
                relayURL: effectivePrimaryRelayURL,
                readRelayURLs: effectiveReadRelayURLs,
                seedItems: route.seedItems
            )
        }
        .navigationDestination(item: $selectedProfileRoute) { route in
            ProfileView(
                pubkey: route.pubkey,
                relayURL: effectivePrimaryRelayURL,
                readRelayURLs: effectiveReadRelayURLs,
                writeRelayURLs: effectiveWriteRelayURLs
            )
        }
        .navigationDestination(item: $selectedFollowingRoute) { route in
            FollowingListView(
                pubkey: route.pubkey,
                readRelayURLs: effectiveReadRelayURLs
            )
        }
        .sheet(isPresented: $isShowingProfileQR) {
            ProfileQRCodeSheet(
                npub: viewModel.npub,
                displayName: viewModel.displayName,
                handle: viewModel.handle,
                avatarURL: viewModel.avatarURL,
                onOpenProfile: { pubkey in
                    openProfile(pubkey: pubkey)
                }
            )
        }
        .fullScreenCover(isPresented: $isShowingAvatarViewer) {
            if let avatarURL = viewModel.avatarURL {
                ProfileAvatarFullscreenViewer(
                    url: avatarURL,
                    title: viewModel.displayName
                )
            }
        }
        .onChange(of: auth.currentAccount?.pubkey) { _, _ in
            configureStores()
            refreshFollowRelationship()
            refreshKnownFollowers()
        }
        .onChange(of: auth.currentNsec) { _, _ in
            configureStores()
        }
        .onChange(of: relaySettings.readRelays) { _, _ in
            configureStores()
            refreshFollowRelationship()
            refreshKnownFollowers()
        }
        .onChange(of: relaySettings.writeRelays) { _, _ in
            configureStores()
            refreshFollowRelationship()
            refreshKnownFollowers()
        }
        .onChange(of: appSettings.slowConnectionMode) { _, _ in
            configureStores()
            Task {
                await viewModel.refresh()
                await viewModel.refreshFollowRelationship(currentAccountPubkey: auth.currentAccount?.pubkey)
                await viewModel.refreshKnownFollowers(
                    currentAccountPubkey: auth.currentAccount?.pubkey,
                    followedPubkeys: followStore.followedPubkeys
                )
            }
        }
        .onChange(of: followStore.followedPubkeys) { _, _ in
            refreshKnownFollowers()
        }
        .onChange(of: viewModel.mode) { _, _ in
            Task {
                await viewModel.prepareForSelectedModeIfNeeded()
            }
        }
    }

    private var profileBackButton: some View {
        Button {
            dismiss()
        } label: {
            ProfileBannerCircleIcon(
                systemImage: "chevron.left",
                foreground: profileBannerButtonForeground,
                border: profileBannerButtonBorder,
                background: profileBannerButtonBackground
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if isOwnProfile {
                qrActionButton
                editProfileActionButton
            } else {
                muteActionButton
                dmActionButton
                qrActionButton
                followActionButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var dmActionButton: some View {
        ProfileActionIconButton(
            systemImage: "bubble.left.and.bubble.right",
            isPrimary: false,
            isDisabled: true,
            accessibilityLabel: "Direct Message",
            action: {}
        )
    }

    private var qrActionButton: some View {
        ProfileActionIconButton(
            systemImage: "qrcode",
            isPrimary: false,
            isDisabled: false,
            accessibilityLabel: "QR Code",
            action: {
                isShowingProfileQR = true
            }
        )
    }

    private var muteActionButton: some View {
        ProfileActionIconButton(
            systemImage: muteStore.isMuted(viewModel.pubkey) ? "speaker.wave.2" : "speaker.slash",
            isPrimary: false,
            isDisabled: muteStore.isPublishing || auth.currentNsec == nil,
            accessibilityLabel: muteStore.isMuted(viewModel.pubkey) ? "Unmute" : "Mute",
            action: {
                muteStore.toggleMute(viewModel.pubkey)
            }
        )
    }

    private var editProfileActionButton: some View {
        ProfileActionIconButton(
            systemImage: "square.and.pencil",
            isPrimary: false,
            isDisabled: primaryActionDisabled,
            accessibilityLabel: "Edit profile",
            action: primaryAction
        )
    }

    private var followActionButton: some View {
        ProfileActionIconButton(
            systemImage: followStore.isFollowing(viewModel.pubkey) ? "person.crop.circle.badge.checkmark" : "plus",
            isPrimary: !followStore.isFollowing(viewModel.pubkey),
            isDisabled: false,
            accessibilityLabel: followStore.isFollowing(viewModel.pubkey) ? "Following" : "Follow",
            action: primaryAction
        )
    }

    private var profileMenuButton: some View {
        Menu {
            if isOwnProfile {
                Button {
                    isShowingProfileEditor = true
                } label: {
                    ProfileMenuOptionLabel(title: "Edit Profile", systemImage: "square.and.pencil")
                }
            } else {
                Button {
                    followStore.toggleFollow(viewModel.pubkey)
                } label: {
                    ProfileMenuOptionLabel(
                        title: followStore.isFollowing(viewModel.pubkey) ? "Unfollow" : "Follow",
                        systemImage: followStore.isFollowing(viewModel.pubkey)
                            ? "person.crop.circle.badge.minus"
                            : "person.crop.circle.badge.plus"
                    )
                }
            }

            Button {
                copyNpubToPasteboard()
            } label: {
                ProfileMenuOptionLabel(title: "Copy ID", systemImage: "doc.on.doc")
            }

            if let websiteURL = viewModel.websiteURL {
                Link(destination: websiteURL) {
                    ProfileMenuOptionLabel(title: "Open Website", systemImage: "safari")
                }
            }
        } label: {
            ProfileBannerCircleIcon(
                systemImage: "ellipsis",
                foreground: profileBannerButtonForeground,
                border: profileBannerButtonBorder,
                background: profileBannerButtonBackground
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile options")
    }

    private func primaryAction() {
        if isOwnProfile {
            isShowingProfileEditor = true
        } else {
            followStore.toggleFollow(viewModel.pubkey)
        }
    }

    private func copyNpubToPasteboard() {
        UIPasteboard.general.string = viewModel.npub
        toastCenter.show("Copied")
    }

    private func configureStores() {
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

    private func refreshFollowRelationship() {
        Task {
            await viewModel.refreshFollowRelationship(currentAccountPubkey: auth.currentAccount?.pubkey)
        }
    }

    private func refreshKnownFollowers() {
        Task {
            await viewModel.refreshKnownFollowers(
                currentAccountPubkey: auth.currentAccount?.pubkey,
                followedPubkeys: followStore.followedPubkeys
            )
        }
    }

    private func openHashtagFeed(hashtag: String) {
        selectedHashtagRoute = HashtagRoute(
            hashtag: hashtag,
            seedItems: matchingHashtagSeedItems(
                hashtag: hashtag,
                from: viewModel.visibleItems
            )
        )
    }

    private func openProfile(pubkey: String) {
        guard pubkey.lowercased() != viewModel.pubkey.lowercased() else { return }
        selectedProfileRoute = ProfileRoute(pubkey: pubkey)
    }

    private func websiteDisplayText(for url: URL) -> String {
        if let host = url.host(), !host.isEmpty {
            return host.lowercased()
        }
        return url.absoluteString
    }

    private func normalizePubkey(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
