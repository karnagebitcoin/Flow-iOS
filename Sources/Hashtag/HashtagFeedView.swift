import SwiftUI

struct HashtagFeedView: View {
    private static let feedHorizontalInset: CGFloat = 14
    private static let bottomScrollClearance: CGFloat = 110
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @StateObject private var viewModel: HashtagFeedViewModel
    @ObservedObject private var reactionStats = NoteReactionStatsService.shared
    @ObservedObject private var followStore = FollowStore.shared
    @ObservedObject private var muteStore = MuteStore.shared
    @ObservedObject private var hashtagFavoritesStore = HashtagFavoritesStore.shared
    @State private var selectedThreadItem: FeedItem?
    @State private var selectedHashtagRoute: HashtagRoute?
    @State private var selectedProfileRoute: ProfileRoute?
    @State private var shouldAutoFocusReplyInThread = false

    init(
        hashtag: String,
        relayURL: URL,
        readRelayURLs: [URL]? = nil,
        seedItems: [FeedItem] = [],
        service: NostrFeedService = NostrFeedService()
    ) {
        _viewModel = StateObject(
            wrappedValue: HashtagFeedViewModel(
                hashtag: hashtag,
                relayURL: relayURL,
                readRelayURLs: readRelayURLs,
                seedItems: seedItems,
                service: service
            )
        )
    }

    var body: some View {
        let _ = muteStore.filterRevision
        let visibleItems = viewModel.visibleItems
        let visibleReplyCounts = ReplyCountEstimator.counts(for: visibleItems)

        List {
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
                        Text("No posts found for #\(viewModel.normalizedHashtag)")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
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
        .navigationTitle("#\(viewModel.normalizedHashtag)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    hashtagFavoritesStore.toggleFavorite(viewModel.normalizedHashtag)
                } label: {
                    Image(systemName: isCurrentHashtagFavorite ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 15, weight: .semibold))
                        .imageScale(.small)
                        .foregroundStyle(isCurrentHashtagFavorite ? Color.accentColor : Color.primary)
                }
                .controlSize(.small)
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isCurrentHashtagFavorite
                        ? "Remove hashtag from favorites"
                        : "Add hashtag to favorites"
                )
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            hashtagFavoritesStore.configure(accountPubkey: auth.currentAccount?.pubkey)
            await viewModel.loadIfNeeded()
        }
        .onChange(of: auth.currentAccount?.pubkey) { _, newValue in
            hashtagFavoritesStore.configure(accountPubkey: newValue)
        }
        .navigationDestination(item: $selectedThreadItem) { item in
            ThreadDetailView(
                initialItem: item,
                relayURL: effectiveRelayURL,
                readRelayURLs: effectiveReadRelayURLs,
                initiallyFocusReplyComposer: shouldAutoFocusReplyInThread
            )
        }
        .navigationDestination(item: $selectedHashtagRoute) { route in
            HashtagFeedView(
                hashtag: route.normalizedHashtag,
                relayURL: effectiveRelayURL,
                readRelayURLs: effectiveReadRelayURLs,
                seedItems: route.seedItems
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

    private func openHashtagFeed(hashtag: String) {
        let route = HashtagRoute(
            hashtag: hashtag,
            seedItems: matchingHashtagSeedItems(
                hashtag: hashtag,
                from: viewModel.visibleItems
            )
        )
        guard route.normalizedHashtag != viewModel.normalizedHashtag else { return }
        selectedHashtagRoute = route
    }

    private func openProfile(pubkey: String) {
        selectedProfileRoute = ProfileRoute(pubkey: pubkey)
    }

    private var effectiveRelayURL: URL {
        if appSettings.slowConnectionMode {
            return AppSettingsStore.slowModeRelayURL
        }
        return viewModel.relayURL
    }

    private var effectiveReadRelayURLs: [URL] {
        appSettings.effectiveReadRelayURLs(from: relaySettings.readRelayURLs)
    }

    private var effectiveWriteRelayURLs: [URL] {
        appSettings.effectiveWriteRelayURLs(from: relaySettings.writeRelayURLs, fallbackReadRelayURLs: [effectiveRelayURL])
    }

    private var isCurrentHashtagFavorite: Bool {
        hashtagFavoritesStore.isFavorite(viewModel.normalizedHashtag)
    }
}
