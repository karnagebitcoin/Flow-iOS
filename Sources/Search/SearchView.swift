import SwiftUI

struct SearchView: View {
    private static let feedHorizontalInset: CGFloat = 14
    private static let bottomScrollClearance: CGFloat = 110
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @ObservedObject private var reactionStats = NoteReactionStatsService.shared
    @ObservedObject private var followStore = FollowStore.shared
    @ObservedObject private var muteStore = MuteStore.shared

    @StateObject private var viewModel: SearchViewModel

    @State private var selectedThreadItem: FeedItem?
    @State private var selectedHashtagRoute: HashtagRoute?
    @State private var selectedProfileRoute: ProfileRoute?
    @State private var shouldAutoFocusReplyInThread = false

    init(viewModel: SearchViewModel? = nil) {
        let initialRelayURL = URL(
            string: RelaySettingsStore.defaultReadRelayURLs.first ?? "wss://relay.damus.io/"
        )!
        _viewModel = StateObject(
            wrappedValue: viewModel ?? SearchViewModel(relayURL: initialRelayURL)
        )
    }

    var body: some View {
        let _ = muteStore.filterRevision
        let visibleItems = viewModel.visibleItems
        let visibleReplyCounts = ReplyCountEstimator.counts(for: visibleItems)

        NavigationStack {
            List {
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
                } else if viewModel.isSearching && !viewModel.profileMatches.isEmpty {
                    Section {
                        ForEach(viewModel.profileMatches) { profile in
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
                        }
                    } header: {
                        Text("Profiles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }

                    if visibleItems.isEmpty {
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
                                onReplyTap: {
                                    shouldAutoFocusReplyInThread = true
                                    selectedThreadItem = item.threadNavigationItem
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
                } else if visibleItems.isEmpty {
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
                            onReplyTap: {
                                shouldAutoFocusReplyInThread = true
                                selectedThreadItem = item.threadNavigationItem
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
            .safeAreaInset(edge: .top, spacing: 0) {
                searchBar
            }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                configureStores()
                viewModel.updateReadRelayURLs(effectiveReadRelayURLs)
                await viewModel.refresh()
                MuteStore.shared.refreshFromRelay()
            }
            .task {
                configureStores()
                viewModel.updateReadRelayURLs(effectiveReadRelayURLs)
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
                configureStores()
            }
            .onChange(of: auth.currentNsec) { _, _ in
                configureStores()
            }
            .onChange(of: relaySettings.readRelays) { _, _ in
                viewModel.updateReadRelayURLs(effectiveReadRelayURLs)
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
                Task {
                    await viewModel.refresh()
                }
            }
        }
    }

    private var searchBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search notes, profiles, and hashtags", text: $viewModel.searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)

            Divider()
        }
        .background(Color(.systemBackground))
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
                Text("No results match \"\(viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines))\".")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text("Trending notes will appear here.")
                    .font(.body)
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

    private func profileResultRow(_ profile: SearchViewModel.ProfileMatch) -> some View {
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

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            openProfile(pubkey: profile.pubkey)
        }
    }

    private func fallbackAvatar(for displayName: String) -> some View {
        ZStack {
            Circle()
                .fill(Color(.secondarySystemFill))
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
