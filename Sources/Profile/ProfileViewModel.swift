import Foundation
import NostrSDK

@MainActor
final class ProfileViewModel: ObservableObject {
    private struct VisibleItemsCacheKey: Equatable {
        let itemsRevision: Int
        let mode: FeedMode
        let hideNSFW: Bool
        let filterRevision: Int
    }

    @Published private(set) var profile: NostrProfile?
    @Published private(set) var metadataSnapshot: ProfileMetadataSnapshot?
    @Published private(set) var followingCount: Int = 0
    @Published private(set) var followsCurrentUser = false
    @Published private(set) var items: [FeedItem] = [] {
        didSet {
            itemsRevision &+= 1
            clearVisibleItemsCache()
        }
    }
    @Published var mode: FeedMode = .posts {
        didSet { clearVisibleItemsCache() }
    }
    @Published private(set) var isLoading = false
    @Published private(set) var hasCompletedInitialLoad = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isSavingProfile = false
    @Published var errorMessage: String?
    @Published var profileSaveError: String?

    let relayURL: URL
    let readRelayURLs: [URL]
    let writeRelayURLs: [URL]
    let pubkey: String

    private let pageSize: Int
    private let service: NostrFeedService
    private let profileEventService: ProfileEventService
    private let relayClient: NostrRelayClient
    private let mediaUploadService: ProfileMediaUploadService
    static let requestedFeedKinds = [1, 6, 16, 1068, 6969, 1111, 1244]

    private let requestKinds = ProfileViewModel.requestedFeedKinds
    private static let fastProfileFetchTimeout: TimeInterval = 3
    private static let fastProfileRelayFetchMode: RelayFetchMode = .firstNonEmptyRelay
    private var oldestCreatedAt: Int?
    private var hasReachedEnd = false
    private var hasLoadedInitialState = false
    private var itemHydrationTask: Task<Void, Never>?
    private var itemsRevision = 0
    private var visibleItemsCacheKey: VisibleItemsCacheKey?
    private var visibleItemsCache: [FeedItem] = []

    init(
        pubkey: String,
        relayURL: URL,
        readRelayURLs: [URL]? = nil,
        writeRelayURLs: [URL]? = nil,
        pageSize: Int = 70,
        service: NostrFeedService = NostrFeedService(),
        profileEventService: ProfileEventService = ProfileEventService(),
        relayClient: NostrRelayClient = NostrRelayClient(),
        mediaUploadService: ProfileMediaUploadService = .shared
    ) {
        self.pubkey = pubkey
        let sharedReadRelays = RelaySettingsStore.shared.readRelayURLs
        let sharedWriteRelays = RelaySettingsStore.shared.writeRelayURLs

        let normalizedReadRelays = Self.normalizedRelayURLs(
            readRelayURLs ?? (sharedReadRelays.isEmpty ? [relayURL] : sharedReadRelays)
        )
        let normalizedWriteRelays = Self.normalizedRelayURLs(
            writeRelayURLs ?? (sharedWriteRelays.isEmpty ? [relayURL] : sharedWriteRelays)
        )

        self.readRelayURLs = normalizedReadRelays.isEmpty ? [relayURL] : normalizedReadRelays
        self.writeRelayURLs = normalizedWriteRelays.isEmpty ? self.readRelayURLs : normalizedWriteRelays
        self.relayURL = self.readRelayURLs.first ?? relayURL
        self.pageSize = pageSize
        self.service = service
        self.profileEventService = profileEventService
        self.relayClient = relayClient
        self.mediaUploadService = mediaUploadService
    }

    var relayLabel: String {
        if readRelayURLs.count > 1 {
            return "\(readRelayURLs.count) relays"
        }
        return relayURL.host() ?? relayURL.absoluteString
    }

    var visibleItems: [FeedItem] {
        let key = VisibleItemsCacheKey(
            itemsRevision: itemsRevision,
            mode: mode,
            hideNSFW: AppSettingsStore.shared.hideNSFWContent,
            filterRevision: MuteStore.shared.filterRevision
        )

        if visibleItemsCacheKey == key {
            return visibleItemsCache
        }

        let filtered = filteredItems(items, for: mode)
        visibleItemsCacheKey = key
        visibleItemsCache = filtered
        return filtered
    }

