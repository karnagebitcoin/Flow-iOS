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
    @State private var isShowingComposeSheet = false
    @State private var isShowingAuthSheet = false
    @State private var authSheetInitialTab: AuthSheetTab = .signIn

    @StateObject private var homeViewModel = HomeFeedViewModel(
        relayURL: URL(string: RelaySettingsStore.defaultReadRelayURLs.first ?? "wss://relay.damus.io/")!
    )
    @StateObject private var searchViewModel = SearchViewModel(
        relayURL: URL(string: RelaySettingsStore.defaultReadRelayURLs.first ?? "wss://relay.damus.io/")!
    )

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

            ActivityView()
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
        Button {
            handleTabSelection(tab)
        } label: {
            Image(systemName: tab.symbolName)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(selectedTab == tab ? appSettings.primaryColor : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.accessibilityLabel)
        .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
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
        selectedTab = tab

        guard tab == .home else { return }

        homeRootResetID = UUID()
    }
}
