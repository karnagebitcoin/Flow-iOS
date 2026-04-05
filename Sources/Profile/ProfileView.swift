import AVFoundation
import Photos
import SwiftUI
import UIKit

struct ProfileView: View {
    private static let feedHorizontalInset: CGFloat = 14
    private static let bottomScrollClearance: CGFloat = 110
    private static let profileBannerHeight: CGFloat = 220
    private static let profileAvatarSize: CGFloat = 104
    private static let profileContentHorizontalPadding: CGFloat = 16
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
    @State private var isSavingProfileImage = false

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
                    if isInitialProfileMetadataLoading {
                        profileHeaderSkeleton
                    } else {
                        profileHeader
                    }
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
                        loadingRow
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
                                .foregroundStyle(.secondary)
                        } else {
                            Text(viewModel.mode == .posts ? "No posts yet" : "No replies yet")
                                .font(.body)
                                .foregroundStyle(.secondary)
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
                muteStore.refreshFromRelay()
            }
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            configureStores()
            await viewModel.loadIfNeeded()
            await viewModel.refreshFollowRelationship(currentAccountPubkey: auth.currentAccount?.pubkey)
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
        }
        .onChange(of: auth.currentNsec) { _, _ in
            configureStores()
        }
        .onChange(of: relaySettings.readRelays) { _, _ in
            configureStores()
            refreshFollowRelationship()
        }
        .onChange(of: relaySettings.writeRelays) { _, _ in
            configureStores()
            refreshFollowRelationship()
        }
        .onChange(of: appSettings.slowConnectionMode) { _, _ in
            configureStores()
            Task {
                await viewModel.refresh()
                await viewModel.refreshFollowRelationship(currentAccountPubkey: auth.currentAccount?.pubkey)
            }
        }
        .onChange(of: viewModel.mode) { _, _ in
            Task {
                await viewModel.prepareForSelectedModeIfNeeded()
            }
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            profileBanner
                .overlay(alignment: .topLeading) {
                    profileBackButton
                        .padding(.leading, 16)
                        .padding(.top, 12)
                        .zIndex(3)
                }
                .overlay(alignment: .topTrailing) {
                    profileMenuButton
                        .padding(.trailing, 16)
                        .padding(.top, 12)
                        .zIndex(4)
                }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom, spacing: 16) {
                    profileAvatar

                    Spacer(minLength: 0)

                    actionRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                profileIdentityBlock

                if let about = viewModel.about, !about.isEmpty {
                    ProfileAboutTextView(
                        text: about,
                        onProfileTap: { pubkey in
                            openProfile(pubkey: pubkey)
                        },
                        onHashtagTap: { hashtag in
                            openHashtagFeed(hashtag: hashtag)
                        }
                    )
                }

                if hasVisibleInfoRows {
                    VStack(alignment: .leading, spacing: 10) {
                        if let nip05 = viewModel.nip05, !nip05.isEmpty {
                            infoRow(text: nip05, systemImage: "checkmark.seal")
                        }
                        if let websiteURL = viewModel.websiteURL {
                            Link(destination: websiteURL) {
                                infoRow(text: websiteDisplayText(for: websiteURL), systemImage: "link")
                            }
                            .buttonStyle(.plain)
                        }
                        if let lightning = viewModel.lightningAddress, !lightning.isEmpty {
                            infoRow(text: lightning, systemImage: "bolt.fill")
                        }
                    }
                }

                if let actionMessage = actionMessage, !actionMessage.isEmpty {
                    Text(actionMessage)
                        .font(appSettings.appFont(.footnote))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: profileContentWidth, alignment: .leading)
            .padding(.horizontal, Self.profileContentHorizontalPadding)
            .padding(.top, -(Self.profileAvatarSize / 2))
        }
        .frame(width: profileRowWidth, alignment: .leading)
        .padding(.bottom, 8)
    }

    private var profileHeaderSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(appSettings.themePalette.secondaryFill)
                .frame(height: Self.profileBannerHeight)
                .overlay(alignment: .topLeading) {
                    profileBackButton
                        .padding(.leading, 16)
                        .padding(.top, 12)
                        .zIndex(3)
                }
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(appSettings.themePalette.tertiaryFill)
                        .frame(width: 36, height: 36)
                        .padding(.trailing, 16)
                        .padding(.top, 12)
                        .zIndex(4)
                }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom, spacing: 16) {
                    Circle()
                        .fill(appSettings.themePalette.secondaryFill)
                        .frame(width: Self.profileAvatarSize, height: Self.profileAvatarSize)

                    Spacer(minLength: 0)

                    HStack(spacing: 10) {
                        Capsule()
                            .fill(appSettings.themePalette.secondaryFill)
                            .frame(width: 44, height: 40)
                        Capsule()
                            .fill(appSettings.themePalette.secondaryFill)
                            .frame(width: 44, height: 40)
                        Capsule()
                            .fill(appSettings.themePalette.secondaryFill)
                            .frame(width: 44, height: 40)
                        Capsule()
                            .fill(appSettings.themePalette.secondaryFill)
                            .frame(width: 44, height: 40)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(appSettings.themePalette.secondaryFill)
                        .frame(width: 210, height: 32)

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(appSettings.themePalette.secondaryFill)
                        .frame(width: 150, height: 20)

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(appSettings.themePalette.secondaryFill)
                        .frame(width: 120, height: 16)
                }

                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(appSettings.themePalette.secondaryFill)
                        .frame(height: 15)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(appSettings.themePalette.secondaryFill)
                        .frame(height: 15)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(appSettings.themePalette.secondaryFill)
                        .frame(width: 236, height: 15)
                }

                VStack(alignment: .leading, spacing: 10) {
                    skeletonInfoRow(width: 184)
                    skeletonInfoRow(width: 152)
                    skeletonInfoRow(width: 228)
                }
            }
            .frame(width: profileContentWidth, alignment: .leading)
            .padding(.horizontal, Self.profileContentHorizontalPadding)
            .padding(.top, -(Self.profileAvatarSize / 2))
        }
        .frame(width: profileRowWidth, alignment: .leading)
        .padding(.bottom, 8)
        .redacted(reason: .placeholder)
    }

    private var profileIdentityBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.displayName)
                .font(appSettings.appFont(size: 30, weight: .heavy))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(viewModel.handle)
                    .font(appSettings.appFont(.subheadline))
                    .foregroundStyle(appSettings.themePalette.mutedForeground)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let profileFollowStatusIconName {
                    Image(systemName: profileFollowStatusIconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }

            if viewModel.followsCurrentUser {
                Text("Follows you")
                    .font(appSettings.appFont(.footnote, weight: .medium))
                    .foregroundStyle(appSettings.themePalette.mutedForeground)
            }

            Button {
                selectedFollowingRoute = FollowingListRoute(pubkey: viewModel.pubkey)
            } label: {
                HStack(spacing: 4) {
                    Text("\(displayedFollowingCount) following")
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .font(appSettings.appFont(.footnote, weight: .semibold))
                .foregroundStyle(appSettings.themePalette.mutedForeground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View following list")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private var profileBackButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.headline.weight(.semibold))
                .foregroundStyle(profileBannerButtonForeground)
                .frame(width: 36, height: 36)
                .background(profileBannerButtonBackground())
                .overlay {
                    Circle()
                        .stroke(profileBannerButtonBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    private var profileBanner: some View {
        ZStack {
            profileBannerContent

            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.clear,
                    appSettings.themePalette.groupedBackground.opacity(0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.profileBannerHeight)
        .background(appSettings.themePalette.secondaryBackground)
        .clipped()
    }

    @ViewBuilder
    private var profileBannerContent: some View {
        if appSettings.textOnlyMode {
            profileBannerFallback
        } else if let bannerURL = viewModel.bannerURL {
            CachedAsyncImage(url: bannerURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    profileBannerFallback
                }
            }
        } else {
            profileBannerFallback
        }
    }

    private var profileBannerFallback: some View {
        ZStack {
            LinearGradient(
                colors: [
                    appSettings.themePalette.secondaryBackground,
                    appSettings.primaryColor.opacity(0.20),
                    appSettings.themePalette.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.42))
                .frame(width: 152, height: 152)
                .blur(radius: 18)
                .offset(x: 120, y: -40)

            Circle()
                .fill(appSettings.primaryColor.opacity(0.16))
                .frame(width: 188, height: 188)
                .blur(radius: 28)
                .offset(x: -132, y: 54)
        }
    }

    private var profileAvatar: some View {
        let isAvatarInteractive = !appSettings.textOnlyMode && viewModel.avatarURL != nil

        return Group {
            if isAvatarInteractive {
                Button {
                    isShowingAvatarViewer = true
                } label: {
                    profileAvatarContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View profile image")
                .contextMenu {
                    Button {
                        Task {
                            await saveProfileAvatar()
                        }
                    } label: {
                        Label("Save Image", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isSavingProfileImage)
                }
            } else {
                profileAvatarContent
            }
        }
    }

    private var profileAvatarContent: some View {
        Group {
            if appSettings.textOnlyMode {
                profileAvatarFallback
            } else if let avatarURL = viewModel.avatarURL {
                if isLoopingProfileVideoURL(avatarURL) {
                    ZStack {
                        profileAvatarFallback
                        ProfileLoopingVideoView(
                            url: avatarURL,
                            videoGravity: .resizeAspectFill
                        )
                    }
                } else {
                    CachedAsyncImage(url: avatarURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            profileAvatarFallback
                        }
                    }
                }
            } else {
                profileAvatarFallback
            }
        }
        .frame(width: Self.profileAvatarSize, height: Self.profileAvatarSize)
        .background(Circle().fill(appSettings.themePalette.background))
        .clipShape(Circle())
        .overlay {
            Circle().stroke(appSettings.themePalette.background, lineWidth: 4)
        }
        .overlay {
            Circle().stroke(appSettings.themePalette.separator.opacity(0.72), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 8)
    }

    private var profileAvatarFallback: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.9),
                            appSettings.themePalette.tertiaryFill
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(String(viewModel.displayName.prefix(1)).uppercased())
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
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
        iconActionButton(
            systemImage: "bubble.left.and.bubble.right",
            isPrimary: false,
            isDisabled: true,
            accessibilityLabel: "Direct Message",
            action: {}
        )
    }

    private var qrActionButton: some View {
        iconActionButton(
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
        iconActionButton(
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
        iconActionButton(
            systemImage: "square.and.pencil",
            isPrimary: false,
            isDisabled: primaryActionDisabled,
            accessibilityLabel: "Edit profile",
            action: primaryAction
        )
    }

    private var followActionButton: some View {
        iconActionButton(
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
                    profileMenuLabel("Edit Profile", systemImage: "square.and.pencil")
                }
            } else {
                Button {
                    followStore.toggleFollow(viewModel.pubkey)
                } label: {
                    profileMenuLabel(
                        followStore.isFollowing(viewModel.pubkey) ? "Unfollow" : "Follow",
                        systemImage: followStore.isFollowing(viewModel.pubkey)
                            ? "person.crop.circle.badge.minus"
                            : "person.crop.circle.badge.plus"
                    )
                }
            }
            Button {
                copyNpubToPasteboard()
            } label: {
                profileMenuLabel("Copy ID", systemImage: "doc.on.doc")
            }
            if let websiteURL = viewModel.websiteURL {
                Link(destination: websiteURL) {
                    profileMenuLabel("Open Website", systemImage: "safari")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline.weight(.semibold))
                .foregroundStyle(profileBannerButtonForeground)
                .frame(width: 36, height: 36)
                .background(profileBannerButtonBackground())
                .overlay {
                    Circle()
                        .stroke(profileBannerButtonBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile options")
    }

    private func profileMenuLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .font(appSettings.appFont(.body))
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(appSettings.primaryColor)
        }
    }

    private var loadingRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(appSettings.themePalette.secondaryFill)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(appSettings.themePalette.secondaryFill)
                    .frame(width: 150, height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(appSettings.themePalette.secondaryFill)
                    .frame(height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(appSettings.themePalette.secondaryFill)
                    .frame(width: 180, height: 14)
            }
        }
        .padding(.vertical, 10)
        .redacted(reason: .placeholder)
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

    @MainActor
    private func saveProfileAvatar() async {
        guard !isSavingProfileImage else { return }
        guard let avatarURL = viewModel.avatarURL else { return }
        isSavingProfileImage = true
        defer { isSavingProfileImage = false }

        let authorizationStatus = await ProfilePhotoLibrarySave.requestWriteAuthorizationIfNeeded()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            toastCenter.show("Photos access is needed to save.", style: .error, duration: 2.8)
            return
        }

        guard let image = await FlowImageCache.shared.image(for: avatarURL) else {
            toastCenter.show("Couldn't load that image right now.", style: .error, duration: 2.8)
            return
        }

        do {
            try await ProfilePhotoLibrarySave.save(image: image)
            toastCenter.show("Saved to Photos")
        } catch {
            toastCenter.show(
                (error as? LocalizedError)?.errorDescription ?? "Couldn't save that image right now.",
                style: .error,
                duration: 2.8
            )
        }
    }

    private func iconActionButton(
        systemImage: String,
        isPrimary: Bool,
        isDisabled: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        let style = appSettings.themePalette.profileActionStyle
        let disabledOpacity = isDisabled ? 0.48 : 1.0
        let foreground = isPrimary
            ? (style?.primaryForeground ?? Color.white)
            : (style?.foreground ?? (isDisabled ? appSettings.themePalette.mutedForeground : appSettings.themePalette.foreground))
        let background = isPrimary
            ? (style?.primaryBackground ?? Color.accentColor)
            : (style?.background ?? appSettings.themePalette.secondaryGroupedBackground)
        let borderColor = isPrimary ? style?.primaryBorder : style?.border

        return Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 18, height: 18)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .foregroundStyle(foreground.opacity(disabledOpacity))
                .background(
                    Capsule()
                        .fill(background.opacity(isDisabled && style != nil ? 0.72 : 1))
                )
                .overlay {
                    if let borderColor {
                        Capsule()
                            .stroke(borderColor.opacity(disabledOpacity), lineWidth: 0.8)
                    } else if !isPrimary {
                        Capsule()
                            .stroke(appSettings.themePalette.separator.opacity(0.7), lineWidth: 0.8)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private func infoRow(text: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(appSettings.themePalette.mutedForeground)
            Text(text)
                .font(appSettings.appFont(.footnote))
                .foregroundStyle(appSettings.themePalette.mutedForeground)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func skeletonInfoRow(width: CGFloat) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appSettings.themePalette.secondaryFill)
                .frame(width: 12, height: 12)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(appSettings.themePalette.secondaryFill)
                .frame(width: width, height: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var hasVisibleInfoRows: Bool {
        if let nip05 = viewModel.nip05, !nip05.isEmpty {
            return true
        }
        if viewModel.websiteURL != nil {
            return true
        }
        if let lightning = viewModel.lightningAddress, !lightning.isEmpty {
            return true
        }
        return false
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

    @ViewBuilder
    private func profileBannerButtonBackground() -> some View {
        if let style = appSettings.themePalette.profileActionStyle {
            Circle().fill(style.bannerBackground)
        } else {
            Circle().fill(appSettings.themePalette.modalBackground)
        }
    }

    private var profileRowWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    private var profileContentWidth: CGFloat {
        max(profileRowWidth - (Self.profileContentHorizontalPadding * 2), 0)
    }

    private var profileFollowStatusIconName: String? {
        guard !isOwnProfile else { return nil }
        return followStore.isFollowing(viewModel.pubkey)
            ? "checkmark.circle.fill"
            : "plus.circle.fill"
    }

    private func normalizePubkey(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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

    private func isLoopingProfileVideoURL(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "mp4", "mov", "m4v", "webm", "mkv":
            return true
        default:
            return false
        }
    }
}

private struct ProfileAvatarFullscreenViewer: View {
    let url: URL
    let title: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                if isLoopingProfileVideoURL(url) {
                    ProfileLoopingVideoView(
                        url: url,
                        videoGravity: .resizeAspect
                    )
                    .padding(16)
                } else {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .padding(16)
                        case .failure:
                            Image(systemName: "person.crop.circle.badge.exclamationmark")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.8))
                        case .empty:
                            ProgressView()
                                .tint(.white)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ThemedToolbarDoneButton {
                        dismiss()
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func isLoopingProfileVideoURL(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "mp4", "mov", "m4v", "webm", "mkv":
            return true
        default:
            return false
        }
    }
}

private struct ProfileLoopingVideoView: UIViewRepresentable {
    let url: URL
    let videoGravity: AVLayerVideoGravity

    final class Coordinator {
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
        var currentURL: URL?

        init() {
            player.isMuted = true
            player.actionAtItemEnd = .none
        }

        func configure(url: URL) {
            guard currentURL != url else {
                player.play()
                return
            }

            currentURL = url
            player.removeAllItems()
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            player.play()
        }

        func stop() {
            player.pause()
            looper = nil
            currentURL = nil
            player.removeAllItems()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ProfileLoopingVideoPlayerContainerView {
        let view = ProfileLoopingVideoPlayerContainerView()
        view.playerLayer.videoGravity = videoGravity
        view.playerLayer.player = context.coordinator.player
        context.coordinator.configure(url: url)
        return view
    }

    func updateUIView(_ uiView: ProfileLoopingVideoPlayerContainerView, context: Context) {
        uiView.playerLayer.videoGravity = videoGravity
        uiView.playerLayer.player = context.coordinator.player
        context.coordinator.configure(url: url)
    }

    static func dismantleUIView(_ uiView: ProfileLoopingVideoPlayerContainerView, coordinator: Coordinator) {
        uiView.playerLayer.player = nil
        coordinator.stop()
    }
}

private final class ProfileLoopingVideoPlayerContainerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

private enum ProfilePhotoLibrarySave {
    private enum SaveError: LocalizedError {
        case failed

        var errorDescription: String? {
            "Couldn't save that image right now."
        }
    }

    static func requestWriteAuthorizationIfNeeded() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch current {
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    continuation.resume(returning: status)
                }
            }
        default:
            return current
        }
    }

    static func save(image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: SaveError.failed)
                }
            }
        }
    }
}