    private var muteFilterSnapshot: MuteFilterSnapshot {
        MuteStore.shared.filterSnapshot
    }

    var displayName: String {
        if let displayName = profile?.displayName?.trimmed, !displayName.isEmpty {
            return displayName
        }
        if let name = profile?.name?.trimmed, !name.isEmpty {
            return name
        }
        return shortNostrIdentifier(pubkey)
    }

    var handle: String {
        if let name = profile?.name?.trimmed, !name.isEmpty {
            return "@\(name.replacingOccurrences(of: " ", with: "").lowercased())"
        }
        if let displayName = profile?.displayName?.trimmed, !displayName.isEmpty {
            return "@\(displayName.replacingOccurrences(of: " ", with: "").lowercased())"
        }
        return "@\(shortNostrIdentifier(pubkey).lowercased())"
    }

    var npub: String {
        if let publicKey = PublicKey(hex: pubkey) {
            return publicKey.npub
        }
        return pubkey
    }

    var avatarURL: URL? {
        guard let picture = profile?.picture?.trimmed, let url = URL(string: picture) else { return nil }
        return url
    }

    var bannerURL: URL? {
        guard let banner = profile?.banner?.trimmed, let url = URL(string: banner) else { return nil }
        return url
    }

    var about: String? {
        profile?.about?.trimmed
    }

    var nip05: String? {
        profile?.nip05?.trimmed
    }

    var websiteValue: String? {
        guard let website = profile?.website?.trimmed, !website.isEmpty else { return nil }
        return website
    }

    var websiteURL: URL? {
        ProfileMetadataEditing.normalizedWebsiteURL(from: websiteValue)
    }

    var lightningAddress: String? {
        profile?.lightningAddress?.trimmed
    }

    var editableFields: EditableProfileFields {
        EditableProfileFields(profile: profile)
    }

    deinit {
        itemHydrationTask?.cancel()
    }

    func loadIfNeeded() async {
        guard !hasLoadedInitialState else { return }
        hasLoadedInitialState = true
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        hasReachedEnd = false
        oldestCreatedAt = nil
        itemHydrationTask?.cancel()
        itemHydrationTask = nil

        if let cachedProfile = await service.cachedProfile(pubkey: pubkey) {
            profile = cachedProfile
        }
        if let cachedFollowingCount = await service.cachedFollowingCount(pubkey: pubkey) {
            followingCount = cachedFollowingCount
        }

        let requestHydrationMode: FeedItemHydrationMode = .cachedProfilesOnly
        let requestFetchTimeout = Self.fastProfileFetchTimeout
        let requestRelayFetchMode = Self.fastProfileRelayFetchMode

        defer {
            isLoading = false
            hasCompletedInitialLoad = true
        }

        async let fetchedProfile = service.fetchProfile(
            relayURLs: readRelayURLs,
            pubkey: pubkey,
            fetchTimeout: requestFetchTimeout,
            relayFetchMode: requestRelayFetchMode
        )
        async let fetchedFollowingCount = service.fetchFollowingCount(
            relayURLs: readRelayURLs,
            pubkey: pubkey,
            fetchTimeout: requestFetchTimeout,
            relayFetchMode: requestRelayFetchMode
        )
        async let fetchedMetadataResult: Result<ProfileMetadataSnapshot?, Error> = {
            do {
                return .success(try await fetchProfileMetadataSnapshot(relayURLs: readRelayURLs, pubkey: pubkey))
            } catch {
                return .failure(error)
            }
        }()

        var fetchedItems: [FeedItem] = []
        var feedError: Error?
        do {
            let feedWindow = try await fetchModeAwareAuthorFeed(
                until: nil,
                minimumVisibleCount: pageSize,
                hydrationMode: requestHydrationMode,
                fetchTimeout: requestFetchTimeout,
                relayFetchMode: requestRelayFetchMode,
                moderationSnapshot: muteFilterSnapshot
            )
            fetchedItems = feedWindow.items
            guard !Task.isCancelled else { return }

            items = pruneMutedItems(fetchedItems)
            oldestCreatedAt = feedWindow.oldestCreatedAt
            hasReachedEnd = feedWindow.hasReachedEnd
            scheduleItemHydration(for: items)
        } catch {
            feedError = error
        }

        if let resolvedProfile = await fetchedProfile {
            profile = resolvedProfile
        }
        followingCount = await fetchedFollowingCount

        switch await fetchedMetadataResult {
        case .success(let snapshot):
            metadataSnapshot = snapshot
        case .failure:
            break
        }

        if let _ = feedError {
            if items.isEmpty {
                errorMessage = "Couldn't load this profile right now."
            } else {
                errorMessage = "Couldn't refresh this profile."
            }
            return
        }
    }

