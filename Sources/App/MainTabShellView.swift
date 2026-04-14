import SwiftUI

struct MainTabShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    private enum Tab: String, CaseIterable, Hashable {
        case home
        case search
        case dms
        case activity

        var accessibilityLabel: String {
            switch self {
            case .home: return "Home"
            case .search: return "Search"
            case .dms: return "Halo Link"
            case .activity: return "Pulse"
            }
        }

        var symbolName: String {
            switch self {
            case .home: return "house"
            case .search: return "magnifyingglass"
            case .dms: return "bubble.left"
            case .activity: return "bell"
            }
        }
    }

    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @EnvironmentObject private var composeSheetCoordinator: AppComposeSheetCoordinator
    @ObservedObject private var muteStore = MuteStore.shared

    @State private var selectedTab: Tab = .home
    @State private var homeRootResetID = UUID()
    @State private var activityRootResetID = UUID()
    @State private var isShowingAuthSheet = false
    @State private var authSheetInitialTab: AuthSheetTab = .signIn
    @State private var isActivityRootVisible = true
    @State private var isDMRootVisible = true
    @State private var isHomeSideMenuPresented = false

    @StateObject private var homeViewModel = HomeFeedViewModel(
        relayURL: URL(string: RelaySettingsStore.defaultReadRelayURLs.first ?? "wss://relay.damus.io/")!
    )
    @StateObject private var searchViewModel = SearchViewModel(
        relayURL: URL(string: RelaySettingsStore.defaultReadRelayURLs.first ?? "wss://relay.damus.io/")!
    )
    @StateObject private var activityViewModel = ActivityViewModel()
    @StateObject private var liveReactsCoordinator = LiveReactsCoordinator()
    @StateObject private var liveReactsSubscriptionController = LiveReactsSubscriptionController()

    var body: some View {
        ZStack {
            AppThemeBackgroundView()
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                HomeFeedView(
                    viewModel: homeViewModel,
                    isShowingSideMenu: $isHomeSideMenuPresented
                )
                    .id(homeRootResetID)
                    .tag(Tab.home)
                    .toolbar(.hidden, for: .tabBar)

                SearchView(
                    viewModel: searchViewModel,
                    isActive: selectedTab == .search
                )
                    .tag(Tab.search)
                    .toolbar(.hidden, for: .tabBar)

                DMsView(isRootVisible: $isDMRootVisible)
                    .tag(Tab.dms)
                    .toolbar(.hidden, for: .tabBar)

                ActivityView(
                    viewModel: activityViewModel,
                    isRootVisible: $isActivityRootVisible,
                    isTabActive: selectedTab == .activity
                )
                    .id(activityRootResetID)
                    .tag(Tab.activity)
                    .toolbar(.hidden, for: .tabBar)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isBottomTabBarVisible {
                bottomTabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            GeometryReader { proxy in
                let horizontalPadding: CGFloat = 10
                let slotWidth = max((proxy.size.width - (horizontalPadding * 2)) / 5, 56)
                let bottomAnchor = proxy.safeAreaInsets.bottom + 50

                LiveReactsOverlayHost(coordinator: liveReactsCoordinator)
                    .frame(width: slotWidth * 1.15, height: 250, alignment: .bottom)
                    .offset(x: -(slotWidth * 0.04), y: -bottomAnchor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .allowsHitTesting(false)
        }
        .sheet(item: composeSheetDraftBinding, onDismiss: {
            composeSheetCoordinator.dismiss()
        }) { draft in
            ComposeNoteSheet(
                currentAccountPubkey: auth.currentAccount?.pubkey,
                currentNsec: auth.currentNsec,
                writeRelayURLs: effectiveWriteRelayURLs,
                initialText: draft.initialText,
                initialAdditionalTags: draft.initialAdditionalTags,
                initialUploadedAttachments: draft.initialUploadedAttachments,
                initialSharedAttachments: draft.initialSharedAttachments,
                initialSelectedMentions: draft.initialSelectedMentions,
                initialPollDraft: draft.initialPollDraft,
                replyTargetEvent: draft.replyTargetEvent,
                replyTargetDisplayNameHint: draft.replyTargetDisplayNameHint,
                replyTargetHandleHint: draft.replyTargetHandleHint,
                replyTargetAvatarURLHint: draft.replyTargetAvatarURLHint,
                quotedEvent: draft.quotedEvent,
                quotedDisplayNameHint: draft.quotedDisplayNameHint,
                quotedHandleHint: draft.quotedHandleHint,
                quotedAvatarURLHint: draft.quotedAvatarURLHint,
                savedDraftID: draft.savedDraftID,
                onPublished: {
                    Task {
                        switch selectedTab {
                        case .home:
                            await homeViewModel.refresh()
                        case .search:
                            await searchViewModel.refresh()
                        case .dms, .activity:
                            break
                        }
                    }
                }
            )
        }
        .sheet(isPresented: $isShowingAuthSheet) {
            AuthSheetView(
                initialTab: authSheetInitialTab,
                onSelectedTabChange: { authSheetInitialTab = $0 }
            )
                .environmentObject(auth)
                .environmentObject(appSettings)
                .environmentObject(relaySettings)
        }
        .task {
            relaySettings.configure(
                accountPubkey: auth.currentAccount?.pubkey,
                nsec: auth.currentNsec
            )
            configureMuteStore()
            configureActivityViewModel()
            await activityViewModel.sceneDidChange(isActive: scenePhase == .active)
            configureLiveReactsSubscription()
            syncActivityTabActiveState()
        }
        .onChange(of: auth.currentAccount?.pubkey) { _, _ in
            relaySettings.configure(
                accountPubkey: auth.currentAccount?.pubkey,
                nsec: auth.currentNsec
            )
            configureMuteStore()
            configureActivityViewModel()
            configureLiveReactsSubscription()
        }
        .onChange(of: auth.currentNsec) { _, _ in
            configureMuteStore()
        }
        .onChange(of: relaySettings.readRelays) { _, _ in
            configureMuteStore()
            configureActivityViewModel()
            configureLiveReactsSubscription()
        }
        .onChange(of: relaySettings.writeRelays) { _, _ in
            configureMuteStore()
        }
        .onChange(of: appSettings.slowConnectionMode) { _, _ in
            configureMuteStore()
            configureActivityViewModel()
            configureLiveReactsSubscription()
        }
        .onChange(of: appSettings.liveReactsEnabled) { _, _ in
            configureLiveReactsSubscription()
        }
        .onChange(of: appSettings.activityNotificationPreferenceSignature) { _, _ in
            activityViewModel.notificationPreferencesChanged()
        }
        .onChange(of: muteStore.filterRevision) { _, _ in
            activityViewModel.notificationPreferencesChanged()
        }
        .onChange(of: isActivityRootVisible) { _, _ in
            syncActivityTabActiveState()
        }
        .onChange(of: scenePhase) { _, _ in
            Task {
                await activityViewModel.sceneDidChange(isActive: scenePhase == .active)
            }
            configureLiveReactsSubscription()
        }
        .animation(.easeInOut(duration: 0.2), value: isHomeSideMenuPresented)
        .animation(.easeInOut(duration: 0.2), value: isDMRootVisible)
        .tint(appSettings.primaryColor)
        .statusBarHidden(false)
    }

    private var bottomTabBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(appSettings.themePalette.chromeBorder)
                .frame(height: 0.7)

            HStack(spacing: 0) {
                tabBarButton(for: .home)
                tabBarButton(for: .search)
                composeTabButton
                tabBarButton(for: .dms)
                tabBarButton(for: .activity)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .background {
            bottomTabBarBackground
                .ignoresSafeArea(edges: .bottom)
        }
    }

        @ViewBuilder
    private var bottomTabBarBackground: some View {
        if appSettings.activeTheme == .sakura {
            ZStack {
                appSettings.themePalette.navigationBackground

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.76),
                        Color(red: 1.0, green: 0.960, blue: 0.978).opacity(0.66)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else if appSettings.activeTheme == .gamer {
            appSettings.themePalette.background
        } else {
            appSettings.themePalette.navigationBackground
        }
    }

    private func tabBarButton(for tab: Tab) -> some View {
        let isHighlighted = isTabHighlighted(tab)

        return Button {
            handleTabSelection(tab)
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(
                        isHighlighted
                            ? appSettings.primaryColor
                            : appSettings.themePalette.iconMutedForeground
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .contentShape(Rectangle())

                if tab == .activity, activityViewModel.hasUnread, !isActivityListVisible {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .offset(x: -20, y: 8)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.accessibilityLabel)
        .accessibilityAddTraits(isHighlighted ? [.isSelected] : [])
    }

    private var composeTabButton: some View {
        Button {
            handleComposeTap()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(appSettings.primaryGradient, in: Circle())
                .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .offset(y: -10)
        .padding(.bottom, -10)
        .accessibilityLabel("Compose note")
    }

    private var effectiveWriteRelayURLs: [URL] {
        return appSettings.effectiveWriteRelayURLs(
            from: relaySettings.writeRelayURLs,
            fallbackReadRelayURLs: effectiveReadRelayURLs
        )
    }

    private var effectiveReadRelayURLs: [URL] {
        appSettings.effectiveReadRelayURLs(from: relaySettings.readRelayURLs)
    }

    private var isBottomTabBarVisible: Bool {
        !isHomeSideMenuPresented && (selectedTab != .dms || isDMRootVisible)
    }

    private var composeSheetDraftBinding: Binding<AppComposeSheetDraft?> {
        Binding(
            get: { composeSheetCoordinator.draft },
            set: { composeSheetCoordinator.draft = $0 }
        )
    }

    private func handleComposeTap() {
        guard auth.currentAccount != nil else {
            authSheetInitialTab = .signIn
            isShowingAuthSheet = true
            return
        }

        composeSheetCoordinator.presentNewNote()
    }

    private func handleTabSelection(_ tab: Tab) {
        let previousTab = selectedTab
        let wasActivityRootVisible = isActivityRootVisible

        if tab != .home {
            isHomeSideMenuPresented = false
        }

        if previousTab == .activity, tab != .activity {
            resetActivityTabToRoot()
        } else if tab == .activity, previousTab == .activity, !wasActivityRootVisible {
            resetActivityTabToRoot()
        }

        selectedTab = tab
        syncActivityTabActiveState()

        guard tab == .home else { return }

        homeRootResetID = UUID()
    }

    private func configureActivityViewModel() {
        activityViewModel.configure(
            currentUserPubkey: auth.currentAccount?.pubkey,
            readRelayURLs: effectiveReadRelayURLs
        )
    }

    private func configureLiveReactsSubscription() {
        liveReactsSubscriptionController.update(
            currentUserPubkey: auth.currentAccount?.pubkey,
            readRelayURLs: effectiveReadRelayURLs,
            isEnabled: appSettings.liveReactsEnabled,
            scenePhase: scenePhase,
            onReaction: { reaction in
                liveReactsCoordinator.emit(reaction)
            }
        )
    }

    private func configureMuteStore() {
        muteStore.configure(
            accountPubkey: auth.currentAccount?.pubkey,
            nsec: auth.currentNsec,
            readRelayURLs: effectiveReadRelayURLs,
            writeRelayURLs: effectiveWriteRelayURLs
        )
    }

    private var isActivityListVisible: Bool {
        selectedTab == .activity && isActivityRootVisible
    }

    private func isTabHighlighted(_ tab: Tab) -> Bool {
        switch tab {
        case .activity:
            return isActivityListVisible
        default:
            return selectedTab == tab
        }
    }

    private func resetActivityTabToRoot() {
        isActivityRootVisible = true
        activityRootResetID = UUID()
    }

    private func syncActivityTabActiveState() {
        activityViewModel.setActivityTabActive(isActivityListVisible)
    }
}
