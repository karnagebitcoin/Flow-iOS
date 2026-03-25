import SwiftUI
import UIKit

struct ProfileView: View {
    private static let feedHorizontalInset: CGFloat = 14
    private static let bottomScrollClearance: CGFloat = 110
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
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
    @State private var transientActionMessage: String?
    @State private var transientActionMessageTask: Task<Void, Never>?

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
                    Picker("Feed", selection: $viewModel.mode) {
                        ForEach(FeedMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
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
            } else {
                ForEach(visibleItems) { item in
                    FeedRowView(
                        item: item,
                        reactionCount: reactionStats.reactionCount(for: item.displayEventID),
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
                        },
                        onReplyTap: {
                            shouldAutoFocusReplyInThread = true
                            selectedThreadItem = item.threadNavigationItem
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
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await viewModel.refresh()
            await viewModel.refreshFollowRelationship(currentAccountPubkey: auth.currentAccount?.pubkey)
            muteStore.refreshFromRelay()
        }
        .task {
            configureStores()
            await viewModel.loadIfNeeded()
            await viewModel.refreshFollowRelationship(currentAccountPubkey: auth.currentAccount?.pubkey)
        }
        .sheet(isPresented: $isShowingProfileEditor) {
            ProfileEditorSheet(
                initialFields: viewModel.editableFields,
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
                readRelayURLs: effectiveReadRelayURLs
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer()

                profileMenuButton
            }

            HStack(alignment: .top, spacing: 16) {
                profileAvatar

                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.displayName)
                        .font(.custom("SF Pro Display", size: 28).weight(.heavy))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(viewModel.handle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        selectedFollowingRoute = FollowingListRoute(pubkey: viewModel.pubkey)
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(displayedFollowingCount) following")
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View following list")
                }

                Spacer(minLength: 0)
            }

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

            actionRow

            if let actionMessage = actionMessage, !actionMessage.isEmpty {
                Text(actionMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var profileHeaderSkeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer()

                Circle()
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 36, height: 36)
            }

            HStack(alignment: .top, spacing: 16) {
                Circle()
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 88, height: 88)

                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.secondarySystemFill))
                        .frame(width: 210, height: 32)

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(.secondarySystemFill))
                        .frame(width: 150, height: 20)

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(.secondarySystemFill))
                        .frame(width: 120, height: 16)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(.secondarySystemFill))
                    .frame(height: 15)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(.secondarySystemFill))
                    .frame(height: 15)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 236, height: 15)
            }

            VStack(alignment: .leading, spacing: 10) {
                skeletonInfoRow(width: 184)
                skeletonInfoRow(width: 152)
                skeletonInfoRow(width: 228)
            }

            HStack(spacing: 10) {
                Capsule()
                    .fill(Color(.secondarySystemFill))
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
                Capsule()
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 46, height: 40)
                Capsule()
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 46, height: 40)
                Capsule()
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 110, height: 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .redacted(reason: .placeholder)
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
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        profileAvatarFallback
                    }
                }
            } else {
                profileAvatarFallback
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(Color(.separator).opacity(0.35), lineWidth: 0.8)
        }
    }

    private var profileAvatarFallback: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.9),
                            Color(.tertiarySystemFill)
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
            primaryActionButton
            if isOwnProfile {
                iconActionButton(
                    systemImage: "qrcode",
                    isPrimary: false,
                    isDisabled: false,
                    accessibilityLabel: "QR Code",
                    action: {
                        isShowingProfileQR = true
                    }
                )
            } else {
                iconActionButton(
                    systemImage: "bubble.left.and.bubble.right",
                    isPrimary: false,
                    isDisabled: true,
                    accessibilityLabel: "Direct Message",
                    action: {}
                )
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

            if !isOwnProfile {
                actionButton(
                    title: muteStore.isMuted(viewModel.pubkey) ? "Unmute" : "Mute",
                    systemImage: muteStore.isMuted(viewModel.pubkey) ? "speaker.wave.2" : "speaker.slash",
                    isPrimary: false,
                    isDisabled: muteStore.isPublishing || auth.currentNsec == nil,
                    action: {
                        muteStore.toggleMute(viewModel.pubkey)
                    }
                )
            }
        }
    }

    private var primaryActionButton: some View {
        actionButton(
            title: primaryActionTitle,
            systemImage: isOwnProfile ? "square.and.pencil" : nil,
            isPrimary: isOwnProfile || !followStore.isFollowing(viewModel.pubkey),
            isDisabled: primaryActionDisabled,
            expandsToFillRow: !isOwnProfile,
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
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(Color(.secondarySystemBackground), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile options")
    }

    private func profileMenuLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(appSettings.primaryColor)
        }
    }

    private var loadingRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color(.secondarySystemFill))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 150, height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.secondarySystemFill))
                    .frame(height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 180, height: 14)
            }
        }
        .padding(.vertical, 10)
        .redacted(reason: .placeholder)
    }

    private var primaryActionTitle: String {
        if isOwnProfile {
            return "Edit"
        }
        return followStore.isFollowing(viewModel.pubkey) ? "Following" : "Follow"
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
        if let transientActionMessage, !transientActionMessage.isEmpty {
            return transientActionMessage
        }
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
        showTransientActionMessage("Copied ID")
    }

    private func showTransientActionMessage(_ message: String) {
        transientActionMessageTask?.cancel()
        transientActionMessage = message

        transientActionMessageTask = Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if transientActionMessage == message {
                    transientActionMessage = nil
                }
            }
        }
    }

    private func actionButton(
        title: String,
        systemImage: String?,
        isPrimary: Bool,
        isDisabled: Bool,
        expandsToFillRow: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: expandsToFillRow ? .infinity : nil)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .foregroundStyle(isPrimary ? Color.white : (isDisabled ? Color.secondary : Color.primary))
            .background(
                Capsule()
                    .fill(isPrimary ? Color.accentColor : Color(.secondarySystemBackground))
            )
            .overlay {
                if !isPrimary {
                    Capsule()
                        .stroke(Color(.separator).opacity(0.35), lineWidth: 0.8)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func iconActionButton(
        systemImage: String,
        isPrimary: Bool,
        isDisabled: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 18, height: 18)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .foregroundStyle(isPrimary ? Color.white : (isDisabled ? Color.secondary : Color.primary))
                .background(
                    Capsule()
                        .fill(isPrimary ? Color.accentColor : Color(.secondarySystemBackground))
                )
                .overlay {
                    if !isPrimary {
                        Capsule()
                            .stroke(Color(.separator).opacity(0.35), lineWidth: 0.8)
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
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func skeletonInfoRow(width: CGFloat) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(.secondarySystemFill))
                .frame(width: 12, height: 12)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(.secondarySystemFill))
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
        selectedHashtagRoute = HashtagRoute(hashtag: hashtag)
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