    func loadMoreIfNeeded(currentItem: FeedItem) async {
        guard !isLoading, !isLoadingMore, !hasReachedEnd else { return }
        guard let lastVisibleID = visibleItems.last?.id, lastVisibleID == currentItem.id else { return }

        let until = max((oldestCreatedAt ?? Int(Date().timeIntervalSince1970)) - 1, 0)
        guard until > 0 else { return }

        let requestHydrationMode: FeedItemHydrationMode = .cachedProfilesOnly
        let requestFetchTimeout = Self.fastProfileFetchTimeout
        let requestRelayFetchMode = Self.fastProfileRelayFetchMode

        isLoadingMore = true
        itemHydrationTask?.cancel()
        itemHydrationTask = nil
        defer {
            isLoadingMore = false
        }

        do {
            let minimumVisibleCount = mode == .postsAndReplies
                ? min(max(pageSize / 2, 10), pageSize)
                : 1
            let feedWindow = try await fetchModeAwareAuthorFeed(
                until: until,
                minimumVisibleCount: minimumVisibleCount,
                hydrationMode: requestHydrationMode,
                fetchTimeout: requestFetchTimeout,
                relayFetchMode: requestRelayFetchMode,
                moderationSnapshot: muteFilterSnapshot
            )

            if feedWindow.items.isEmpty {
                hasReachedEnd = true
                return
            }

            oldestCreatedAt = feedWindow.oldestCreatedAt
            hasReachedEnd = feedWindow.hasReachedEnd
            mergeKeepingNewest(itemsToMerge: feedWindow.items)
            scheduleItemHydration(for: items)
        } catch {
            errorMessage = mode == .postsAndReplies
                ? "Couldn't load more replies."
                : "Couldn't load more posts."
        }
    }

    func prepareForSelectedModeIfNeeded() async {
        guard hasCompletedInitialLoad else { return }
        guard mode == .postsAndReplies else { return }
        guard !hasReachedEnd else { return }

        let minimumVisibleReplies = min(max(pageSize / 3, 8), pageSize)
        guard filteredItems(items, for: .postsAndReplies).count < minimumVisibleReplies else { return }

        await refresh()
    }

    func refreshFollowRelationship(currentAccountPubkey: String?) async {
        let normalizedCurrentPubkey = normalizePubkey(currentAccountPubkey)
        let normalizedProfilePubkey = normalizePubkey(pubkey)

        guard !normalizedCurrentPubkey.isEmpty,
              normalizedCurrentPubkey != normalizedProfilePubkey else {
            followsCurrentUser = false
            return
        }

        var didResolveFromCache = false
        if let cachedSnapshot = await service.cachedFollowListSnapshot(pubkey: pubkey) {
            followsCurrentUser = cachedSnapshot.followedPubkeys.contains(normalizedCurrentPubkey)
            didResolveFromCache = true
        }

        guard let fetchedSnapshot = try? await service.fetchFollowListSnapshot(
            relayURLs: readRelayURLs,
            pubkey: pubkey,
            fetchTimeout: Self.fastProfileFetchTimeout,
            relayFetchMode: Self.fastProfileRelayFetchMode
        ) else {
            if !didResolveFromCache {
                followsCurrentUser = false
            }
            return
        }

        guard !Task.isCancelled else { return }
        followsCurrentUser = fetchedSnapshot.followedPubkeys.contains(normalizedCurrentPubkey)
    }

