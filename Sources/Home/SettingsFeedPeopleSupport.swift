import NostrSDK
import SwiftUI

enum SettingsFeedRelayURLs {
    static let searchablePeopleRelayURLs: [URL] = [
        VertexProfileSearchService.relayURL,
        URL(string: "wss://relay.nostr.band/"),
        URL(string: "wss://search.nos.today/")
    ].compactMap { $0 }

    static func normalized(_ relayURLs: [URL]) -> [URL] {
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

struct SettingsNewsPersonPickerView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore

    var body: some View {
        SettingsFeedPersonPicker(
            relayURLs: searchRelayTargets,
            searchFooter: "Search uses Vertex plus your read relays. You can also paste a hex pubkey, npub, or nprofile directly.",
            isAdded: { pubkey in
                appSettings.newsAuthorPubkeys.contains(pubkey.lowercased())
            },
            onAdd: { result in
                try appSettings.addNewsAuthor(result.pubkey)
            }
        )
    }

    private var searchRelayTargets: [URL] {
        SettingsFeedRelayURLs.normalized(
            relaySettings.readRelayURLs +
            appSettings.newsRelayURLs +
            SettingsFeedRelayURLs.searchablePeopleRelayURLs
        )
    }
}

struct SettingsFeedPersonPicker: View {
    @EnvironmentObject private var auth: AuthManager

    let relayURLs: [URL]
    let searchFooter: String
    let isAdded: (String) -> Bool
    let onAdd: (ProfileSearchResult) throws -> Void

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
                Text(searchFooter)
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
                            isAdded: isAdded(result.pubkey.lowercased())
                        ) {
                            add(result)
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

    private func add(_ result: ProfileSearchResult) {
        do {
            try onAdd(result)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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

struct SettingsNewsAuthorRow: View {
    let pubkey: String
    let relayURLs: [URL]
    let service: NostrFeedService
    let onRemove: () -> Void

    @State private var profile: NostrProfile?

    var body: some View {
        let identity = SettingsFeedProfileIdentity(pubkey: pubkey, profile: profile)

        HStack(spacing: 12) {
            NewsAuthorAvatarView(
                url: identity.avatarURL,
                fallbackText: identity.displayName
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(identity.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(identity.handle)
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
            .accessibilityLabel("Remove \(identity.displayName)")
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
}

struct SettingsNewsPersonSearchRow: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    let result: ProfileSearchResult
    let isAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        let identity = SettingsFeedProfileIdentity(pubkey: result.pubkey, profile: result.profile)

        HStack(spacing: 12) {
            NewsAuthorAvatarView(
                url: identity.avatarURL,
                fallbackText: identity.displayName
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(identity.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(identity.handle)
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
                .accessibilityLabel("Add \(identity.displayName)")
            }
        }
    }
}

private struct SettingsFeedProfileIdentity {
    let pubkey: String
    let profile: NostrProfile?

    var displayName: String {
        if let displayName = normalized(profile?.displayName) {
            return displayName
        }
        if let name = normalized(profile?.name) {
            return name
        }
        return shortNostrIdentifier(pubkey)
    }

    var handle: String {
        if let name = normalized(profile?.name) {
            return "@\(name.replacingOccurrences(of: " ", with: "").lowercased())"
        }
        return "@\(shortNostrIdentifier(pubkey).lowercased())"
    }

    var avatarURL: URL? {
        profile?.resolvedAvatarURL
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
                CachedAsyncImage(url: url, kind: .avatar) { phase in
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
