import SwiftUI

struct DMsView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @ObservedObject private var followStore = FollowStore.shared

    @StateObject private var store = HaloLinkStore()
    @State private var activeTab: HaloLinkInboxTab = .conversations
    @State private var navigationPath: [HaloLinkThreadRoute] = []
    @State private var isShowingNewConversationSheet = false
    @Binding private var isRootVisible: Bool

    init(isRootVisible: Binding<Bool> = .constant(true)) {
        _isRootVisible = isRootVisible
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                appSettings.themePalette.background
                    .ignoresSafeArea()

                if auth.currentAccount == nil {
                    signedOutState
                } else if auth.currentNsec == nil {
                    noSignerState
                } else {
                    mainContent
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: HaloLinkThreadRoute.self) { route in
                HaloLinkThreadView(route: route, store: store)
                    .environmentObject(appSettings)
                    .environmentObject(auth)
            }
        }
        .sheet(isPresented: $isShowingNewConversationSheet) {
            HaloLinkNewConversationSheet(store: store) { route in
                openThread(route)
            }
            .environmentObject(appSettings)
        }
        .onAppear {
            notifyRootVisibilityChanged()
        }
        .onChange(of: navigationPath.count) { _, _ in
            notifyRootVisibilityChanged()
        }
        .task {
            configureStore()
        }
        .onChange(of: auth.currentAccount?.pubkey) { _, _ in
            configureStore()
        }
        .onChange(of: auth.currentNsec) { _, _ in
            configureStore()
        }
        .onChange(of: relaySettings.readRelays) { _, _ in
            configureStore()
        }
        .onChange(of: relaySettings.writeRelays) { _, _ in
            configureStore()
        }
        .onChange(of: relaySettings.inboxRelays) { _, _ in
            configureStore()
        }
        .onChange(of: followStore.followedPubkeys) { _, _ in
            configureStore()
        }
        .tint(appSettings.primaryColor)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            header

            FlowCapsuleTabBar(
                selection: $activeTab,
                items: HaloLinkInboxTab.allCases,
                selectedBackground: inboxTabSelectedBackground,
                title: { $0.title }
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let errorMessage = store.errorMessage, !errorMessage.isEmpty {
                        errorCard(errorMessage)
                    }

                    if store.isLoading && store.conversations.isEmpty {
                        loadingCard
                    } else if visibleConversations.isEmpty {
                        emptyCard
                    } else {
                        conversationList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 22)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Messages")
                .font(appSettings.appFont(.largeTitle, weight: .bold))
                .foregroundStyle(appSettings.themePalette.foreground)

            Spacer(minLength: 12)

            Button("Mark all as read") {
                store.markAllAsRead()
            }
            .font(appSettings.appFont(.subheadline, weight: .medium))
            .foregroundStyle(
                store.unreadMessageCount > 0
                    ? appSettings.themePalette.secondaryForeground
                    : appSettings.themePalette.tertiaryForeground
            )
            .disabled(store.unreadMessageCount == 0)

            Button {
                isShowingNewConversationSheet = true
            } label: {
                Label("New", systemImage: "plus")
                    .font(appSettings.appFont(.headline, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Capsule(style: .continuous).fill(appSettings.primaryGradient))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var conversationList: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleConversations.enumerated()), id: \.element.id) { index, conversation in
                HaloLinkConversationRow(
                    conversation: conversation,
                    store: store,
                    timestampText: relativeTimestamp(for: conversation.lastMessageDate),
                    onOpen: {
                        openThread(HaloLinkThreadRoute(participantPubkeys: conversation.participantPubkeys))
                    },
                    onMarkAsRead: {
                        store.markConversationAsRead(conversation.id)
                    },
                    onDismiss: {
                        store.dismissConversation(conversation.id)
                    }
                )

                if index < visibleConversations.count - 1 {
                    Divider()
                        .overlay(appSettings.themePalette.separator)
                        .padding(.leading, 78)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(appSettings.themePalette.sheetCardBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(appSettings.themePalette.sheetCardBorder, lineWidth: 1)
        }
    }

    private var visibleConversations: [HaloLinkConversation] {
        switch activeTab {
        case .conversations:
            return store.activeConversations
        case .requests:
            return store.requests
        }
    }

    private var inboxTabSelectedBackground: Color {
        if appSettings.activeTheme == .sakura {
            return Color.white.opacity(0.88)
        } else if appSettings.activeTheme == .gamer {
            return appSettings.themePalette.chromeBackground.opacity(0.88)
        }
        return appSettings.themePalette.secondaryBackground
    }

    private var signedOutState: some View {
        HaloLinkInfoState(
            iconName: "bubble.left.and.bubble.right",
            title: "Sign in to use Halo Link",
            message: "Halo Link uses NIP-17 direct messages, reactions, and encrypted media in one inbox."
        )
    }

    private var noSignerState: some View {
        HaloLinkInfoState(
            iconName: "key.fill",
            title: "A private key is required",
            message: "This account can browse, but Halo Link needs an `nsec` so it can decrypt and send NIP-17 messages."
        )
    }

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)

            Text("Checking for messages...")
                .font(appSettings.appFont(.headline, weight: .semibold))
                .foregroundStyle(appSettings.themePalette.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(appSettings.themePalette.sheetCardBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(appSettings.themePalette.sheetCardBorder, lineWidth: 1)
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: activeTab == .conversations ? "bubble.left.and.bubble.right" : "tray")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(appSettings.themePalette.secondaryForeground)

            Text(activeTab == .conversations ? "No conversations yet" : "No requests right now")
                .font(appSettings.appFont(.headline, weight: .semibold))
                .foregroundStyle(appSettings.themePalette.foreground)

            Text(
                activeTab == .conversations
                    ? "Start a new Halo Link chat or wait for someone to message you."
                    : "Incoming message requests will show up here until you reply or dismiss them."
            )
            .font(appSettings.appFont(.subheadline))
            .foregroundStyle(appSettings.themePalette.secondaryForeground)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(appSettings.themePalette.sheetCardBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(appSettings.themePalette.sheetCardBorder, lineWidth: 1)
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(appSettings.themePalette.warningForeground)

            Text(message)
                .font(appSettings.appFont(.footnote))
                .foregroundStyle(appSettings.themePalette.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(appSettings.themePalette.sheetCardBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(appSettings.themePalette.sheetCardBorder, lineWidth: 1)
        }
    }

    private func configureStore() {
        store.configure(
            accountPubkey: auth.currentAccount?.pubkey,
            nsec: auth.currentNsec,
            readRelayURLs: relaySettings.readRelayURLs,
            writeRelayURLs: relaySettings.writeRelayURLs,
            inboxRelayURLs: relaySettings.inboxRelayURLs,
            followedPubkeys: followStore.followedPubkeys
        )
    }

    private func openThread(_ route: HaloLinkThreadRoute) {
        store.markConversationAsRead(route.id)
        navigationPath.append(route)
        isShowingNewConversationSheet = false
    }

    private func notifyRootVisibilityChanged() {
        isRootVisible = navigationPath.isEmpty
    }

    private func relativeTimestamp(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct HaloLinkConversationRow: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    let conversation: HaloLinkConversation
    @ObservedObject var store: HaloLinkStore
    let timestampText: String
    let onOpen: () -> Void
    let onMarkAsRead: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onOpen) {
                HStack(alignment: .center, spacing: 12) {
                    HaloLinkConversationAvatarStrip(
                        participantPubkeys: conversation.participantPubkeys,
                        store: store
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(title)
                                .font(appSettings.appFont(.headline, weight: .semibold))
                                .foregroundStyle(appSettings.themePalette.foreground)
                                .lineLimit(1)

                            if conversation.unreadCount > 0 {
                                Circle()
                                    .fill(appSettings.primaryColor)
                                    .frame(width: 7, height: 7)
                            }
                        }

                        Text(conversation.lastMessagePreview)
                            .font(appSettings.appFont(.subheadline))
                            .foregroundStyle(appSettings.themePalette.secondaryForeground)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text(timestampText)
                        .font(appSettings.appFont(.caption1))
                        .foregroundStyle(appSettings.themePalette.secondaryForeground)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Menu {
                if conversation.unreadCount > 0 {
                    Button("Mark as Read", systemImage: "checkmark") {
                        onMarkAsRead()
                    }
                }

                Button(
                    conversation.isRequest ? "Dismiss Request" : "Hide Conversation",
                    systemImage: "eye.slash"
                ) {
                    onDismiss()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(appSettings.themePalette.secondaryForeground)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var title: String {
        let names = conversation.participantPubkeys.map(store.displayName(for:))
        if names.isEmpty {
            return "Unknown"
        }
        if names.count == 1 {
            return names[0]
        }
        if names.count == 2 {
            return names.joined(separator: ", ")
        }
        return "\(names[0]), \(names[1]) +\(names.count - 2)"
    }
}

private struct HaloLinkConversationAvatarStrip: View {
    let participantPubkeys: [String]
    @ObservedObject var store: HaloLinkStore

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(Array(participantPubkeys.prefix(2)).enumerated()), id: \.element) { index, pubkey in
                AvatarView(
                    url: store.avatarURL(for: pubkey),
                    fallback: store.displayName(for: pubkey),
                    size: 42
                )
                .offset(x: CGFloat(index) * 20)
            }
        }
        .frame(width: participantPubkeys.count > 1 ? 62 : 42, height: 42, alignment: .leading)
    }
}

private struct HaloLinkInfoState: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    let iconName: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(appSettings.themePalette.secondaryForeground)

            Text(title)
                .font(appSettings.appFont(.title3, weight: .semibold))
                .foregroundStyle(appSettings.themePalette.foreground)

            Text(message)
                .font(appSettings.appFont(.subheadline))
                .foregroundStyle(appSettings.themePalette.secondaryForeground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct HaloLinkNewConversationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettingsStore

    @ObservedObject var store: HaloLinkStore
    let onOpenThread: (HaloLinkThreadRoute) -> Void

    @State private var query = ""
    @State private var selectedRecipientPubkeys: [String] = []
    @State private var searchResults: [ProfileSearchResult] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            List {
                if !selectedRecipientPubkeys.isEmpty {
                    Section("To") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(selectedRecipientPubkeys, id: \.self) { pubkey in
                                    Button {
                                        selectedRecipientPubkeys.removeAll { $0 == pubkey }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(store.displayName(for: pubkey))
                                            Image(systemName: "xmark.circle.fill")
                                        }
                                        .font(appSettings.appFont(.subheadline, weight: .medium))
                                        .foregroundStyle(appSettings.themePalette.foreground)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(appSettings.themePalette.secondaryGroupedBackground)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(appSettings.themePalette.sheetCardBackground)
                    }
                }

                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(appSettings.themePalette.secondaryForeground)

                        TextField("Search people", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        if isSearching {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }

                Section {
                    ForEach(searchResults) { result in
                        Button {
                            toggleSelection(for: result.pubkey)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(
                                    url: result.profile?.resolvedAvatarURL,
                                    fallback: result.profile?.displayName ?? shortNostrIdentifier(result.pubkey),
                                    size: 38
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(store.displayName(for: result.pubkey))
                                        .font(appSettings.appFont(.body, weight: .semibold))
                                        .foregroundStyle(appSettings.themePalette.foreground)
                                        .lineLimit(1)

                                    Text(store.handle(for: result.pubkey))
                                        .font(appSettings.appFont(.caption1))
                                        .foregroundStyle(appSettings.themePalette.secondaryForeground)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 8)

                                if selectedRecipientPubkeys.contains(result.pubkey.lowercased()) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(appSettings.primaryColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Recent Profiles")
                    } else {
                        Text("Results")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(appSettings.themePalette.groupedBackground)
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(actionButtonTitle) {
                        let route = HaloLinkThreadRoute(participantPubkeys: selectedRecipientPubkeys)
                        onOpenThread(route)
                        dismiss()
                    }
                    .disabled(selectedRecipientPubkeys.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            await loadResults()
        }
        .task(id: query) {
            await loadResults()
        }
    }

    private var actionButtonTitle: String {
        store.conversation(for: selectedRecipientPubkeys) == nil ? "Start" : "Open"
    }

    private func toggleSelection(for pubkey: String) {
        let normalizedPubkey = pubkey.lowercased()
        if selectedRecipientPubkeys.contains(normalizedPubkey) {
            selectedRecipientPubkeys.removeAll { $0 == normalizedPubkey }
        } else {
            selectedRecipientPubkeys.append(normalizedPubkey)
        }
    }

    private func loadResults() async {
        isSearching = true
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard !Task.isCancelled else { return }
        searchResults = await store.searchProfiles(query: query)
        isSearching = false
    }
}