    func saveProfile(
        fields: EditableProfileFields,
        currentAccountPubkey: String?,
        currentNsec: String?
    ) async -> Bool {
        guard normalizePubkey(currentAccountPubkey) == normalizePubkey(pubkey) else {
            profileSaveError = "Only the active account can edit this profile."
            return false
        }

        guard let normalizedNsec = normalizeNsec(currentNsec),
              let keypair = Keypair(nsec: normalizedNsec.lowercased()) else {
            profileSaveError = "Sign in with a private key to edit your profile."
            return false
        }

        guard !isSavingProfile else { return false }
        isSavingProfile = true
        profileSaveError = nil

        defer {
            isSavingProfile = false
        }

        do {
            let latestSnapshot = try await fetchProfileMetadataSnapshot(
                relayURLs: readRelayURLs,
                pubkey: pubkey
            )
            guard !Task.isCancelled else { return false }

            let baseSnapshot = latestSnapshot ?? metadataSnapshot
            let content = try ProfileMetadataEditing.mergedContent(
                fields: fields,
                baseJSON: baseSnapshot?.jsonObject ?? [:]
            )
            let sdkTags = (baseSnapshot?.tags ?? []).compactMap(decodeSDKTag(from:))

            let event = try NostrSDK.NostrEvent.Builder<NostrSDK.NostrEvent>(kind: .metadata)
                .content(content)
                .appendTags(contentsOf: sdkTags)
                .build(signedBy: keypair)

            let eventData = try JSONEncoder().encode(event)
            guard let eventObject = try JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
                throw RelayClientError.publishRejected("Malformed profile metadata")
            }

            let publishResult = await withTaskGroup(
                of: Error?.self,
                returning: (successfulPublishes: Int, firstError: Error?).self
            ) { group in
                for relayURL in writeRelayURLs {
                    group.addTask { [relayClient] in
                        do {
                            try await relayClient.publishEvent(
                                relayURL: relayURL,
                                eventObject: eventObject,
                                eventID: event.id
                            )
                            return nil
                        } catch {
                            return error
                        }
                    }
                }

                var successfulPublishes = 0
                var firstError: Error?
                for await error in group {
                    if let error {
                        if firstError == nil {
                            firstError = error
                        }
                    } else {
                        successfulPublishes += 1
                    }
                }

                return (successfulPublishes, firstError)
            }

            if publishResult.successfulPublishes == 0 {
                throw publishResult.firstError ?? RelayClientError.publishRejected("Couldn't publish profile metadata")
            }

            let updatedProfile = NostrProfile.decode(from: content)
            metadataSnapshot = ProfileMetadataSnapshot(content: content, tags: baseSnapshot?.tags ?? [])
            profile = updatedProfile
            if let updatedProfile {
                await ProfileCache.shared.store(profiles: [pubkey: updatedProfile], missed: [])
            }
            NotificationCenter.default.post(
                name: .profileMetadataUpdated,
                object: nil,
                userInfo: ["pubkey": pubkey.lowercased()]
            )
            profileSaveError = nil
            return true
        } catch {
            profileSaveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func uploadProfileImage(
        data: Data,
        mimeType: String,
        filename: String,
        currentAccountPubkey: String?,
        currentNsec: String?
    ) async throws -> String {
        guard normalizePubkey(currentAccountPubkey) == normalizePubkey(pubkey) else {
            throw ProfileMediaUploadError.notActiveAccount
        }

        guard let normalizedNsec = normalizeNsec(currentNsec) else {
            throw ProfileMediaUploadError.invalidCredentials
        }

        let uploadedURL = try await mediaUploadService.uploadProfileImage(
            data: data,
            mimeType: mimeType,
            filename: filename,
            nsec: normalizedNsec
        )
        return uploadedURL.absoluteString
    }

    private func fetchProfileMetadataSnapshot(
        relayURLs: [URL],
        pubkey: String
    ) async throws -> ProfileMetadataSnapshot? {
        let targets = Self.normalizedRelayURLs(relayURLs)
        guard !targets.isEmpty else { return nil }
        return try await profileEventService.fetchProfileMetadataSnapshot(relayURLs: targets, pubkey: pubkey)
    }

    private func mergeKeepingNewest(itemsToMerge: [FeedItem]) {
        var byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for item in itemsToMerge {
            byID[item.id] = item
        }
        items = pruneMutedItems(byID.values.sorted {
            if $0.event.createdAt == $1.event.createdAt {
                return $0.id > $1.id
            }
            return $0.event.createdAt > $1.event.createdAt
        })
    }

    private func filteredItems(_ sourceItems: [FeedItem], for mode: FeedMode) -> [FeedItem] {
        let hideNSFW = AppSettingsStore.shared.hideNSFWContent
        return sourceItems.filter { item in
            if MuteStore.shared.shouldHideAny(item.moderationEvents) {
                return false
            }
            if hideNSFW && item.moderationEvents.contains(where: { $0.containsNSFWHashtag }) {
                return false
            }

            switch mode {
            case .posts:
                return !item.displayEvent.isReplyNote
            case .postsAndReplies:
                return item.displayEvent.isReplyNote
            }
        }
    }

    private func pruneMutedItems(
        _ sourceItems: [FeedItem],
        snapshot: MuteFilterSnapshot? = nil
    ) -> [FeedItem] {
        let snapshot = snapshot ?? muteFilterSnapshot
        guard snapshot.hasAnyRules else { return sourceItems }

        return sourceItems.filter { item in
            !snapshot.shouldHideAny(in: item.moderationEvents)
        }
    }

    private func clearVisibleItemsCache() {
        visibleItemsCacheKey = nil
        visibleItemsCache = []
    }

    private struct FeedWindow {
        let items: [FeedItem]
        let oldestCreatedAt: Int?
        let hasReachedEnd: Bool
    }

    private func fetchModeAwareAuthorFeed(
        until: Int?,
        minimumVisibleCount: Int,
        hydrationMode: FeedItemHydrationMode,
        fetchTimeout: TimeInterval,
        relayFetchMode: RelayFetchMode,
        moderationSnapshot: MuteFilterSnapshot? = nil
    ) async throws -> FeedWindow {
        let targetMode = mode
        let batchSize = targetMode == .postsAndReplies ? max(pageSize, 100) : pageSize
        let maxBatches = targetMode == .postsAndReplies ? 4 : 1

        var aggregated: [FeedItem] = []
        var nextUntil = until
        var oldestFetchedCreatedAt: Int?
        var hasReachedEnd = false

        for _ in 0..<maxBatches {
            let fetched = try await service.fetchAuthorFeed(
                relayURLs: readRelayURLs,
                authorPubkey: pubkey,
                kinds: requestKinds,
                limit: batchSize,
                until: nextUntil,
                hydrationMode: hydrationMode,
                fetchTimeout: fetchTimeout,
                relayFetchMode: relayFetchMode,
                moderationSnapshot: moderationSnapshot
            )

            if fetched.isEmpty {
                hasReachedEnd = true
                break
            }

            oldestFetchedCreatedAt = fetched.last?.event.createdAt
            hasReachedEnd = fetched.count < batchSize
            aggregated = mergedItemsKeepingNewest(existing: aggregated, incoming: fetched)

            if filteredItems(aggregated, for: targetMode).count >= minimumVisibleCount {
                break
            }

            guard !hasReachedEnd, let oldestFetchedCreatedAt else {
                break
            }

            let candidateUntil = max(oldestFetchedCreatedAt - 1, 0)
            guard candidateUntil > 0 else {
                hasReachedEnd = true
                break
            }
            nextUntil = candidateUntil
        }

        return FeedWindow(
            items: aggregated,
            oldestCreatedAt: oldestFetchedCreatedAt,
            hasReachedEnd: hasReachedEnd
        )
    }

    private func mergedItemsKeepingNewest(existing: [FeedItem], incoming: [FeedItem]) -> [FeedItem] {
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for item in incoming {
            byID[item.id] = item
        }
        return byID.values.sorted {
            if $0.event.createdAt == $1.event.createdAt {
                return $0.id > $1.id
            }
            return $0.event.createdAt > $1.event.createdAt
        }
    }

    private func scheduleItemHydration(for sourceItems: [FeedItem]) {
        itemHydrationTask?.cancel()

        let events = sourceItems.map(\.event)
        guard !events.isEmpty else { return }
        let relayTargets = readRelayURLs

        itemHydrationTask = Task { [weak self] in
            guard let self else { return }
            let hydrated = await self.service.buildFeedItems(
                relayURLs: relayTargets,
                events: events,
                hydrationMode: .full,
                moderationSnapshot: self.muteFilterSnapshot
            )
            guard !Task.isCancelled else { return }
            guard !hydrated.isEmpty else { return }

            await MainActor.run {
                self.mergeKeepingNewest(itemsToMerge: hydrated)
            }
        }
    }

    private func decodeSDKTag(from raw: [String]) -> NostrSDK.Tag? {
        guard raw.count >= 2 else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: raw),
              let tag = try? JSONDecoder().decode(NostrSDK.Tag.self, from: data) else {
            return nil
        }
        return tag
    }

