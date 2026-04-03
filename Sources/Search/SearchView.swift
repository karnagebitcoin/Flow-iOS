import SwiftUI

struct SearchView: View {
    private static let feedHorizontalInset: CGFloat = 14
    private static let bottomScrollClearance: CGFloat = 110
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @ObservedObject private var reactionStats = NoteReactionStatsService.shared
    @ObservedObject private var followStore = FollowStore.shared
    @ObservedObject private var hashtagFavoritesStore = HashtagFavoritesStore.shared
    @ObservedObject private var muteStore = MuteStore.shared

    @StateObject private var viewModel: SearchViewModel

    @State private var selectedThreadItem: FeedItem?
    @State private var selectedHashtagRoute: HashtagRoute?
    @State private var selectedProfileRoute: ProfileRoute?
    @State private var shouldAutoFocusReplyInThread = false
    private let isActive: Bool

    init(viewModel: SearchViewModel? = nil, isActive: Bool = true) {
        let initialRelayURL = URL(
            string: RelaySettingsStore.defaultReadRelayURLs.first ?? "wss://relay.damus.io/"
        )!
        _viewModel = StateObject(
            wrappedValue: viewModel ?? SearchViewModel(relayURL: initialRelayURL)
        )
        self.isActive = isActive
    }

    var body: some View {
        let _ = muteStore.filterRevision
        let visibleItems = viewModel.visibleItems
        let visibleProfiles = viewModel.displayedProfiles
        let visibleReplyCounts = ReplyCountEstimator.counts(for: visibleItems)

        NavigationStack {
            ZStack {
                AppThemeBackgroundView()
                    .ignoresSafeArea()

                List {
                    if let suggestion = viewModel.suggestedContentSearch {
                        searchActionRow(suggestion)
                            .listRowInsets(
                                EdgeInsets(
                                    top: 8,
                                    leading: Self.feedHorizontalInset,
                                    bottom: 8,
                                    trailing: Self.feedHorizontalInset
                                )
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    if viewModel.isLoading && !viewModel.hasAnySearchResults {
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
                    } else {
                        if !visibleProfiles.isEmpty {
                            Section {
                                ForEach(visibleProfiles) { profile in
                                    profileResultRow(profile)
                                        .listRowInsets(
                                            EdgeInsets(
                                                top: 8,
                                                leading: Self.feedHorizontalInset,
                                                bottom: 8,
                                                trailing: Self.feedHorizontalInset
                                            )
                                        )
                                        .listRowSeparator(.visible)
                                        .listRowSeparatorTint(appSettings.themePalette.chromeBorder)
                                        .listRowBackground(Color.clear)
                                }
                            } header: {
                                Text(viewModel.isSearching ? "People" : "Suggestions")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(nil)
                            }
                        }

                        if let activeContentSearch = viewModel.activeContentSearch {
                            if visibleItems.isEmpty {
                                notesEmptyState(activeContentSearch)
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
                                Section {
                                    ForEach(visibleItems) { item in
                                        noteResultRow(item, visibleReplyCounts: visibleReplyCounts)
                                    }
                                } header: {
                                    Text(activeContentSearch.sectionTitle)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .textCase(nil)
                                }
                            }
                        } else if visibleProfiles.isEmpty {
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
                .safeAreaInset(edge: .top, spacing: 0) {
                    searchBar
                }
                .toolbar(.hidden, for: .navigationBar)
                .refreshable {
                    appSettings.configure(accountPubkey: auth.currentAccount?.pubkey)
                    configureStores()
                    updateSearchContext()
                    viewModel.updateReadRelayURLs(effectiveReadRelayURLs)
                    hashtagFavoritesStore.configure(accountPubkey: auth.currentAccount?.pubkey)
                    await viewModel.refresh()
                    MuteStore.shared.refreshFromRelay()
                }
                .task(id: isActive) {
                    guard isActive else { return }
                    appSettings.configure(accountPubkey: auth.currentAccount?.pubkey)
                    configureStores()
                    updateSearchContext()
                    viewModel.updateReadRelayURLs(effectiveReadRelayURLs)
                    hashtagFavoritesStore.configure(accountPubkey: auth.currentAccount?.pubkey)
                    await viewModel.loadIfNeeded()
                }
                .onChange(of: viewModel.searchText) { _, _ in
                    viewModel.handleSearchTextChanged()
                    if viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Task {
                            await viewModel.loadIfNeeded()
                        }
                    }
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
                .onChange(of: auth.currentAccount?.pubkey) { _, _ in
                    appSettings.configure(accountPubkey: auth.currentAccount?.pubkey)
                    configureStores()
                    updateSearchContext()
                    hashtagFavoritesStore.configure(accountPubkey: auth.currentAccount?.pubkey)
                    guard isActive else { return }
                    Task {
                        await viewModel.loadIfNeeded()
                    }
                }
                .onChange(of: auth.currentNsec) { _, _ in
                    configureStores()
                    updateSearchContext()
                }
                .onChange(of: followStore.followedPubkeys) { _, _ in
                    // Preserve the current suggestion list so an optimistic
                    // follow tap only flips the button state instead of
                    // rebuilding the entire screen.
                    updateSearchContext(invalidatePopularProfiles: false)
                }
                .onChange(of: relaySettings.readRelays) { _, _ in
                    viewModel.updateReadRelayURLs(effectiveReadRelayURLs)
                    guard isActive else { return }
                    Task {
                        await viewModel.loadIfNeeded()
                    }
                }
                .onChange(of: relaySettings.writeRelays) { _, _ in
                    configureStores()
                }
                .onChange(of: appSettings.slowConnectionMode) { _, _ in
                    configureStores()
                    viewModel.updateReadRelayURLs(effectiveReadRelayURLs)
                    guard isActive else { return }
                    Task {
                        await viewModel.refresh()
                    }
                }
            }
        }
    }

    private var searchBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(appSettings.themePalette.mutedForeground)

                TextField("Search notes, profiles, and hashtags", text: $viewModel.searchText)
                    .font(appSettings.appFont(.body))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        Task {
                            await viewModel.activateSuggestedContentSearch()
                        }
                    }

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(appSettings.themePalette.mutedForeground)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(searchFieldFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)

            Rectangle()
                .fill(appSettings.themePalette.chromeBorder)
                .frame(height: 0.7)
        }
        .background(searchBarBackground)
    }

    @ViewBuilder
    private var searchBarBackground: some View {
        if appSettings.activeTheme == .sakura {
            ZStack {
                appSettings.themePalette.chromeBackground.opacity(0.78)
                appSettings.primaryGradient.opacity(0.14)
            }
        } else if appSettings.activeTheme == .dracula {
            appSettings.themePalette.background
        } else {
            appSettings.themePalette.chromeBackground
        }
    }

    private var searchFieldFill: Color {
        if appSettings.activeTheme == .sakura {
            return Color.white.opacity(0.72)
        }
        return appSettings.themePalette.secondaryBackground
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button("Try Again") {
                    Task {
                        await viewModel.refresh()
                    }
                }
                .buttonStyle(.borderedProminent)
            } else if viewModel.isSearching {
                Text("No people match \"\(viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines))\".")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text("Popular people will appear here.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func notesEmptyState(_ activeContentSearch: SearchViewModel.SuggestedContentSearch) -> some View {
        VStack(spacing: 10) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text("No results for \(activeContentSearch.title.lowercased()).")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
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

    private func profileResultRow(_ profile: SearchViewModel.ProfileMatch) -> some View {
        let isCurrentUser = profile.pubkey.lowercased() == auth.currentAccount?.pubkey.lowercased()
        let isFollowing = followStore.isFollowing(profile.pubkey)

        return HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                AvatarView(url: profile.avatarURL, fallback: profile.displayName, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(profile.handle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                openProfile(pubkey: profile.pubkey)
            }

            Spacer(minLength: 0)

            if isCurrentUser {
                profileStatusBadge(
                    title: "You",
                    systemImage: "person.crop.circle.fill",
                    foreground: .primary,
                    background: appSettings.themePalette.secondaryGroupedBackground
                )
            } else {
                Button {
                    followStore.toggleFollow(profile.pubkey)
                } label: {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isFollowing ? appSettings.themePalette.mutedForeground : Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isFollowing ? AnyShapeStyle(appSettings.themePalette.secondaryGroupedBackground) : AnyShapeStyle(appSettings.primaryGradient))
                        )
                        .overlay {
                            if isFollowing {
                                Capsule(style: .continuous)
                                    .stroke(appSettings.themePalette.separator, lineWidth: 0.8)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func searchActionRow(_ suggestion: SearchViewModel.SuggestedContentSearch) -> some View {
        let isActive = viewModel.activeContentSearch == suggestion
        let isPinned = isPinnedFeedSuggestion(suggestion)

        return HStack(spacing: 10) {
            Button {
                Task {
                    await viewModel.activateSuggestedContentSearch()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: actionIcon(for: suggestion))
                        .font(.headline)
                        .foregroundStyle(isActive ? Color.white : appSettings.primaryColor)

                    Text(suggestion.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isActive ? Color.white : .primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isActive ? Color.white.opacity(0.9) : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                togglePinnedFeedSuggestion(suggestion)
            } label: {
                Image(systemName: isPinned ? "star.fill" : "star")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isActive ? Color.white : (isPinned ? appSettings.primaryColor : .secondary))
                    .frame(width: 34, height: 34)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                isActive
                                    ? Color.white.opacity(0.16)
                                    : appSettings.themePalette.tertiaryFill
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPinned ? "Unsave feed" : "Save feed")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isActive ? AnyShapeStyle(appSettings.primaryGradient) : AnyShapeStyle(appSettings.themePalette.secondaryBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func profileStatusBadge(
        title: String,
        systemImage: String,
        foreground: Color,
        background: Color
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background, in: Capsule(style: .continuous))
    }

    private func noteResultRow(_ item: FeedItem, visibleReplyCounts: [String: Int]) -> some View {
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
            Task {
                await viewModel.loadMoreIfNeeded(currentItem: item)
            }
        }
    }

    private func actionIcon(for suggestion: SearchViewModel.SuggestedContentSearch) -> String {
        switch suggestion.kind {
        case .notes:
            return "doc.text.magnifyingglass"
        case .hashtag:
            return "number"
        }
    }

    private func fallbackAvatar(for displayName: String) -> some View {
        ZStack {
            Circle()
                .fill(appSettings.themePalette.secondaryFill)
            Text(String(displayName.prefix(1)).uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
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
        MuteStore.shared.configure(
            accountPubkey: auth.currentAccount?.pubkey,
            nsec: auth.currentNsec,
            readRelayURLs: effectiveReadRelayURLs,
            writeRelayURLs: effectiveWriteRelayURLs
        )
    }

    private func updateSearchContext(invalidatePopularProfiles: Bool = true) {
        viewModel.updateSearchContext(
            currentAccountPubkey: auth.currentAccount?.pubkey,
            currentNsec: auth.currentNsec,
            followedPubkeys: Array(followStore.followedPubkeys),
            invalidatePopularProfiles: invalidatePopularProfiles
        )
    }

    private func openHashtagFeed(hashtag: String) {
        let route = HashtagRoute(
            hashtag: hashtag,
            seedItems: matchingHashtagSeedItems(
                hashtag: hashtag,
                from: viewModel.visibleItems
            )
        )
        selectedHashtagRoute = route
    }

    private func openProfile(pubkey: String) {
        selectedProfileRoute = ProfileRoute(pubkey: pubkey)
    }

    private func isPinnedFeedSuggestion(_ suggestion: SearchViewModel.SuggestedContentSearch) -> Bool {
        switch suggestion.kind {
        case .hashtag(let hashtag):
            return hashtagFavoritesStore.isFavorite(hashtag)
        case .notes(let query):
            return appSettings.customFeed(withID: savedSearchFeedID(for: query)) != nil
        }
    }

    private func togglePinnedFeedSuggestion(_ suggestion: SearchViewModel.SuggestedContentSearch) {
        switch suggestion.kind {
        case .hashtag(let hashtag):
            hashtagFavoritesStore.toggleFavorite(hashtag)
        case .notes(let query):
            let feedID = savedSearchFeedID(for: query)
            if appSettings.customFeed(withID: feedID) != nil {
                appSettings.removeCustomFeed(id: feedID)
            } else if let feed = savedSearchFeedDefinition(for: query) {
                try? appSettings.saveCustomFeed(feed)
            }
        }
    }

    private func savedSearchFeedDefinition(for query: String) -> CustomFeedDefinition? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }

        return CustomFeedDefinition(
            id: savedSearchFeedID(for: trimmedQuery),
            name: trimmedQuery,
            iconSystemName: "magnifyingglass",
            phrases: [trimmedQuery]
        )
    }

    private func savedSearchFeedID(for query: String) -> String {
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
        return "saved-search:\(normalized)"
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
}
