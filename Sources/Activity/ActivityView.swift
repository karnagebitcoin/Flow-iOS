import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore

    @ObservedObject var viewModel: ActivityViewModel
    @State private var isShowingAuthSheet = false
    @State private var authSheetInitialTab: AuthSheetTab = .signIn
    @State private var isShowingSideMenu = false
    @State private var isShowingSettings = false
    @State private var isShowingNotificationSettings = false
    @State private var selectedThreadRoute: ActivityThreadRoute?
    @State private var selectedProfileRoute: ProfileRoute?
    @State private var topNavAvatarURL: URL?
    @State private var topNavAvatarImage: UIImage?
    @StateObject private var settingsSheetState = SettingsSheetState()
    @Binding private var isRootVisible: Bool

    init(
        viewModel: ActivityViewModel,
        isRootVisible: Binding<Bool> = .constant(true)
    ) {
        self.viewModel = viewModel
        _isRootVisible = isRootVisible
    }

    var body: some View {
        let _ = appSettings.activityNotificationPreferenceSignature

        NavigationStack {
            ZStack(alignment: .leading) {
                VStack(spacing: 0) {
                    topNavigationBar

                    List {
                        Section {
                            FlowCapsuleTabBar(
                                selection: $viewModel.selectedFilter,
                                items: ActivityFilter.allCases,
                                title: { $0.title }
                            )
                            .accessibilityLabel("Activity filter")
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                        if viewModel.isLoading && viewModel.items.isEmpty {
                            ForEach(0..<5, id: \.self) { _ in
                                loadingRow
                                    .listRowSeparator(.hidden)
                            }
                        } else if viewModel.visibleItems.isEmpty {
                            emptyStateRow
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(viewModel.visibleItems) { item in
                                ActivityRowCell(item: item)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedThreadRoute = threadRoute(for: item)
                                    }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        relaySettings.configure(
                            accountPubkey: auth.currentAccount?.pubkey,
                            nsec: auth.currentNsec
                        )
                        viewModel.configure(
                            currentUserPubkey: auth.currentAccount?.pubkey,
                            readRelayURLs: effectiveReadRelayURLs
                        )
                        await viewModel.refresh()
                    }
                }
                .disabled(isShowingSideMenu)

                if isShowingSideMenu {
                    sideMenuOverlay
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isShowingSideMenu)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                relaySettings.configure(
                    accountPubkey: auth.currentAccount?.pubkey,
                    nsec: auth.currentNsec
                )
                viewModel.configure(
                    currentUserPubkey: auth.currentAccount?.pubkey,
                    readRelayURLs: effectiveReadRelayURLs
                )
                await viewModel.loadIfNeeded()
            }
            .onChange(of: auth.currentAccount?.pubkey) { _, newValue in
                viewModel.configure(
                    currentUserPubkey: newValue,
                    readRelayURLs: effectiveReadRelayURLs
                )
            }
            .onChange(of: relaySettings.readRelays) { _, _ in
                viewModel.configure(
                    currentUserPubkey: auth.currentAccount?.pubkey,
                    readRelayURLs: effectiveReadRelayURLs
                )
            }
            .onChange(of: appSettings.slowConnectionMode) { _, _ in
                viewModel.configure(
                    currentUserPubkey: auth.currentAccount?.pubkey,
                    readRelayURLs: effectiveReadRelayURLs
                )
                Task {
                    await viewModel.refresh()
                }
            }
            .sheet(isPresented: $isShowingSettings, onDismiss: {
                settingsSheetState.reset()
            }) {
                SettingsView(sheetState: settingsSheetState)
                    .environmentObject(relaySettings)
            }
            .sheet(isPresented: $isShowingNotificationSettings) {
                notificationSettingsSheet
            }
            .sheet(isPresented: $isShowingAuthSheet) {
                AuthSheetView(initialTab: authSheetInitialTab)
                    .environmentObject(auth)
                    .environmentObject(appSettings)
                    .environmentObject(relaySettings)
            }
            .navigationDestination(item: $selectedThreadRoute) { route in
                ThreadDetailView(
                    initialItem: route.initialItem,
                    relayURL: viewModel.primaryRelayURL,
                    readRelayURLs: effectiveReadRelayURLs,
                    initialReplyScrollTargetID: route.initialReplyScrollTargetID
                )
            }
            .navigationDestination(item: $selectedProfileRoute) { route in
                ProfileView(
                    pubkey: route.pubkey,
                    relayURL: viewModel.primaryRelayURL,
                    readRelayURLs: effectiveReadRelayURLs,
                    writeRelayURLs: effectiveWriteRelayURLs
                )
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
            .onAppear {
                notifyRootVisibilityChanged()
            }
            .onChange(of: selectedThreadRoute) { _, _ in
                notifyRootVisibilityChanged()
            }
            .onChange(of: selectedProfileRoute) { _, _ in
                notifyRootVisibilityChanged()
            }
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

    private var topNavigationBar: some View {
        ZStack {
            Text("Activity")
                .font(.headline)
                .lineLimit(1)

            HStack {
                Button {
                    isShowingSideMenu = true
                } label: {
                    topNavAccountIcon
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open menu")

                Spacer()

                Button {
                    isShowingNotificationSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Notification settings")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
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
                .stroke(Color(.separator).opacity(0.35), lineWidth: 0.7)
        }
    }

    private var topNavAccountFallback: some View {
        ZStack {
            Circle()
                .fill(Color(.secondarySystemBackground))
            Image(systemName: "person.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
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

    private var notificationSettingsSheet: some View {
        NavigationStack {
            NotificationPreferencesView(navigationTitleText: "Notification Settings", titleDisplayMode: .inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            isShowingNotificationSettings = false
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemBackground))
    }

    private var emptyStateRow: some View {
        VStack(spacing: 6) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if viewModel.hasItemsHiddenByNotificationPreferences {
                Text("No activity matches your current notification settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No activity yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(.secondarySystemFill))
                .frame(width: 30, height: 30)

            Circle()
                .fill(Color(.secondarySystemFill))
                .frame(width: 20, height: 20)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.secondarySystemFill))
                .frame(height: 14)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.secondarySystemFill))
                .frame(width: 42, height: 12)
        }
        .padding(.vertical, 2)
        .redacted(reason: .placeholder)
    }

    private func openAuthSheet(tab: AuthSheetTab) {
        authSheetInitialTab = tab
        isShowingAuthSheet = true
    }

    private func closeSideMenu() {
        isShowingSideMenu = false
    }

    private var isShowingActivityRoot: Bool {
        selectedThreadRoute == nil && selectedProfileRoute == nil
    }

    private func notifyRootVisibilityChanged() {
        isRootVisible = isShowingActivityRoot
    }

    private func openProfile(pubkey: String) {
        selectedProfileRoute = ProfileRoute(pubkey: pubkey)
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

    private func threadRoute(for item: ActivityRow) -> ActivityThreadRoute? {
        switch item.action {
        case .mention, .reply, .quoteShare:
            if item.event.isReplyNote {
                let destinationEvent = item.target.event ?? item.event
                let shouldScrollToReply = destinationEvent.id.lowercased() != item.event.id.lowercased()
                return ActivityThreadRoute(
                    initialItem: FeedItem(
                        event: destinationEvent,
                        profile: profileForThreadDestination(event: destinationEvent, item: item)
                    ),
                    initialReplyScrollTargetID: shouldScrollToReply ? item.event.id.lowercased() : nil
                )
            }

            return ActivityThreadRoute(
                initialItem: FeedItem(event: item.event, profile: item.actorProfile),
                initialReplyScrollTargetID: nil
            )

        case .reaction:
            guard let destinationEvent = item.target.event else { return nil }
            return ActivityThreadRoute(
                initialItem: FeedItem(
                    event: destinationEvent,
                    profile: profileForThreadDestination(event: destinationEvent, item: item)
                ),
                initialReplyScrollTargetID: nil
            )

        case .reshare:
            let destinationEvent = item.target.event ?? item.event
            return ActivityThreadRoute(
                initialItem: FeedItem(
                    event: destinationEvent,
                    profile: profileForThreadDestination(event: destinationEvent, item: item)
                ),
                initialReplyScrollTargetID: nil
            )
        }
    }

    private func profileForThreadDestination(event: NostrEvent, item: ActivityRow) -> NostrProfile? {
        if event.id.lowercased() == item.event.id.lowercased() {
            return item.actorProfile
        }
        return item.target.profile
    }
}

struct ActivityRowCell: View {
    let item: ActivityRow

    var body: some View {
        HStack(spacing: 10) {
            ActivityAvatarView(url: item.actor.avatarURL, fallback: avatarFallbackCharacter)

            activityIndicator

            HStack(spacing: 8) {
                previewContent

                Spacer(minLength: 8)

                Text(RelativeTimestampFormatter.shortString(from: item.createdAtDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var activityIndicator: some View {
        switch item.action {
        case .mention:
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.14), in: Circle())
        case .reply:
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.14), in: Circle())
        case .reaction(let reaction):
            if let customEmojiURL = reaction.customEmojiImageURL {
                CachedAsyncImage(url: customEmojiURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        fallbackReactionSymbol(for: reaction)
                    }
                }
                .frame(width: 20, height: 20)
            } else {
                fallbackReactionSymbol(for: reaction)
            }
        case .reshare:
            Image(systemName: "arrow.2.squarepath")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 20, height: 20)
                .background(Color.green.opacity(0.14), in: Circle())
        case .quoteShare:
            Image(systemName: "quote.bubble.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 20, height: 20)
                .background(Color.orange.opacity(0.14), in: Circle())
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if let previewText {
            Text(previewText)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if showsImagePill {
            Text("Image")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(.tertiarySystemFill), in: Capsule())
        } else {
            EmptyView()
        }
    }

    private var avatarFallbackCharacter: String {
        String(item.actor.displayName.prefix(1)).uppercased()
    }

    private var previewText: String? {
        let sourceSnippet = normalizedPreviewText(
            from: item.event.activitySnippet(maxLength: 120),
            event: item.event
        )
        let targetSnippet = normalizedPreviewText(
            from: item.targetSnippet,
            event: item.target.event
        )

        switch item.action {
        case .mention, .reply, .quoteShare:
            if let sourceSnippet, !sourceSnippet.isEmpty {
                return sourceSnippet
            }
            return targetSnippet
        case .reaction:
            return targetSnippet
        case .reshare:
            return targetSnippet
        }
    }

    private var showsImagePill: Bool {
        switch item.action {
        case .mention, .reply, .quoteShare:
            if item.event.hasMedia {
                return true
            }
            return previewText == nil && (item.target.event?.hasMedia ?? false)
        case .reaction, .reshare:
            return previewText == nil && (item.target.event?.hasMedia ?? false)
        }
    }

    private func normalizedSnippet(from value: String?) -> String? {
        let normalized = (value ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizedPreviewText(from value: String?, event: NostrEvent?) -> String? {
        guard let normalized = normalizedSnippet(from: value) else { return nil }
        if let event, event.hasMedia, looksLikeStandaloneMediaLink(normalized) {
            return nil
        }
        return normalized
    }

    private func looksLikeStandaloneMediaLink(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let tokens = trimmed.split(whereSeparator: \.isWhitespace)
        guard tokens.count == 1 else { return false }
        guard let url = URL(string: String(tokens[0])), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        let path = url.path.lowercased()
        return Self.mediaPreviewExtensions.contains { path.hasSuffix($0) }
    }

    @ViewBuilder
    private func fallbackReactionSymbol(for reaction: ActivityReaction) -> some View {
        let value = reaction.displayValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value == "+" {
            Image(systemName: "heart.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.pink)
                .frame(width: 20, height: 20)
                .background(Color.pink.opacity(0.14), in: Circle())
        } else {
            Text(value)
                .font(.system(size: 16))
                .frame(width: 20, height: 20)
        }
    }

    private static let mediaPreviewExtensions: Set<String> = [
        ".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".svg",
        ".mp4", ".webm", ".ogg", ".mov", ".mp3", ".wav", ".flac",
        ".aac", ".m4a", ".opus", ".wma"
    ]
}

private struct ActivityAvatarView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    let url: URL?
    let fallback: String

    var body: some View {
        Group {
            if appSettings.textOnlyMode {
                fallbackAvatar
            } else if let url {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(Color(.separator), lineWidth: 0.5)
        }
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle().fill(Color(.secondarySystemFill))
            Text(String(fallback.prefix(1)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ActivityThreadRoute: Identifiable, Hashable {
    let initialItem: FeedItem
    let initialReplyScrollTargetID: String?

    var id: String {
        "\(initialItem.id.lowercased()):\(initialReplyScrollTargetID ?? "")"
    }
}
