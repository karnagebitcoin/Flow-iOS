import SwiftUI

struct MainTabShellView: View {
    private enum Tab: String, CaseIterable, Hashable {
        case home
        case search
        case dms
        case activity

        var accessibilityLabel: String {
            switch self {
            case .home: return "Home"
            case .search: return "Search"
            case .dms: return "Messages"
            case .activity: return "Activity"
            }
        }

        var symbolName: String {
            switch self {
            case .home: return "house"
            case .search: return "magnifyingglass"
            case .dms: return "bubble.left.and.bubble.right"
            case .activity: return "bell"
            }
        }
    }

    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    
    @State private var selectedTab: Tab = .home
    @State private var homeRootResetID = UUID()
    @State private var activityRootResetID = UUID()
    @State private var isShowingComposeSheet = false
    @State private var isShowingAuthSheet = false
    @State private var authSheetInitialTab: AuthSheetTab = .signIn
    @State private var isActivityRootVisible = true

    @StateObject private var homeViewModel = HomeFeedViewModel(
        relayURL: URL(string: RelaySettingsStore.defaultReadRelayURLs.first ?? "wss://relay.damus.io/")!
    )
    @StateObject private var searchViewModel = SearchViewModel(
        relayURL: URL(string: RelaySettingsStore.defaultReadRelayURLs.first ?? "wss://relay.damus.io/")!
    )
    @StateObject private var activityViewModel = ActivityViewModel()

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeFeedView(viewModel: homeViewModel)
                .id(homeRootResetID)
                .tag(Tab.home)
                .toolbar(.hidden, for: .tabBar)

            SearchView(viewModel: searchViewModel)
                .tag(Tab.search)
                .toolbar(.hidden, for: .tabBar)

            DMsView()
                .tag(Tab.dms)
                .toolbar(.hidden, for: .tabBar)

            ActivityView(
                viewModel: activityViewModel,
                isRootVisible: $isActivityRootVisible
            )
                .id(activityRootResetID)
                .tag(Tab.activity)
                .toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomTabBar
        }
        .sheet(isPresented: $isShowingComposeSheet) {
            ComposeNoteSheet(
                currentAccountPubkey: auth.currentAccount?.pubkey,
                currentNsec: auth.currentNsec,
                writeRelayURLs: effectiveWriteRelayURLs,
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
            AuthSheetView(initialTab: authSheetInitialTab)
                .environmentObject(auth)
                .environmentObject(appSettings)
                .environmentObject(relaySettings)
        }
        .task {
            relaySettings.configure(
                accountPubkey: auth.currentAccount?.pubkey,
                nsec: auth.currentNsec
            )
            configureActivityViewModel()
            await activityViewModel.loadIfNeeded()
            syncActivityTabActiveState()
        }
        .onChange(of: auth.currentAccount?.pubkey) { _, _ in
            relaySettings.configure(
                accountPubkey: auth.currentAccount?.pubkey,
                nsec: auth.currentNsec
            )
            configureActivityViewModel()
        }
        .onChange(of: relaySettings.readRelays) { _, _ in
            configureActivityViewModel()
        }
        .onChange(of: appSettings.slowConnectionMode) { _, _ in
            configureActivityViewModel()
        }
        .onChange(of: appSettings.activityNotificationPreferenceSignature) { _, _ in
            activityViewModel.notificationPreferencesChanged()
        }
        .onChange(of: isActivityRootVisible) { _, _ in
            syncActivityTabActiveState()
        }
        .tint(appSettings.primaryColor)
    }

    private var bottomTabBar: some View {
        VStack(spacing: 0) {
            Divider()

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
            .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground))
    }

    private func tabBarButton(for tab: Tab) -> some View {
        let isHighlighted = isTabHighlighted(tab)

        return Button {
            handleTabSelection(tab)
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(isHighlighted ? appSettings.primaryColor : .secondary)
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
                .background(appSettings.primaryColor, in: Circle())
                .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .offset(y: -10)
        .padding(.bottom, -10)
        .accessibilityLabel("Compose note")
    }

    private var effectiveWriteRelayURLs: [URL] {
        let readRelayURLs = appSettings.effectiveReadRelayURLs(from: relaySettings.readRelayURLs)
        return appSettings.effectiveWriteRelayURLs(
            from: relaySettings.writeRelayURLs,
            fallbackReadRelayURLs: readRelayURLs
        )
    }

    private func handleComposeTap() {
        guard auth.currentAccount != nil else {
            authSheetInitialTab = .signIn
            isShowingAuthSheet = true
            return
        }

        isShowingComposeSheet = true
    }

    private func handleTabSelection(_ tab: Tab) {
        let previousTab = selectedTab
        let wasActivityRootVisible = isActivityRootVisible

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
            readRelayURLs: appSettings.effectiveReadRelayURLs(from: relaySettings.readRelayURLs)
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
