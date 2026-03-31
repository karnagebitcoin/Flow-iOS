import SwiftUI

struct HomeFeedView: View {
    private static let feedTopAnchorID = "home-feed-top-anchor"
    private static let feedScrollCoordinateSpace = "home-feed-scroll"
    private static let feedHorizontalInset: CGFloat = 14
    private static let bottomScrollClearance: CGFloat = 110
    private static let autoMergeTopThreshold: CGFloat = 56

    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @ObservedObject var viewModel: HomeFeedViewModel
    @ObservedObject private var reactionStats = NoteReactionStatsService.shared
    @ObservedObject private var followStore = FollowStore.shared
    @ObservedObject private var muteStore = MuteStore.shared
    @ObservedObject private var interestFeedStore = InterestFeedStore.shared
    @ObservedObject private var hashtagFavoritesStore = HashtagFavoritesStore.shared

    @State private var isShowingAuthSheet = false
    @State private var authSheetInitialTab: AuthSheetTab = .signIn
    @State private var isShowingSideMenu = false
    @State private var isShowingFeedSourcePicker = false
    @State private var isShowingFilterSheet = false
    @State private var isShowingSettings = false
    @State private var isTopNavigationVisible = true
    @StateObject private var settingsSheetState = SettingsSheetState()

    @State private var selectedThreadItem: FeedItem?
    @State private var selectedHashtagRoute: HashtagRoute?
    @State private var selectedProfileRoute: ProfileRoute?
    @State private var topNavAvatarURL: URL?
    @State private var topNavAvatarImage: UIImage?
    @State private var shouldAutoFocusReplyInThread = false
    @State private var feedTopOffset: CGFloat = 0

