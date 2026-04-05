import NostrSDK
import SwiftUI

struct SettingsFeedsView: View {
    var body: some View {
        ThemedSettingsForm {
            Section {
                SettingsNavigationRow(title: "Interests", systemImage: "sparkles") {
                    SettingsInterestsFeedView()
                }

                SettingsNavigationRow(title: "News", systemImage: "newspaper.fill") {
                    SettingsNewsFeedView()
                }

                SettingsNavigationRow(title: "Custom Feeds", systemImage: "square.stack.3d.up.fill") {
                    SettingsCustomFeedsView()
                }
            } footer: {
                Text("Choose what powers each feed. Interests uses hashtags from onboarding, News can combine relays, curated people, and hashtags, and Custom Feeds let you mix your own people, phrases, and topics.")
            }
        }
        .navigationTitle("Feeds")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsInterestsFeedView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var toastCenter: AppToastCenter
    @ObservedObject private var interestFeedStore = InterestFeedStore.shared

    @State private var hashtagInput = ""
    @State private var validationMessage: String?

    var body: some View {
        ThemedSettingsForm {
            Section("Add Hashtag") {
                TextField("#technology", text: $hashtagInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(addHashtag)

                Button("Add Hashtag") {
                    addHashtag()
                }
                .buttonStyle(.borderedProminent)
                .disabled(hashtagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section {
                if interestFeedStore.hashtags.isEmpty {
                    Text("No interest hashtags added yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(interestFeedStore.hashtags, id: \.self) { hashtag in
                        HStack(spacing: 10) {
                            Label("#\(hashtag)", systemImage: "number")
                                .foregroundStyle(.primary)

                            Spacer(minLength: 8)

                            Button {
                                interestFeedStore.removeHashtag(hashtag)
                                toastCenter.show("Removed #\(hashtag) from Interests", style: .info)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(AppSettingsStore.shared.primaryColor)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove #\(hashtag)")
                        }
                    }
                }
            } header: {
                Text("Hashtags")
            } footer: {
                Text("These hashtags power the Interests feed created during onboarding.")
            }

            if let validationMessage, !validationMessage.isEmpty {
                Section {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Interests")
        .navigationBarTitleDisplayMode(.large)
        .task {
            interestFeedStore.configure(accountPubkey: auth.currentAccount?.pubkey)
        }
        .onChange(of: auth.currentAccount?.pubkey) { _, newValue in
            interestFeedStore.configure(accountPubkey: newValue)
        }
    }

    private func addHashtag() {
        validationMessage = nil
        let normalizedHashtag = InterestTopic.normalizeHashtag(hashtagInput)
        let wasAlreadyAdded = interestFeedStore.hashtags.contains(normalizedHashtag)

        do {
            try interestFeedStore.addHashtag(hashtagInput)
            hashtagInput = ""
            if wasAlreadyAdded {
                toastCenter.show("#\(normalizedHashtag) is already in Interests", style: .info)
            } else {
                toastCenter.show("Added #\(normalizedHashtag) to Interests")
            }
        } catch {
            validationMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct SettingsNewsFeedView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore

    @State private var relayInput = ""
    @State private var hashtagInput = ""
    @State private var validationMessage: String?

    private let service = NostrFeedService()

    var body: some View {
        ThemedSettingsForm {
            Section {
                ForEach(appSettings.newsRelayURLs, id: \.self) { relay in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(relayLabel(for: relay))
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(relay.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Button {
                            removeRelay(relay)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(appSettings.primaryColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(appSettings.newsRelayURLs.count <= 1)
                        .accessibilityLabel("Remove \(relayLabel(for: relay))")
                    }
                }
            } header: {
                Text("News Relays")
            } footer: {
                Text("The News feed listens to all configured News relays.")
            }

            Section("Add Relay") {
                TextField("wss://news.example.com", text: $relayInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(addRelay)

                Button("Add Relay") {
                    addRelay()
                }
                .buttonStyle(.borderedProminent)
                .disabled(relayInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section {
                NavigationLink {
                    SettingsNewsPersonPickerView()
                } label: {
                    Label("Add Person", systemImage: "person.crop.circle.badge.plus")
                }

                if appSettings.newsAuthorPubkeys.isEmpty {
                    Text("No specific people added yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appSettings.newsAuthorPubkeys, id: \.self) { pubkey in
                        SettingsNewsAuthorRow(
                            pubkey: pubkey,
                            relayURLs: newsSearchRelayURLs,
                            service: service
                        ) {
                            appSettings.removeNewsAuthor(pubkey)
                        }
                    }
                }
            } header: {
                Text("People")
            } footer: {
                Text("Added people will always be blended into the News feed, even if they post on relays outside the News relay list.")
            }

            Section {
                if appSettings.newsHashtags.isEmpty {
                    Text("No hashtags added yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appSettings.newsHashtags, id: \.self) { hashtag in
                        HStack(spacing: 10) {
                            Label("#\(hashtag)", systemImage: "number")
                                .foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            Button {
                                appSettings.removeNewsHashtag(hashtag)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(appSettings.primaryColor)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove #\(hashtag)")
                        }
                    }
                }
            } header: {
                Text("Hashtags")
            } footer: {
                Text("Use hashtags to pull topic-specific notes into News.")
            }

            Section("Add Hashtag") {
                TextField("#breaking", text: $hashtagInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(addHashtag)

                Button("Add Hashtag") {
                    addHashtag()
                }
                .buttonStyle(.borderedProminent)
                .disabled(hashtagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let validationMessage {
                Section {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("News")
        .navigationBarTitleDisplayMode(.large)
    }

    private func relayLabel(for relay: URL) -> String {
        guard let host = relay.host, !host.isEmpty else {
            return relay.absoluteString
        }
        return host
    }

    private func addRelay() {
        validationMessage = nil

        do {
            try appSettings.addNewsRelay(relayInput)
            relayInput = ""
        } catch {
            validationMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func removeRelay(_ relay: URL) {
        validationMessage = nil

        do {
            try appSettings.removeNewsRelay(relay)
        } catch {
            validationMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func addHashtag() {
        validationMessage = nil

        do {
            try appSettings.addNewsHashtag(hashtagInput)
            hashtagInput = ""
        } catch {
            validationMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var newsSearchRelayURLs: [URL] {
        Self.normalizedRelayURLs(
            relaySettings.readRelayURLs +
            appSettings.newsRelayURLs +
            SettingsNewsPersonPickerView.searchableRelayURLs
        )
    }

    private static func normalizedRelayURLs(_ relayURLs: [URL]) -> [URL] {
        var seen = Set<String>()
        var ordered: [URL] = []

        for relayURL in relayURLs {
            let normalized = relayURL.absoluteString.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            ordered.append(relayURL)
        }

        return ordered
    }
}

private struct SettingsCustomFeedDraft: Identifiable, Hashable {
    var id: String
    var name: String
    var iconSystemName: String
    var hashtags: [String]
    var authorPubkeys: [String]
    var phrases: [String]

    init(
        id: String = UUID().uuidString.lowercased(),
        name: String = "",
        iconSystemName: String = CustomFeedIconCatalog.randomIconName(),
        hashtags: [String] = [],
        authorPubkeys: [String] = [],
        phrases: [String] = []
    ) {
        self.id = id
        self.name = name
        self.iconSystemName = iconSystemName
        self.hashtags = hashtags
        self.authorPubkeys = authorPubkeys
        self.phrases = phrases
    }

    init(feed: CustomFeedDefinition) {
        self.id = feed.id
        self.name = feed.name
        self.iconSystemName = feed.iconSystemName
        self.hashtags = feed.hashtags
        self.authorPubkeys = feed.authorPubkeys
        self.phrases = feed.phrases
    }

    var definition: CustomFeedDefinition {
        CustomFeedDefinition(
            id: id,
            name: name,
            iconSystemName: iconSystemName,
            hashtags: hashtags,
            authorPubkeys: authorPubkeys,
            phrases: phrases
        )
    }
}

private struct SettingsCustomFeedsView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    @State private var draft: SettingsCustomFeedDraft?

    var body: some View {
        ThemedSettingsForm {
            Section {
                Button {
                    draft = SettingsCustomFeedDraft()
                } label: {
                    Label("Create Feed", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.plain)
            } footer: {
                Text("Custom feeds appear in the main feed selector and can blend hashtags, specific people, and phrases.")
            }

            Section("Saved Feeds") {
                if appSettings.customFeeds.isEmpty {
                    Text("No custom feeds yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appSettings.customFeeds) { feed in
                        Button {
                            draft = SettingsCustomFeedDraft(feed: feed)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    Image(systemName: feed.iconSystemName)
                                        .font(.headline)
                                        .foregroundStyle(appSettings.primaryColor)
                                        .frame(width: 24, alignment: .center)

                                    Text(feed.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)

                                    Spacer(minLength: 8)

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }

                                Text(criteriaSummary(for: feed))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                appSettings.removeCustomFeed(id: feed.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Custom Feeds")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $draft) { currentDraft in
            SettingsCustomFeedEditorSheet(initialDraft: currentDraft)
        }
    }

    private func criteriaSummary(for feed: CustomFeedDefinition) -> String {
        let hashtags = feed.hashtags.map { "#\($0)" }
        let authors = feed.authorPubkeys.map { "@\(shortNostrIdentifier($0).lowercased())" }
        let phrases = feed.phrases.map { "\"\($0)\"" }
        let parts = hashtags + authors + phrases
        return parts.isEmpty ? "No sources configured" : parts.joined(separator: " • ")
    }
}

private struct SettingsCustomFeedEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore

    @State private var draft: SettingsCustomFeedDraft
    @State private var hashtagInput = ""
    @State private var phraseInput = ""
    @State private var validationMessage: String?

    private let service = NostrFeedService()

    init(initialDraft: SettingsCustomFeedDraft) {
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            ThemedSettingsForm {
                Section("Name") {
                    TextField("Soccer Season", text: $draft.name)
                }

                Section("Icon") {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(appSettings.primaryColor.opacity(0.14))
                                .frame(width: 56, height: 56)

                            Image(systemName: draft.iconSystemName)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(appSettings.primaryColor)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Choose an icon for this feed")
                                .font(.subheadline.weight(.medium))
                            Button("Randomize Icon") {
                                draft.iconSystemName = CustomFeedIconCatalog.randomIconName()
                            }
                            .font(.footnote.weight(.semibold))
                        }

                        Spacer(minLength: 0)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                        ForEach(CustomFeedIconCatalog.availableIcons, id: \.self) { icon in
                            Button {
                                draft.iconSystemName = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.headline)
                                    .foregroundStyle(draft.iconSystemName == icon ? appSettings.primaryColor : .primary)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(
                                                draft.iconSystemName == icon
                                                    ? appSettings.primaryColor.opacity(0.16)
                                                    : appSettings.themePalette.secondaryBackground
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }

                Section {
                    if draft.hashtags.isEmpty {
                        Text("No hashtags added yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(draft.hashtags, id: \.self) { hashtag in
                            HStack(spacing: 10) {
                                Label("#\(hashtag)", systemImage: "number")
                                    .foregroundStyle(.primary)

                                Spacer(minLength: 8)

                                Button {
                                    draft.hashtags.removeAll { $0 == hashtag }
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(appSettings.primaryColor)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove #\(hashtag)")
                            }
                        }
                    }
                } header: {
                    Text("Hashtags")
                } footer: {
                    Text("Hashtags pull in topic-based notes for this feed.")
                }

                Section("Add Hashtag") {
                    TextField("#soccer", text: $hashtagInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(addHashtag)

                    Button("Add Hashtag") {
                        addHashtag()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(hashtagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section {
                    NavigationLink {
                        SettingsCustomFeedPersonPickerView(
                            selectedPubkeys: $draft.authorPubkeys,
                            relayURLs: personSearchRelayURLs
                        )
                    } label: {
                        Label("Add Person", systemImage: "person.crop.circle.badge.plus")
                    }

                    if draft.authorPubkeys.isEmpty {
                        Text("No specific people added yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(draft.authorPubkeys, id: \.self) { pubkey in
                            SettingsNewsAuthorRow(
                                pubkey: pubkey,
                                relayURLs: personSearchRelayURLs,
                                service: service
                            ) {
                                draft.authorPubkeys.removeAll { $0 == pubkey }
                            }
                        }
                    }
                } header: {
                    Text("People")
                } footer: {
                    Text("People always pull notes from those authors into this feed.")
                }

                Section {
                    if draft.phrases.isEmpty {
                        Text("No phrases added yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(draft.phrases, id: \.self) { phrase in
                            HStack(spacing: 10) {
                                Label(phrase, systemImage: "text.quote")
                                    .foregroundStyle(.primary)

                                Spacer(minLength: 8)

                                Button {
                                    draft.phrases.removeAll { $0.caseInsensitiveCompare(phrase) == .orderedSame }
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(appSettings.primaryColor)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(phrase)")
                            }
                        }
                    }
                } header: {
                    Text("Phrases")
                } footer: {
                    Text("Phrases search across note content, like \"soccer scores\" or \"matchday\".")
                }

                Section("Add Phrase") {
                    TextField("soccer scores", text: $phraseInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(addPhrase)

                    Button("Add Phrase") {
                        addPhrase()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(phraseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if isEditingExistingFeed {
                    Section {
                        Button("Delete Feed", role: .destructive) {
                            appSettings.removeCustomFeed(id: draft.id)
                            dismiss()
                        }
                    }
                }

                if let validationMessage, !validationMessage.isEmpty {
                    Section {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditingExistingFeed ? "Edit Feed" : "Create Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditingExistingFeed ? "Save" : "Create") {
                        saveFeed()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var isEditingExistingFeed: Bool {
        appSettings.customFeed(withID: draft.id) != nil
    }

    private var personSearchRelayURLs: [URL] {
        Self.normalizedRelayURLs(
            relaySettings.readRelayURLs +
            appSettings.newsRelayURLs +
            SettingsNewsPersonPickerView.searchableRelayURLs
        )
    }

    private func addHashtag() {
        validationMessage = nil
        guard let normalized = AppSettingsStore.normalizedNewsHashtag(hashtagInput) else {
            validationMessage = AppSettingsError.invalidNewsHashtag.errorDescription
            return
        }

        if !draft.hashtags.contains(normalized) {
            draft.hashtags.append(normalized)
        }
        hashtagInput = ""
    }

    private func addPhrase() {
        validationMessage = nil
        guard let normalized = AppSettingsStore.normalizedCustomFeedPhrase(phraseInput) else {
            return
        }

        if !draft.phrases.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
            draft.phrases.append(normalized)
        }
        phraseInput = ""
    }

    private func saveFeed() {
        validationMessage = nil

        do {
            try appSettings.saveCustomFeed(draft.definition)
            dismiss()
        } catch {
            validationMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func normalizedRelayURLs(_ relayURLs: [URL]) -> [URL] {
        var seen = Set<String>()
        var ordered: [URL] = []

        for relayURL in relayURLs {
            let normalized = relayURL.absoluteString.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            ordered.append(relayURL)
        }

        return ordered
    }
}

private struct SettingsCustomFeedPersonPickerView: View {
    @EnvironmentObject private var auth: AuthManager

    @Binding var selectedPubkeys: [String]
    let relayURLs: [URL]

    @State private var searchText = ""
    @State private var results: [ProfileSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private let service = NostrFeedService()
    private let vertexSearchService = VertexProfileSearchService.shared

    var body: some View {
        ThemedSettingsForm {
            Section {
                TextField("Search name or paste npub", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: searchText) { _, _ in
                        scheduleSearch()
                    }

                if isSearching {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Searching people…")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Search")
            } footer: {
                Text("Search uses Vertex plus the selected relay set. You can also paste a hex pubkey, npub, or nprofile directly.")
            }

            if let errorMessage, !errorMessage.isEmpty {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Results") {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Search by name, handle, or paste a specific person identifier.")
                        .foregroundStyle(.secondary)
                } else if !isSearching && results.isEmpty {
                    Text("No people found yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { result in
                        SettingsNewsPersonSearchRow(
                            result: result,
                            isAdded: selectedPubkeys.contains(result.pubkey.lowercased())
                        ) {
                            let normalized = result.pubkey.lowercased()
                            if !selectedPubkeys.contains(normalized) {
                                selectedPubkeys.append(normalized)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Add Person")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        errorMessage = nil

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }

        searchTask = Task { [service] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            let exactPubkey = AppSettingsStore.normalizedNewsAuthorPubkey(from: trimmed)
            let profileQuery = normalizedProfileQuery(trimmed)
            let currentNsec = await MainActor.run { auth.currentNsec }

            await MainActor.run {
                isSearching = true
            }

            async let exactProfileTask: ProfileSearchResult? = fetchExactProfile(pubkey: exactPubkey)
            async let profileMatchesTask: [ProfileSearchResult] = fetchProfileMatches(
                query: profileQuery,
                currentNsec: currentNsec,
                service: service
            )

            let exactProfile = await exactProfileTask
            let profileMatches = await profileMatchesTask

            guard !Task.isCancelled else { return }

            let leadingExactMatches = exactProfile.map { [$0] } ?? []
            let merged = deduplicatedProfileResults([leadingExactMatches, profileMatches])
            await MainActor.run {
                results = merged
                isSearching = false
            }
        }
    }

    private func normalizedProfileQuery(_ value: String) -> String {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if trimmed.hasPrefix("@") {
            return String(trimmed.dropFirst())
        }
        if trimmed.hasPrefix("nostr:") {
            return String(trimmed.dropFirst("nostr:".count))
        }
        return trimmed
    }

    private func fetchExactProfile(pubkey: String?) async -> ProfileSearchResult? {
        guard let pubkey, !pubkey.isEmpty else { return nil }
        let profile = await service.fetchProfile(
            relayURLs: relayURLs,
            pubkey: pubkey,
            fetchTimeout: 6,
            relayFetchMode: .firstNonEmptyRelay
        )
        return ProfileSearchResult(
            pubkey: pubkey,
            profile: profile,
            createdAt: Int(Date().timeIntervalSince1970)
        )
    }

    private func fetchProfileMatches(
        query: String,
        currentNsec: String?,
        service: NostrFeedService
    ) async -> [ProfileSearchResult] {
        guard query.count >= 2 else { return [] }

        async let relaySearchTask: [ProfileSearchResult] = {
            do {
                return try await service.searchProfiles(
                    relayURLs: relayURLs,
                    query: query,
                    limit: 12,
                    fetchTimeout: 6,
                    relayFetchMode: .firstNonEmptyRelay
                )
            } catch {
                return []
            }
        }()

        async let vertexSearchTask: [ProfileSearchResult] = {
            guard let currentNsec, !currentNsec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return []
            }
            guard query.count > 3 else { return [] }

            do {
                return try await vertexSearchService.searchProfiles(
                    query: query,
                    limit: 12,
                    nsec: currentNsec,
                    relayURLs: relayURLs,
                    feedService: service
                )
            } catch {
                return []
            }
        }()

        let vertexMatches = await vertexSearchTask
        let relayMatches = await relaySearchTask
        return deduplicatedProfileResults([vertexMatches, relayMatches])
    }

    private func deduplicatedProfileResults(_ groups: [[ProfileSearchResult]]) -> [ProfileSearchResult] {
        var seen = Set<String>()
        var ordered: [ProfileSearchResult] = []

        for group in groups {
            for result in group {
                let normalized = result.pubkey.lowercased()
                guard seen.insert(normalized).inserted else { continue }
                ordered.append(result)
            }
        }

        return ordered
    }
}

private struct SettingsNewsAuthorRow: View {
    let pubkey: String
    let relayURLs: [URL]
    let service: NostrFeedService
    let onRemove: () -> Void

    @State private var profile: NostrProfile?

    var body: some View {
        HStack(spacing: 12) {
            NewsAuthorAvatarView(
                url: avatarURL,
                fallbackText: displayName
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(handle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                onRemove()
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(AppSettingsStore.shared.primaryColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(displayName)")
        }
        .task(id: pubkey) {
            if let cached = await service.cachedProfile(pubkey: pubkey) {
                profile = cached
            }

            if profile == nil, !relayURLs.isEmpty {
                profile = await service.fetchProfile(
                    relayURLs: relayURLs,
                    pubkey: pubkey,
                    fetchTimeout: 6,
                    relayFetchMode: .firstNonEmptyRelay
                )
            }
        }
    }

    private var displayName: String {
        if let displayName = normalized(profile?.displayName) {
            return displayName
        }
        if let name = normalized(profile?.name) {
            return name
        }
        return shortNostrIdentifier(pubkey)
    }

    private var handle: String {
        if let name = normalized(profile?.name) {
            return "@\(name.replacingOccurrences(of: " ", with: "").lowercased())"
        }
        return "@\(shortNostrIdentifier(pubkey).lowercased())"
    }

    private var avatarURL: URL? {
        guard let picture = normalized(profile?.picture) else { return nil }
        return URL(string: picture)
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct SettingsNewsPersonPickerView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var relaySettings: RelaySettingsStore

    @State private var searchText = ""
    @State private var results: [ProfileSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private let service = NostrFeedService()
    private let vertexSearchService = VertexProfileSearchService.shared

    static let searchableRelayURLs: [URL] = [
        VertexProfileSearchService.relayURL,
        URL(string: "wss://relay.nostr.band/"),
        URL(string: "wss://search.nos.today/")
    ].compactMap { $0 }

    var body: some View {
        ThemedSettingsForm {
            Section {
                TextField("Search name or paste npub", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: searchText) { _, _ in
                        scheduleSearch()
                    }

                if isSearching {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Searching people…")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Search")
            } footer: {
                Text("Search uses Vertex plus your read relays. You can also paste a hex pubkey, npub, or nprofile directly.")
            }

            if let errorMessage, !errorMessage.isEmpty {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Results") {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Search by name, handle, or paste a specific person identifier.")
                        .foregroundStyle(.secondary)
                } else if !isSearching && results.isEmpty {
                    Text("No people found yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { result in
                        SettingsNewsPersonSearchRow(
                            result: result,
                            isAdded: appSettings.newsAuthorPubkeys.contains(result.pubkey.lowercased())
                        ) {
                            do {
                                try appSettings.addNewsAuthor(result.pubkey)
                            } catch {
                                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Add Person")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        errorMessage = nil

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }

        searchTask = Task { [service] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            let relayURLs = searchRelayTargets
            let exactPubkey = AppSettingsStore.normalizedNewsAuthorPubkey(from: trimmed)
            let profileQuery = normalizedProfileQuery(trimmed)
            let currentNsec = await MainActor.run { auth.currentNsec }

            await MainActor.run {
                isSearching = true
            }

            async let exactProfileTask: ProfileSearchResult? = fetchExactProfile(pubkey: exactPubkey, relayURLs: relayURLs)
            async let profileMatchesTask: [ProfileSearchResult] = fetchProfileMatches(
                query: profileQuery,
                relayURLs: relayURLs,
                currentNsec: currentNsec,
                service: service
            )

            let exactProfile = await exactProfileTask
            let profileMatches = await profileMatchesTask

            guard !Task.isCancelled else { return }

            let leadingExactMatches = exactProfile.map { [$0] } ?? []
            let merged = deduplicatedProfileResults([leadingExactMatches, profileMatches])
            await MainActor.run {
                results = merged
                isSearching = false
            }
        }
    }

    private var searchRelayTargets: [URL] {
        Self.normalizedRelayURLs(
            relaySettings.readRelayURLs +
            appSettings.newsRelayURLs +
            Self.searchableRelayURLs
        )
    }

    private func normalizedProfileQuery(_ value: String) -> String {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if trimmed.hasPrefix("@") {
            return String(trimmed.dropFirst())
        }
        if trimmed.hasPrefix("nostr:") {
            return String(trimmed.dropFirst("nostr:".count))
        }
        return trimmed
    }

    private func fetchExactProfile(pubkey: String?, relayURLs: [URL]) async -> ProfileSearchResult? {
        guard let pubkey, !pubkey.isEmpty else { return nil }
        let profile = await service.fetchProfile(
            relayURLs: relayURLs,
            pubkey: pubkey,
            fetchTimeout: 6,
            relayFetchMode: .firstNonEmptyRelay
        )
        return ProfileSearchResult(
            pubkey: pubkey,
            profile: profile,
            createdAt: Int(Date().timeIntervalSince1970)
        )
    }

    private func fetchProfileMatches(
        query: String,
        relayURLs: [URL],
        currentNsec: String?,
        service: NostrFeedService
    ) async -> [ProfileSearchResult] {
        guard query.count >= 2 else { return [] }

        async let relaySearchTask: [ProfileSearchResult] = {
            do {
                return try await service.searchProfiles(
                    relayURLs: relayURLs,
                    query: query,
                    limit: 12,
                    fetchTimeout: 6,
                    relayFetchMode: .firstNonEmptyRelay
                )
            } catch {
                return []
            }
        }()

        async let vertexSearchTask: [ProfileSearchResult] = {
            guard let currentNsec, !currentNsec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return []
            }
            guard query.count > 3 else { return [] }

            do {
                return try await vertexSearchService.searchProfiles(
                    query: query,
                    limit: 12,
                    nsec: currentNsec,
                    relayURLs: relayURLs,
                    feedService: service
                )
            } catch {
                return []
            }
        }()

        let vertexMatches = await vertexSearchTask
        let relayMatches = await relaySearchTask
        return deduplicatedProfileResults([vertexMatches, relayMatches])
    }

    private func deduplicatedProfileResults(_ groups: [[ProfileSearchResult]]) -> [ProfileSearchResult] {
        var seen = Set<String>()
        var ordered: [ProfileSearchResult] = []

        for group in groups {
            for result in group {
                let normalized = result.pubkey.lowercased()
                guard seen.insert(normalized).inserted else { continue }
                ordered.append(result)
            }
        }

        return ordered
    }

    private static func normalizedRelayURLs(_ relayURLs: [URL]) -> [URL] {
        var seen = Set<String>()
        var ordered: [URL] = []

        for relayURL in relayURLs {
            let normalized = relayURL.absoluteString.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            ordered.append(relayURL)
        }

        return ordered
    }
}

private struct SettingsNewsPersonSearchRow: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    let result: ProfileSearchResult
    let isAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            NewsAuthorAvatarView(
                url: avatarURL,
                fallbackText: displayName
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(handle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isAdded {
                Text("Added")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    onAdd()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(appSettings.primaryColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(displayName)")
            }
        }
    }

    private var displayName: String {
        if let displayName = normalized(result.profile?.displayName) {
            return displayName
        }
        if let name = normalized(result.profile?.name) {
            return name
        }
        return shortNostrIdentifier(result.pubkey)
    }

    private var handle: String {
        if let name = normalized(result.profile?.name) {
            return "@\(name.replacingOccurrences(of: " ", with: "").lowercased())"
        }
        return "@\(shortNostrIdentifier(result.pubkey).lowercased())"
    }

    private var avatarURL: URL? {
        guard let picture = normalized(result.profile?.picture) else { return nil }
        return URL(string: picture)
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct NewsAuthorAvatarView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    let url: URL?
    let fallbackText: String

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Circle()
            .fill(appSettings.themePalette.tertiaryFill)
            .overlay {
                Text(String(fallbackText.prefix(1)).uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
    }
}