    private func normalizePubkey(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func normalizeNsec(_ value: String?) -> String? {
        guard let trimmed = value?.trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
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

enum ProfileMediaUploadError: LocalizedError {
    case notActiveAccount
    case invalidCredentials
    case invalidUploadService
    case invalidUploadResponse
    case missingUploadedURL
    case uploadFailed(statusCode: Int)
    case uploadFailedWithMessage(String)

    var errorDescription: String? {
        switch self {
        case .notActiveAccount:
            return "Only the active account can edit this profile."
        case .invalidCredentials:
            return "Sign in with a private key to upload a profile image."
        case .invalidUploadService:
            return "Media upload service is unavailable right now."
        case .invalidUploadResponse:
            return "Upload completed, but the media URL response was invalid."
        case .missingUploadedURL:
            return "Upload completed, but no media URL was returned."
        case .uploadFailed(let statusCode):
            return "Image upload failed (\(statusCode))."
        case .uploadFailedWithMessage(let message):
            return message
        }
    }
}

actor ProfileMediaUploadService {
    static let shared = ProfileMediaUploadService()
    private let mediaUploadService = MediaUploadService.shared

    func uploadProfileImage(
        data: Data,
        mimeType: String,
        filename: String,
        nsec: String
    ) async throws -> URL {
        do {
            let result = try await mediaUploadService.uploadMedia(
                data: data,
                mimeType: mimeType,
                filename: filename,
                nsec: nsec,
                provider: .blossom
            )
            return result.url
        } catch let uploadError as MediaUploadError {
            switch uploadError {
            case .invalidCredentials:
                throw ProfileMediaUploadError.invalidCredentials
            case .invalidUploadService:
                throw ProfileMediaUploadError.invalidUploadService
            case .missingUploadedURL:
                throw ProfileMediaUploadError.missingUploadedURL
            case .invalidUploadResponse:
                throw ProfileMediaUploadError.invalidUploadResponse
            case .blossomUploadFailed(let statusCode), .nip96UploadFailed(let statusCode):
                throw ProfileMediaUploadError.uploadFailed(statusCode: statusCode)
            case .blossomFallbackFailed(let primaryDescription, let fallbackDescription):
                throw ProfileMediaUploadError.uploadFailedWithMessage(
                    "Blossom failed: \(primaryDescription) Tried Nostr.Build too: \(fallbackDescription)"
                )
            case .unsupportedBlossomPayment, .missingFileData:
                throw uploadError
            }
        } catch {
            throw error
        }
    }
}

extension Notification.Name {
    static let profileMetadataUpdated = Notification.Name("x21.profileMetadataUpdated")
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