    var body: some View {
        let _ = muteStore.filterRevision
        let visibleItems = viewModel.visibleItems
        let visibleReplyCounts = ReplyCountEstimator.counts(for: visibleItems)

        NavigationStack {
            ZStack(alignment: .leading) {
                AppThemeBackgroundView()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if isTopNavigationVisible || isShowingSideMenu {
                        topNavigationBar
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    ScrollViewReader { scrollProxy in
                        List {
                            VStack(alignment: .leading, spacing: 8) {
                                FlowCapsuleTabBar(
                                    selection: $viewModel.mode,
                                    items: FeedMode.allCases,
                                    title: { $0.title }
                                )

                                if viewModel.mediaOnly {
                                    Label("Media-only filter enabled", systemImage: "line.3.horizontal.decrease.circle.fill")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 0)
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
                            .id(Self.feedTopAnchorID)
                            .background(feedTopOffsetReader)

                            if viewModel.isShowingLoadingPlaceholder {
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
                                if viewModel.shouldShowFilteredOutState {
                                    filteredOutState
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
                                    emptyState
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
                                        },
                                        onMuteConversation: { conversationID in
                                            viewModel.muteConversation(conversationID)
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
                                    .listRowSeparatorTint(appSettings.themePalette.chromeBorder)
                                    .listRowBackground(Color.clear)
                                    .onAppear {
                                        if appSettings.reactionsVisibleInFeeds {
                                            reactionStats.prefetch(events: [item.displayEvent], relayURLs: effectiveReadRelayURLs)
                                        }
                                        Task(priority: .utility) {
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
                        .coordinateSpace(name: Self.feedScrollCoordinateSpace)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                                .onChanged { value in
                                    handleFeedDragChange(value)
                                }
                        )
                        .overlay(alignment: .top) {
                            if viewModel.visibleBufferedNewItemsCount > 0, !isNearFeedTop {
                                newNotesPill {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        viewModel.showBufferedNewItems()
                                        scrollProxy.scrollTo(Self.feedTopAnchorID, anchor: .top)
                                    }
                                }
                                .padding(.top, isTopNavigationVisible ? 8 : 4)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .onPreferenceChange(HomeFeedTopOffsetPreferenceKey.self) { newValue in
                            feedTopOffset = newValue
                            autoShowBufferedItemsIfNeeded()
                        }
                        .onChange(of: viewModel.visibleBufferedNewItemsCount) { _, _ in
                            autoShowBufferedItemsIfNeeded()
                        }
                        .refreshable {
                            if viewModel.visibleBufferedNewItemsCount > 0 {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.showBufferedNewItems()
                                    scrollProxy.scrollTo(Self.feedTopAnchorID, anchor: .top)
                                }
                            } else {
                                await viewModel.refresh()
                            }
                        }
                        .task {
                            appSettings.configure(accountPubkey: auth.currentAccount?.pubkey)
                            relaySettings.configure(
                                accountPubkey: auth.currentAccount?.pubkey,
                                nsec: auth.currentNsec
                            )
                            viewModel.updateReadRelayURLs(effectiveReadRelayURLs)
                            interestFeedStore.configure(accountPubkey: auth.currentAccount?.pubkey)
                            viewModel.updateInterestHashtags(interestFeedStore.hashtags)
                            hashtagFavoritesStore.configure(accountPubkey: auth.currentAccount?.pubkey)
                            viewModel.updateFavoriteHashtags(hashtagFavoritesStore.favoriteHashtags)
                            viewModel.updateCustomFeeds(appSettings.customFeeds)

                            viewModel.updateCurrentUserPubkey(auth.currentAccount?.pubkey)
                            followStore.configure(
                                accountPubkey: auth.currentAccount?.pubkey,
                                nsec: auth.currentNsec,
                                readRelayURLs: effectiveReadRelayURLs,
                                writeRelayURLs: effectiveWriteRelayURLs
                            )
                            MuteStore.shared.configure(
                                accountPubkey: auth.currentAccount?.pubkey,
                                nsec: auth.currentNsec,
                                readRelayURLs: effectiveReadRelayURLs,
                                writeRelayURLs: effectiveWriteRelayURLs
                            )
                            await viewModel.loadIfNeeded()
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: isTopNavigationVisible)
                .disabled(isShowingSideMenu)

                if isShowingSideMenu {
                    sideMenuOverlay
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isShowingSideMenu)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingAuthSheet) {
                AuthSheetView(initialTab: authSheetInitialTab)
                    .environmentObject(auth)
                    .environmentObject(appSettings)
                    .environmentObject(relaySettings)
            }
            .sheet(isPresented: $isShowingFeedSourcePicker) {
                feedSourcePickerSheet
            }
            .sheet(isPresented: $isShowingFilterSheet) {
                filterSheet
            }
            .sheet(isPresented: $isShowingSettings, onDismiss: {
                settingsSheetState.reset()
            }) {
                SettingsView(sheetState: settingsSheetState)
                    .environmentObject(relaySettings)
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
            .onChange(of: auth.currentAccount?.pubkey) { _, newValue in
                appSettings.configure(accountPubkey: newValue)
                relaySettings.configure(
                    accountPubkey: newValue,
                    nsec: auth.currentNsec
                )
                viewModel.updateReadRelayURLs(effectiveReadRelayURLs)
                interestFeedStore.configure(accountPubkey: newValue)
                viewModel.updateInterestHashtags(interestFeedStore.hashtags)
                hashtagFavoritesStore.configure(accountPubkey: newValue)
                viewModel.updateFavoriteHashtags(hashtagFavoritesStore.favoriteHashtags)
                viewModel.updateCustomFeeds(appSettings.customFeeds)

                followStore.configure(
                    accountPubkey: newValue,
                    nsec: auth.currentNsec,
                    readRelayURLs: effectiveReadRelayURLs,
                    writeRelayURLs: effectiveWriteRelayURLs
                )
                MuteStore.shared.configure(
                    accountPubkey: newValue,
                    nsec: auth.currentNsec,
                    readRelayURLs: effectiveReadRelayURLs,
                    writeRelayURLs: effectiveWriteRelayURLs
                )
                viewModel.updateCurrentUserPubkey(newValue)
            }
            .onChange(of: auth.currentNsec) { _, newValue in
                relaySettings.configure(
                    accountPubkey: auth.currentAccount?.pubkey,
                    nsec: newValue
                )

                followStore.configure(
                    accountPubkey: auth.currentAccount?.pubkey,
                    nsec: newValue,
                    readRelayURLs: effectiveReadRelayURLs,
                    writeRelayURLs: effectiveWriteRelayURLs
                )
                MuteStore.shared.configure(
                    accountPubkey: auth.currentAccount?.pubkey,
                    nsec: newValue,
                    readRelayURLs: effectiveReadRelayURLs,
                    writeRelayURLs: effectiveWriteRelayURLs
                )
            }
            .onChange(of: relaySettings.readRelays) { _, _ in
                viewModel.updateReadRelayURLs(effectiveReadRelayURLs)
                followStore.configure(
                    accountPubkey: auth.currentAccount?.pubkey,
                    nsec: auth.currentNsec,
                    readRelayURLs: effectiveReadRelayURLs,
                    writeRelayURLs: effectiveWriteRelayURLs
                )
                MuteStore.shared.configure(
                    accountPubkey: auth.currentAccount?.pubkey,
                    nsec: auth.currentNsec,
                    readRelayURLs: effectiveReadRelayURLs,
                    writeRelayURLs: effectiveWriteRelayURLs
                )
            }
            .onChange(of: relaySettings.writeRelays) { _, _ in
                followStore.configure(
                    accountPubkey: auth.currentAccount?.pubkey,
                    nsec: auth.currentNsec,
                    readRelayURLs: effectiveReadRelayURLs,
                    writeRelayURLs: effectiveWriteRelayURLs
                )
                MuteStore.shared.configure(
                    accountPubkey: auth.currentAccount?.pubkey,
                    nsec: auth.currentNsec,
                    readRelayURLs: effectiveReadRelayURLs,
                    writeRelayURLs: effectiveWriteRelayURLs
                )
            }
            .onChange(of: appSettings.slowConnectionMode) { _, _ in
                viewModel.updateReadRelayURLs(effectiveReadRelayURLs)
                followStore.configure(
                    accountPubkey: auth.currentAccount?.pubkey,
                    nsec: auth.currentNsec,
                    readRelayURLs: effectiveReadRelayURLs,
                    writeRelayURLs: effectiveWriteRelayURLs
                )
                MuteStore.shared.configure(
                    accountPubkey: auth.currentAccount?.pubkey,
                    nsec: auth.currentNsec,
                    readRelayURLs: effectiveReadRelayURLs,
                    writeRelayURLs: effectiveWriteRelayURLs
                )
                Task {
                    await viewModel.refresh(silent: true)
                }
            }
            .onChange(of: appSettings.newsRelayURLs) { _, _ in
                guard viewModel.feedSource == .news else { return }
                Task {
                    await viewModel.refresh(silent: true)
                }
            }
            .onChange(of: appSettings.newsAuthorPubkeys) { _, _ in
                guard viewModel.feedSource == .news else { return }
                Task {
                    await viewModel.refresh(silent: true)
                }
            }
            .onChange(of: appSettings.newsHashtags) { _, _ in
                guard viewModel.feedSource == .news else { return }
                Task {
                    await viewModel.refresh(silent: true)
                }
            }
            .onChange(of: followStore.followedPubkeys) { _, _ in
                guard viewModel.feedSource == .following else { return }
                Task {
                    await viewModel.refresh(silent: true)
                }
            }
            .onChange(of: interestFeedStore.hashtags) { _, newValue in
                viewModel.updateInterestHashtags(newValue)
            }
            .onChange(of: hashtagFavoritesStore.favoriteHashtags) { _, newValue in
                viewModel.updateFavoriteHashtags(newValue)
            }
            .onChange(of: appSettings.customFeeds) { _, newValue in
                viewModel.updateCustomFeeds(newValue)
            }
            .task(id: topNavAvatarLookupID) {
                await refreshTopNavAvatar()
            }
            .onReceive(NotificationCenter.default.publisher(for: .profileMetadataUpdated)) { notification in
                guard let updatedPubkey = (notification.userInfo?["pubkey"] as? String)?.lowercased(),
                      let currentPubkey = auth.currentAccount?.pubkey.lowercased(),
                      updatedPubkey == currentPubkey else {
                    return
                }
                Task {
                    await refreshTopNavAvatar()
                }
            }
        }
    }

    private var topNavigationBar: some View {
        HStack(spacing: 12) {
            Button {
                isShowingSideMenu = true
            } label: {
                topNavAccountIcon
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open menu")

            Spacer()

            Button {
                isShowingFeedSourcePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: feedSourceIconName(for: viewModel.feedSource))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appSettings.primaryColor)
                    Text(feedSourceLabel(for: viewModel.feedSource))
                        .font(appSettings.appFont(.headline, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(topNavigationControlFill)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose feed source")

            Spacer()

            filterButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(topNavigationBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(appSettings.themePalette.chromeBorder)
                .frame(height: 0.7)
        }
    }

    @ViewBuilder
    private var topNavigationBackground: some View {
        if appSettings.activeTheme == .sakura {
            ZStack {
                appSettings.themePalette.chromeBackground

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.78),
                        Color(red: 1.0, green: 0.960, blue: 0.978).opacity(0.66)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else {
            appSettings.themePalette.chromeBackground
        }
    }

    private var topNavigationControlFill: Color {
        if appSettings.activeTheme == .sakura {
            return Color.white.opacity(0.88)
        }
        return appSettings.themePalette.secondaryBackground
    }

    private var sideMenuOverlay: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeSideMenu()
                    }

                HomeSlideoutMenuView(
                    onViewProfile: {
                        if let pubkey = auth.currentAccount?.pubkey {
                            openProfile(pubkey: pubkey)
                        }
                        closeSideMenu()
                    },
                    onOpenScannedProfile: { pubkey in
                        closeSideMenu()
                        openProfile(pubkey: pubkey)
                    },
                    onManageSettings: {
                        closeSideMenu()
                        isShowingSettings = true
                    },
                    onManageAccounts: {
                        closeSideMenu()
                        openAuthSheet(tab: .accounts)
                    },
                    onLogout: {
                        auth.logout()
                        closeSideMenu()
                    },
                    onClose: {
                        closeSideMenu()
                    }
                )
                .environmentObject(auth)
                .frame(width: min(320, geometry.size.width * 0.82))
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.move(edge: .leading))
            }
        }
    }

    private var filterButton: some View {
        Button {
            isShowingFilterSheet = true
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 46, height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Feed filters")
        .accessibilityAddTraits(viewModel.isUsingCustomFilters ? [.isSelected] : [])
    }

    private var filterGridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 120), spacing: 10),
            GridItem(.flexible(minimum: 120), spacing: 10)
        ]
    }

    private var filterSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    kindsFilterSection
                    contentFilterSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 44)
            }
            .navigationTitle("Feed Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isShowingFilterSheet = false
                    }
                }
            }
            .background(appSettings.themePalette.background)
        }
        .presentationDetents([.fraction(0.7), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(appSettings.themePalette.background)
    }

    private var kindsFilterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: filterGridColumns, spacing: 10) {
                ForEach(viewModel.kindFilterOptions) { option in
                    FilterKindTileView(
                        title: option.title,
                        iconName: filterIconName(for: option),
                        isSelected: viewModel.isKindGroupEnabled(option),
                        action: {
                            viewModel.toggleKindGroup(option)
                        }
                    )
                }
            }

            Button {
                viewModel.selectAllKinds()
            } label: {
                Label("Select All", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.footnote.weight(.medium))
            }
            .buttonStyle(.bordered)
        }
    }

    private var contentFilterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content")
                .font(.headline)

            let mediaOnlyEnabled = viewModel.mediaOnly
            Button {
                viewModel.setMediaOnly(!mediaOnlyEnabled)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: mediaOnlyEnabled ? "photo.on.rectangle.angled" : "rectangle")
                    Text("Only notes with media")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if mediaOnlyEnabled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(appSettings.primaryColor)
                    }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            mediaOnlyEnabled
                                ? appSettings.primaryColor.opacity(0.14)
                                : appSettings.themePalette.secondaryBackground
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func filterIconName(for option: FeedKindFilterOption) -> String {
        switch option.id {
        case "posts":
            return "text.bubble"
        case "reposts":
            return "arrow.triangle.2.circlepath"
        case "articles":
            return "doc.text"
        case "polls":
            return "chart.bar.xaxis"
        case "voice":
            return "waveform"
        case "photos":
            return "photo"
        case "videos":
            return "video"
        default:
            return "line.3.horizontal.decrease.circle"
        }
    }

    private var filteredOutState: some View {
        VStack(spacing: 10) {
            Text(viewModel.filteredOutMessage)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if viewModel.mediaOnlyFilteredOutAll {
                Button("Show posts without media") {
                    viewModel.disableMediaOnlyFilter()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else if viewModel.interestsFeedHasNoHashtags {
                Text("No interests selected yet")
                    .font(.headline)
                Text("Add topic hashtags in Settings > Feeds > Interests.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else if viewModel.followingFeedHasNoFollowings {
                Text("No followed accounts yet")
                    .font(.headline)
                Text("Follow people or switch to Network from the feed selector.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text("No posts yet")
                    .font(.headline)
                Text("Pull down to refresh and try these relays again.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
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

    private func openAuthSheet(tab: AuthSheetTab) {
        authSheetInitialTab = tab
        isShowingAuthSheet = true
    }

    private func closeSideMenu() {
        isShowingSideMenu = false
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
        selectedProfileRoute = ProfileRoute(pubkey: pubkey)
    }

    private func handleFeedDragChange(_ value: DragGesture.Value) {
        guard !isShowingSideMenu else { return }

        let verticalTranslation = value.translation.height
        if verticalTranslation <= -14 {
            setTopNavigationVisibility(false)
        } else if verticalTranslation >= 14 {
            setTopNavigationVisibility(true)
        }
    }

    private func setTopNavigationVisibility(_ isVisible: Bool) {
        guard isTopNavigationVisible != isVisible else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            isTopNavigationVisible = isVisible
        }
    }

    private func feedSourceLabel(for source: HomePrimaryFeedSource) -> String {
        switch source {
        case .network:
            return "Network"
        case .following:
            return "Following"
        case .trending:
            return "Trending"
        case .interests:
            return "Interests"
        case .news:
            return "News"
        case .custom(let feedID):
            return viewModel.customFeedDefinition(id: feedID)?.name ?? "Custom Feed"
        case .hashtag(let hashtag):
            return HomePrimaryFeedSource.normalizeHashtag(hashtag)
        }
    }

    private func feedSourceIconName(for source: HomePrimaryFeedSource) -> String {
        switch source {
        case .network:
            return "dot.radiowaves.left.and.right"
        case .following:
            return "person.2"
        case .trending:
            return "chart.line.uptrend.xyaxis"
        case .interests:
            return "sparkles"
        case .news:
            return "newspaper"
        case .custom(let feedID):
            return viewModel.customFeedDefinition(id: feedID)?.iconSystemName ?? CustomFeedIconCatalog.defaultIcon
        case .hashtag:
            return "number"
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

    private var effectivePrimaryRelayURL: URL {
        effectiveReadRelayURLs.first ?? AppSettingsStore.slowModeRelayURL
    }

    private var topNavAccountIcon: some View {
        Group {
            if appSettings.textOnlyMode {
                topNavAccountFallback
            } else if let topNavAvatarImage {
                Image(uiImage: topNavAvatarImage)
                    .resizable()
                    .scaledToFill()
            } else {
                topNavAccountFallback
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(appSettings.themePalette.separator.opacity(0.35), lineWidth: 0.7)
        }
    }

    private var topNavAccountFallback: some View {
        ZStack {
            Circle()
                .fill(topNavigationControlFill)
            Image(systemName: "person.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private var topNavAvatarLookupID: String {
        let accountID = auth.currentAccount?.id ?? "none"
        let relaySignature = effectiveReadRelayURLs
            .map { $0.absoluteString.lowercased() }
            .joined(separator: ",")
        return "\(accountID)|\(relaySignature)"
    }

    @MainActor
    private func refreshTopNavAvatar() async {
        guard let account = auth.currentAccount else {
            topNavAvatarURL = nil
            topNavAvatarImage = nil
            return
        }

        let normalizedPubkey = account.pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cacheResult = await ProfileCache.shared.resolve(pubkeys: [account.pubkey, normalizedPubkey])
        if let cachedProfile = cacheResult.hits[account.pubkey] ?? cacheResult.hits[normalizedPubkey],
           let cachedAvatarURL = preferredAvatarURL(from: cachedProfile) {
            await loadTopNavAvatarImage(from: cachedAvatarURL)
            return
        }

        let fetchedProfile = await NostrFeedService().fetchProfile(
            relayURLs: effectiveReadRelayURLs,
            pubkey: normalizedPubkey
        )
        if let avatarURL = fetchedProfile.flatMap(preferredAvatarURL(from:)) {
            await loadTopNavAvatarImage(from: avatarURL)
        } else {
            topNavAvatarURL = nil
            topNavAvatarImage = nil
        }
    }

    private func preferredAvatarURL(from profile: NostrProfile) -> URL? {
        guard let picture = profile.picture?.trimmingCharacters(in: .whitespacesAndNewlines),
              !picture.isEmpty,
              let url = URL(string: picture),
              url.scheme != nil else {
            return nil
        }
        return url
    }

    @MainActor
    private func loadTopNavAvatarImage(from url: URL) async {
        if topNavAvatarURL == url, topNavAvatarImage != nil {
            return
        }

        let previousURL = topNavAvatarURL
        topNavAvatarURL = url

        if let image = await FlowImageCache.shared.image(for: url) {
            guard topNavAvatarURL == url else { return }
            topNavAvatarImage = image
        } else if previousURL != url {
            topNavAvatarImage = nil
        }
    }

    private func newNotesPill(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                newNotesAvatarStack

                Text(newNotesPillLabel)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(appSettings.themePalette.separator.opacity(0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .shadow(color: Color.black.opacity(0.09), radius: 6, y: 2)
        .accessibilityLabel("Show latest notes")
    }

    private var newNotesAvatarStack: some View {
        let authors = recentBufferedAuthors

        return HStack(spacing: -10) {
            ForEach(Array(authors.enumerated()), id: \.element.id) { index, item in
                AvatarView(url: item.avatarURL, fallback: item.displayName, size: 24)
                    .padding(2)
                    .background(Circle().fill(appSettings.themePalette.chromeBackground))
                    .overlay {
                        Circle()
                            .stroke(appSettings.themePalette.chromeBackground, lineWidth: 1.2)
                    }
                    .zIndex(Double(authors.count - index))
            }
        }
        .padding(.trailing, authors.count > 1 ? 4 : 0)
    }

    private var newNotesPillLabel: String {
        let count = viewModel.visibleBufferedNewItemsCount
        return count == 1 ? "1 note" : "\(count) notes"
    }

    private var recentBufferedAuthors: [FeedItem] {
        var seenAuthors = Set<String>()
        var authors: [FeedItem] = []

        for item in viewModel.visibleBufferedNewItems {
            let authorKey = item.displayAuthorPubkey.lowercased()
            guard seenAuthors.insert(authorKey).inserted else { continue }
            authors.append(item)
            if authors.count == 3 {
                break
            }
        }

        return authors
    }

    private var isNearFeedTop: Bool {
        feedTopOffset >= -Self.autoMergeTopThreshold
    }

    private var feedTopOffsetReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: HomeFeedTopOffsetPreferenceKey.self,
                    value: proxy.frame(in: .named(Self.feedScrollCoordinateSpace)).minY
                )
        }
    }

    private func autoShowBufferedItemsIfNeeded() {
        guard isNearFeedTop else { return }
        guard viewModel.visibleBufferedNewItemsCount > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.showBufferedNewItems()
        }
    }

    private var feedSourcePickerSheet: some View {
        NavigationStack {
            List {
                ForEach(viewModel.feedSourceOptions, id: \.id) { source in
                    Button {
                        viewModel.selectFeedSource(source)
                        isShowingFeedSourcePicker = false
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: feedSourceIconName(for: source))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 18, alignment: .center)

                            Text(feedSourceLabel(for: source))
                                .foregroundStyle(.primary)

                            Spacer()

                            if viewModel.feedSource == source {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(appSettings.primaryColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Feed Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isShowingFeedSourcePicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct HomeFeedTopOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct FilterKindTileView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    let title: String
    let iconName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? appSettings.primaryColor : .secondary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(appSettings.primaryColor)
                    }
                }

                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isSelected
                            ? appSettings.primaryColor.opacity(0.14)
                            : appSettings.themePalette.secondaryBackground
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected
                            ? appSettings.primaryColor.opacity(0.75)
                            : appSettings.themePalette.separator.opacity(0.35),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
