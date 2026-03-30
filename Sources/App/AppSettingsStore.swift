import Foundation
import NostrSDK
import SwiftUI
import UIKit
import UserNotifications

enum AppThemeOption: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case system
    case black
    case white
    case sakura
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .black:
            return "Black"
        case .white:
            return "White"
        case .sakura:
            return "Sakura"
        case .dark:
            return "Dark"
        case .light:
            return "Light"
        }
    }

    var iconName: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .black:
            return "moon.fill"
        case .white:
            return "sun.max.fill"
        case .sakura:
            return "leaf.fill"
        case .dark:
            return "sparkles"
        case .light:
            return "sun.haze.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .system:
            return "Follow the device setting"
        case .black:
            return "Dark appearance"
        case .white:
            return "Light appearance"
        case .sakura:
            return "Paper whites with gradient blossom pinks"
        case .dark:
            return "Coming soon"
        case .light:
            return "Coming soon"
        }
    }

    var isEnabled: Bool {
        switch self {
        case .system, .black, .white, .sakura:
            return true
        case .dark, .light:
            return false
        }
    }

    var requiresFlowPlus: Bool {
        switch self {
        case .sakura:
            return true
        case .system, .black, .white, .dark, .light:
            return false
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .black, .dark:
            return .dark
        case .white, .light, .sakura:
            return .light
        }
    }

    var fixedPrimaryColor: Color? {
        switch self {
        case .sakura:
            return Color(red: 1.0, green: 0.404, blue: 0.941)
        case .system, .black, .white, .dark, .light:
            return nil
        }
    }

    var fixedPrimaryGradient: LinearGradient? {
        switch self {
        case .sakura:
            return LinearGradient(
                colors: [
                    Color(red: 0.976, green: 0.659, blue: 1.0),
                    Color(red: 1.0, green: 0.404, blue: 0.941)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .system, .black, .white, .dark, .light:
            return nil
        }
    }

    var qrShareBackgroundResourceName: String? {
        switch self {
        case .sakura:
            return "sakura-share-bg.json"
        case .system, .black, .white, .dark, .light:
            return nil
        }
    }

    var palette: AppThemePalette {
        switch self {
        case .system:
            return .system
        case .black:
            return .black
        case .white:
            return .white
        case .sakura:
            return .sakura
        case .dark:
            return .black
        case .light:
            return .white
        }
    }

    func isSelectable(with hasFlowPlus: Bool) -> Bool {
        isEnabled && (!requiresFlowPlus || hasFlowPlus)
    }
}

enum AppFontSize: Int, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case small
    case medium
    case large
    case extraLarge

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .small:
            return "Small"
        case .medium:
            return "Default"
        case .large:
            return "Large"
        case .extraLarge:
            return "XL"
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small:
            return .small
        case .medium:
            return .medium
        case .large:
            return .large
        case .extraLarge:
            return .xLarge
        }
    }
}

enum BreakReminderInterval: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case off
    case twentyMinutes
    case fortyMinutes
    case oneHour
    case twoHours

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .twentyMinutes:
            return "20 Minutes"
        case .fortyMinutes:
            return "40 Minutes"
        case .oneHour:
            return "1 Hour"
        case .twoHours:
            return "2 Hours"
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .off:
            return nil
        case .twentyMinutes:
            return 20 * 60
        case .fortyMinutes:
            return 40 * 60
        case .oneHour:
            return 60 * 60
        case .twoHours:
            return 2 * 60 * 60
        }
    }
}

struct CustomFeedDefinition: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var iconSystemName: String
    var hashtags: [String]
    var authorPubkeys: [String]
    var phrases: [String]

    init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        iconSystemName: String = CustomFeedIconCatalog.defaultIcon,
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

    var hasSources: Bool {
        !hashtags.isEmpty || !authorPubkeys.isEmpty || !phrases.isEmpty
    }

    var cacheSignature: String {
        [
            name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            iconSystemName.lowercased(),
            hashtags.joined(separator: ","),
            authorPubkeys.joined(separator: ","),
            phrases.map { $0.lowercased() }.joined(separator: ",")
        ].joined(separator: "|")
    }
}

enum CustomFeedIconCatalog {
    static let defaultIcon = "square.stack.3d.up.fill"

    static let availableIcons: [String] = [
        "square.stack.3d.up.fill",
        "newspaper.fill",
        "sparkles",
        "bolt.fill",
        "waveform.path.ecg",
        "soccerball",
        "trophy.fill",
        "figure.run",
        "globe.americas.fill",
        "chart.line.uptrend.xyaxis",
        "music.note",
        "headphones",
        "mic.fill",
        "film.fill",
        "camera.fill",
        "gamecontroller.fill",
        "leaf.fill",
        "flame.fill",
        "moon.stars.fill",
        "sun.max.fill",
        "flag.fill",
        "bird.fill",
        "book.fill",
        "heart.text.square.fill",
        "person.3.fill"
    ]

    static func normalizedIcon(_ iconSystemName: String?) -> String {
        guard let iconSystemName, availableIcons.contains(iconSystemName) else {
            return defaultIcon
        }
        return iconSystemName
    }

    static func randomIconName() -> String {
        availableIcons.randomElement() ?? defaultIcon
    }
}

enum AppSettingsError: LocalizedError {
    case invalidNewsRelayURL
    case newsRelayRequired
    case invalidNewsAuthorIdentifier
    case invalidNewsHashtag
    case invalidCustomFeedName
    case customFeedRequiresContent

    var errorDescription: String? {
        switch self {
        case .invalidNewsRelayURL:
            return "Enter a valid News relay URL (wss://...)."
        case .newsRelayRequired:
            return "Keep at least one News relay."
        case .invalidNewsAuthorIdentifier:
            return "Enter a valid hex pubkey, npub, or nprofile for News people."
        case .invalidNewsHashtag:
            return "Enter a valid hashtag for the News feed."
        case .invalidCustomFeedName:
            return "Give your feed a name."
        case .customFeedRequiresContent:
            return "Add at least one hashtag, person, or phrase to save this feed."
        }
    }
}

@MainActor
final class AppSettingsStore: ObservableObject {
    static let shared = AppSettingsStore()
    nonisolated static let slowModeRelayURL = URL(string: "wss://relay.damus.io/")!
    nonisolated static let defaultNewsRelayURLs = [URL(string: "wss://news.utxo.one")!]
    nonisolated static var defaultPrimaryColor: Color {
        Color(red: 0.67, green: 0.61, blue: 0.27)
    }
    nonisolated static let legacyStorageKey = "x21.app.settings"
    nonisolated static let legacyScopedStorageKeyPrefix = "x21.app.settings.v2"
    nonisolated static let storageKeyPrefix = "flow.app.settings.v2"
    nonisolated static let legacyMigrationAccountKey = "flow.app.settings.legacyMigratedAccount"

    private struct MentionMetadataDecoder: MetadataCoding {}

    @Published private var persistedSettings: PersistedSettings
    @Published private(set) var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var premiumThemesUnlocked = false
    @Published private(set) var premiumFontsUnlocked = false
    @Published private(set) var previewTheme: AppThemeOption?
    @Published private(set) var previewFontOption: AppFontOption?
    @Published private(set) var isFlowPlusPreviewUnlocked = false
    @Published private(set) var hasUsedFlowPlusPreviewThisSession = false
    @Published private(set) var hasUsedPremiumThemePreviewThisSession = false

    private let defaults: UserDefaults
    private let authStore: AuthStore
    private var currentAccountStorageID: String?
    private var notificationAuthorizationTask: Task<Void, Never>?

    private struct PersistedSettings: Codable, Sendable {
        private enum CodingKeys: String, CodingKey {
            case primaryColor
            case theme
            case fontOption
            case fontSize
            case breakReminderInterval
            case liveReactsEnabled
            case hideNSFWContent
            case autoplayVideos
            case autoplayVideoSoundEnabled
            case blurMediaFromUnfollowedAuthors
            case textOnlyMode
            case slowConnectionMode
            case notificationsEnabled
            case activityMentionNotificationsEnabled
            case activityReactionNotificationsEnabled
            case activityReplyNotificationsEnabled
            case activityReshareNotificationsEnabled
            case activityQuoteShareNotificationsEnabled
            case mediaUploadProvider
            case newsRelayURLs
            case newsAuthorPubkeys
            case newsHashtags
            case customFeeds
            case webOfTrustHops
        }

        var primaryColor: StoredColor?
        var theme: AppThemeOption = .system
        var fontOption: AppFontOption = .system
        var fontSize: AppFontSize = .medium
        var breakReminderInterval: BreakReminderInterval = .fortyMinutes
        var liveReactsEnabled: Bool = true
        var hideNSFWContent: Bool = true
        var autoplayVideos: Bool = true
        var autoplayVideoSoundEnabled: Bool = false
        var blurMediaFromUnfollowedAuthors: Bool = true
        var textOnlyMode: Bool = false
        var slowConnectionMode: Bool = false
        var notificationsEnabled: Bool = false
        var activityMentionNotificationsEnabled: Bool = true
        var activityReactionNotificationsEnabled: Bool = true
        var activityReplyNotificationsEnabled: Bool = true
        var activityReshareNotificationsEnabled: Bool = true
        var activityQuoteShareNotificationsEnabled: Bool = true
        var mediaUploadProvider: MediaUploadProvider = .blossom
        var newsRelayURLs: [URL] = AppSettingsStore.defaultNewsRelayURLs
        var newsAuthorPubkeys: [String] = []
        var newsHashtags: [String] = []
        var customFeeds: [CustomFeedDefinition] = []
        var webOfTrustHops: Int = 3

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            primaryColor = try container.decodeIfPresent(StoredColor.self, forKey: .primaryColor)
            theme = (try? container.decode(AppThemeOption.self, forKey: .theme)) ?? .system
            fontOption = (try? container.decode(AppFontOption.self, forKey: .fontOption)) ?? .system
            fontSize = (try? container.decode(AppFontSize.self, forKey: .fontSize)) ?? .medium
            breakReminderInterval = (try? container.decode(BreakReminderInterval.self, forKey: .breakReminderInterval)) ?? .fortyMinutes
            liveReactsEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveReactsEnabled) ?? true
            hideNSFWContent = try container.decodeIfPresent(Bool.self, forKey: .hideNSFWContent) ?? true
            autoplayVideos = try container.decodeIfPresent(Bool.self, forKey: .autoplayVideos) ?? true
            autoplayVideoSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoplayVideoSoundEnabled) ?? false
            blurMediaFromUnfollowedAuthors = try container.decodeIfPresent(Bool.self, forKey: .blurMediaFromUnfollowedAuthors) ?? true
            textOnlyMode = try container.decodeIfPresent(Bool.self, forKey: .textOnlyMode) ?? false
            slowConnectionMode = try container.decodeIfPresent(Bool.self, forKey: .slowConnectionMode) ?? false
            notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
            activityMentionNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .activityMentionNotificationsEnabled) ?? true
            activityReactionNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .activityReactionNotificationsEnabled) ?? true
            activityReplyNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .activityReplyNotificationsEnabled) ?? true
            activityReshareNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .activityReshareNotificationsEnabled) ?? true
            activityQuoteShareNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .activityQuoteShareNotificationsEnabled) ?? true
            mediaUploadProvider = (try? container.decode(MediaUploadProvider.self, forKey: .mediaUploadProvider)) ?? .blossom
            newsRelayURLs = AppSettingsStore.normalizedRelayURLs(
                (try? container.decode([URL].self, forKey: .newsRelayURLs)) ?? AppSettingsStore.defaultNewsRelayURLs,
                fallback: AppSettingsStore.defaultNewsRelayURLs
            )
            newsAuthorPubkeys = AppSettingsStore.normalizedNewsAuthorPubkeys(
                try container.decodeIfPresent([String].self, forKey: .newsAuthorPubkeys) ?? []
            )
            newsHashtags = AppSettingsStore.normalizedNewsHashtags(
                try container.decodeIfPresent([String].self, forKey: .newsHashtags) ?? []
            )
            customFeeds = AppSettingsStore.normalizedCustomFeeds(
                try container.decodeIfPresent([CustomFeedDefinition].self, forKey: .customFeeds) ?? []
            )
            webOfTrustHops = AppSettingsStore.clampedWebOfTrustHops(
                try container.decodeIfPresent(Int.self, forKey: .webOfTrustHops) ?? 3
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(primaryColor, forKey: .primaryColor)
            try container.encode(theme, forKey: .theme)
            try container.encode(fontOption, forKey: .fontOption)
            try container.encode(fontSize, forKey: .fontSize)
            try container.encode(breakReminderInterval, forKey: .breakReminderInterval)
            try container.encode(liveReactsEnabled, forKey: .liveReactsEnabled)
            try container.encode(hideNSFWContent, forKey: .hideNSFWContent)
            try container.encode(autoplayVideos, forKey: .autoplayVideos)
            try container.encode(autoplayVideoSoundEnabled, forKey: .autoplayVideoSoundEnabled)
            try container.encode(blurMediaFromUnfollowedAuthors, forKey: .blurMediaFromUnfollowedAuthors)
            try container.encode(textOnlyMode, forKey: .textOnlyMode)
            try container.encode(slowConnectionMode, forKey: .slowConnectionMode)
            try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
            try container.encode(activityMentionNotificationsEnabled, forKey: .activityMentionNotificationsEnabled)
            try container.encode(activityReactionNotificationsEnabled, forKey: .activityReactionNotificationsEnabled)
            try container.encode(activityReplyNotificationsEnabled, forKey: .activityReplyNotificationsEnabled)
            try container.encode(activityReshareNotificationsEnabled, forKey: .activityReshareNotificationsEnabled)
            try container.encode(activityQuoteShareNotificationsEnabled, forKey: .activityQuoteShareNotificationsEnabled)
            try container.encode(mediaUploadProvider, forKey: .mediaUploadProvider)
            try container.encode(newsRelayURLs, forKey: .newsRelayURLs)
            try container.encode(newsAuthorPubkeys, forKey: .newsAuthorPubkeys)
            try container.encode(newsHashtags, forKey: .newsHashtags)
            try container.encode(customFeeds, forKey: .customFeeds)
            try container.encode(webOfTrustHops, forKey: .webOfTrustHops)
        }
    }

    private struct StoredColor: Codable, Hashable, Sendable {
        let archivedData: Data

        init(color: Color) {
            let uiColor = UIColor(color)
            archivedData = (try? NSKeyedArchiver.archivedData(withRootObject: uiColor, requiringSecureCoding: true)) ?? Data()
        }

        var color: Color {
            guard !archivedData.isEmpty,
                  let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: archivedData) else {
                return AppSettingsStore.defaultPrimaryColor
            }
            return Color(uiColor)
        }
    }

    init(defaults: UserDefaults = .standard, authStore: AuthStore = .shared) {
        self.defaults = defaults
        self.authStore = authStore
        let authState = authStore.load()
        let initialAccountStorageID = Self.normalizedSettingsAccountID(
            authState.accounts.first(where: { $0.id == authState.currentAccountID })?.pubkey
        )
        let allowLegacyGlobalMigration = authState.accounts.count <= 1
        self.currentAccountStorageID = initialAccountStorageID

        if let initialAccountStorageID,
           let migratedSettings = Self.migrateLegacySettingsIfNeeded(
               defaults: defaults,
               accountStorageID: initialAccountStorageID,
               allowLegacyGlobalMigration: allowLegacyGlobalMigration
           ) {
            persistedSettings = migratedSettings
        } else if let initialAccountStorageID {
            persistedSettings = Self.loadPersistedSettings(
                defaults: defaults,
                accountStorageID: initialAccountStorageID,
                allowLegacyFallback: false
            )
        } else {
            persistedSettings = PersistedSettings()
        }
    }

    deinit {
        notificationAuthorizationTask?.cancel()
    }

    func configure(accountPubkey: String?) {
        let normalizedAccountStorageID = Self.normalizedSettingsAccountID(accountPubkey)
        guard currentAccountStorageID != normalizedAccountStorageID else { return }
        let allowLegacyGlobalMigration = authStore.load().accounts.count <= 1

        currentAccountStorageID = normalizedAccountStorageID

        guard let normalizedAccountStorageID else {
            persistedSettings = PersistedSettings()
            return
        }

        if let migratedSettings = Self.migrateLegacySettingsIfNeeded(
            defaults: defaults,
            accountStorageID: normalizedAccountStorageID,
            allowLegacyGlobalMigration: allowLegacyGlobalMigration
        ) {
            persistedSettings = migratedSettings
            return
        }

        persistedSettings = Self.loadPersistedSettings(
            defaults: defaults,
            accountStorageID: normalizedAccountStorageID,
            allowLegacyFallback: false
        )
    }

    var primaryColor: Color {
        get { activeTheme.fixedPrimaryColor ?? persistedSettings.primaryColor?.color ?? Self.defaultPrimaryColor }
        set {
            persistedSettings.primaryColor = StoredColor(color: newValue)
            persist()
        }
    }

    var primaryGradient: LinearGradient {
        if let fixedPrimaryGradient = activeTheme.fixedPrimaryGradient {
            return fixedPrimaryGradient
        }

        let color = primaryColor
        return LinearGradient(
            colors: [color, color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var theme: AppThemeOption {
        get { persistedSettings.theme }
        set {
            previewTheme = nil
            persistedSettings.theme = newValue
            persist()
        }
    }

    var fontSize: AppFontSize {
        get { persistedSettings.fontSize }
        set {
            persistedSettings.fontSize = newValue
            persist()
        }
    }

    var fontOption: AppFontOption {
        get { persistedSettings.fontOption }
        set {
            previewFontOption = nil
            persistedSettings.fontOption = newValue
            persist()
        }
    }

    var breakReminderInterval: BreakReminderInterval {
        get { persistedSettings.breakReminderInterval }
        set {
            persistedSettings.breakReminderInterval = newValue
            persist()
        }
    }

    var liveReactsEnabled: Bool {
        get { persistedSettings.liveReactsEnabled }
        set {
            persistedSettings.liveReactsEnabled = newValue
            persist()
        }
    }

    var textOnlyMode: Bool {
        get { persistedSettings.textOnlyMode }
        set {
            persistedSettings.textOnlyMode = newValue
            persist()
        }
    }

    var hideNSFWContent: Bool {
        get { persistedSettings.hideNSFWContent }
        set {
            persistedSettings.hideNSFWContent = newValue
            persist()
        }
    }

    var autoplayVideos: Bool {
        get { persistedSettings.autoplayVideos }
        set {
            persistedSettings.autoplayVideos = newValue
            persist()
        }
    }

    var autoplayVideoSoundEnabled: Bool {
        get { persistedSettings.autoplayVideoSoundEnabled }
        set {
            persistedSettings.autoplayVideoSoundEnabled = newValue
            persist()
        }
    }

    var blurMediaFromUnfollowedAuthors: Bool {
        get { persistedSettings.blurMediaFromUnfollowedAuthors }
        set {
            persistedSettings.blurMediaFromUnfollowedAuthors = newValue
            persist()
        }
    }

    var slowConnectionMode: Bool {
        get { persistedSettings.slowConnectionMode }
        set {
            persistedSettings.slowConnectionMode = newValue
            persist()
        }
    }

    var notificationsEnabled: Bool {
        get { persistedSettings.notificationsEnabled }
        set {
            persistedSettings.notificationsEnabled = newValue
            persist()

            if newValue {
                scheduleNotificationAuthorizationCheck()
            } else {
                notificationAuthorizationTask?.cancel()
                notificationAuthorizationTask = nil
            }
        }
    }

    var activityMentionNotificationsEnabled: Bool {
        get { persistedSettings.activityMentionNotificationsEnabled }
        set {
            persistedSettings.activityMentionNotificationsEnabled = newValue
            persist()
        }
    }

    var activityReactionNotificationsEnabled: Bool {
        get { persistedSettings.activityReactionNotificationsEnabled }
        set {
            persistedSettings.activityReactionNotificationsEnabled = newValue
            persist()
        }
    }

    var activityReplyNotificationsEnabled: Bool {
        get { persistedSettings.activityReplyNotificationsEnabled }
        set {
            persistedSettings.activityReplyNotificationsEnabled = newValue
            persist()
        }
    }

    var activityReshareNotificationsEnabled: Bool {
        get { persistedSettings.activityReshareNotificationsEnabled }
        set {
            persistedSettings.activityReshareNotificationsEnabled = newValue
            persist()
        }
    }

    var activityQuoteShareNotificationsEnabled: Bool {
        get { persistedSettings.activityQuoteShareNotificationsEnabled }
        set {
            persistedSettings.activityQuoteShareNotificationsEnabled = newValue
            persist()
        }
    }

    var mediaUploadProvider: MediaUploadProvider {
        get { persistedSettings.mediaUploadProvider }
        set {
            persistedSettings.mediaUploadProvider = newValue
            persist()
        }
    }

    var newsRelayURLs: [URL] {
        get { persistedSettings.newsRelayURLs }
        set {
            persistedSettings.newsRelayURLs = Self.normalizedRelayURLs(
                newValue,
                fallback: Self.defaultNewsRelayURLs
            )
            persist()
        }
    }

    var newsAuthorPubkeys: [String] {
        get { persistedSettings.newsAuthorPubkeys }
        set {
            persistedSettings.newsAuthorPubkeys = Self.normalizedNewsAuthorPubkeys(newValue)
            persist()
        }
    }

    var newsHashtags: [String] {
        get { persistedSettings.newsHashtags }
        set {
            persistedSettings.newsHashtags = Self.normalizedNewsHashtags(newValue)
            persist()
        }
    }

    var webOfTrustHops: Int {
        get { persistedSettings.webOfTrustHops }
        set {
            persistedSettings.webOfTrustHops = Self.clampedWebOfTrustHops(newValue)
            persist()
        }
    }

    var customFeeds: [CustomFeedDefinition] {
        get { persistedSettings.customFeeds }
        set {
            persistedSettings.customFeeds = Self.normalizedCustomFeeds(newValue)
            persist()
        }
    }

    func addNewsRelay(_ relayInput: String) throws {
        guard let relayURL = Self.normalizedRelayURL(from: relayInput) else {
            throw AppSettingsError.invalidNewsRelayURL
        }

        setNewsRelayURLs(newsRelayURLs + [relayURL])
    }

    func removeNewsRelay(_ relayURL: URL) throws {
        guard newsRelayURLs.count > 1 else {
            throw AppSettingsError.newsRelayRequired
        }

        let normalizedRelayURL = Self.normalizedRelayURL(relayURL) ?? relayURL
        let updatedRelayURLs = newsRelayURLs.filter { $0.absoluteString != normalizedRelayURL.absoluteString }

        guard updatedRelayURLs.count < newsRelayURLs.count else { return }
        setNewsRelayURLs(updatedRelayURLs)
    }

    func setNewsRelayURLs(_ relayURLs: [URL]) {
        newsRelayURLs = relayURLs
    }

    func addNewsAuthor(_ rawIdentifier: String) throws {
        guard let pubkey = Self.normalizedNewsAuthorPubkey(from: rawIdentifier) else {
            throw AppSettingsError.invalidNewsAuthorIdentifier
        }
        setNewsAuthorPubkeys(newsAuthorPubkeys + [pubkey])
    }

    func removeNewsAuthor(_ pubkey: String) {
        let normalizedPubkey = pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedPubkey.isEmpty else { return }
        newsAuthorPubkeys = newsAuthorPubkeys.filter { $0 != normalizedPubkey }
    }

    func setNewsAuthorPubkeys(_ pubkeys: [String]) {
        newsAuthorPubkeys = pubkeys
    }

    func addNewsHashtag(_ rawHashtag: String) throws {
        guard let hashtag = Self.normalizedNewsHashtag(rawHashtag) else {
            throw AppSettingsError.invalidNewsHashtag
        }
        setNewsHashtags(newsHashtags + [hashtag])
    }

    func removeNewsHashtag(_ hashtag: String) {
        let normalizedHashtag = Self.normalizedNewsHashtag(hashtag) ?? hashtag
        newsHashtags = newsHashtags.filter { $0 != normalizedHashtag }
    }

    func setNewsHashtags(_ hashtags: [String]) {
        newsHashtags = hashtags
    }

    func saveCustomFeed(_ feed: CustomFeedDefinition) throws {
        let normalizedFeed = try Self.normalizedCustomFeed(feed)
        var updatedFeeds = customFeeds

        if let existingIndex = updatedFeeds.firstIndex(where: { $0.id == normalizedFeed.id }) {
            updatedFeeds[existingIndex] = normalizedFeed
        } else {
            updatedFeeds.append(normalizedFeed)
        }

        customFeeds = updatedFeeds
    }

    func removeCustomFeed(id: String) {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedID.isEmpty else { return }
        customFeeds = customFeeds.filter { $0.id != normalizedID }
    }

    func customFeed(withID id: String) -> CustomFeedDefinition? {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedID.isEmpty else { return nil }
        return customFeeds.first { $0.id == normalizedID }
    }

    var activeTheme: AppThemeOption {
        if let previewTheme, previewTheme.isEnabled {
            return previewTheme
        }
        let requestedTheme = persistedSettings.theme
        return requestedTheme.isSelectable(with: premiumThemesUnlocked) ? requestedTheme : .system
    }

    var themePalette: AppThemePalette {
        activeTheme.palette
    }

    var activeFontOption: AppFontOption {
        if let previewFontOption, previewFontOption.isEnabled {
            return previewFontOption
        }
        let requestedFontOption = persistedSettings.fontOption
        return requestedFontOption.isSelectable(with: premiumFontsUnlocked) ? requestedFontOption : .system
    }

    var hasFlowPlusCustomizationAccess: Bool {
        premiumThemesUnlocked || premiumFontsUnlocked || isFlowPlusPreviewUnlocked
    }

    var canCustomizePrimaryColor: Bool {
        activeTheme.fixedPrimaryColor == nil
    }

    func canBeginThemePreview(_ theme: AppThemeOption) -> Bool {
        guard theme.isEnabled else { return false }
        guard theme.requiresFlowPlus else { return true }
        guard !premiumThemesUnlocked else { return true }
        return !hasUsedPremiumThemePreviewThisSession || previewTheme == theme
    }

    func canBeginFlowPlusPreview() -> Bool {
        guard !premiumThemesUnlocked || !premiumFontsUnlocked else { return true }
        return !hasUsedFlowPlusPreviewThisSession || isFlowPlusPreviewUnlocked
    }

    @discardableResult
    func beginFlowPlusPreview() -> Bool {
        guard canBeginFlowPlusPreview() else { return false }
        isFlowPlusPreviewUnlocked = true
        if !premiumThemesUnlocked || !premiumFontsUnlocked {
            hasUsedFlowPlusPreviewThisSession = true
        }
        return true
    }

    @discardableResult
    func beginThemePreview(_ theme: AppThemeOption) -> Bool {
        guard canBeginThemePreview(theme) else { return false }
        previewTheme = theme
        if theme.requiresFlowPlus && !premiumThemesUnlocked {
            hasUsedPremiumThemePreviewThisSession = true
        }
        return true
    }

    func endThemePreview() {
        previewTheme = nil
    }

    func beginFontPreview(_ option: AppFontOption) {
        guard option.isEnabled else { return }
        previewFontOption = option
    }

    func endFontPreview() {
        previewFontOption = nil
    }

    func updateFlowPlusAccess(_ unlocked: Bool) {
        guard premiumThemesUnlocked != unlocked || premiumFontsUnlocked != unlocked else { return }
        premiumThemesUnlocked = unlocked
        premiumFontsUnlocked = unlocked
        if unlocked {
            isFlowPlusPreviewUnlocked = false
        }

        if unlocked, let previewTheme, previewTheme.requiresFlowPlus {
            persistedSettings.theme = previewTheme
            self.previewTheme = nil
        }

        if unlocked, let previewFontOption, previewFontOption.requiresFlowPlus {
            persistedSettings.fontOption = previewFontOption
            self.previewFontOption = nil
        }

        persist()
    }

    var preferredColorScheme: ColorScheme? {
        activeTheme.preferredColorScheme
    }

    var dynamicTypeSize: DynamicTypeSize {
        fontSize.dynamicTypeSize
    }

    var reactionsVisibleInFeeds: Bool {
        !slowConnectionMode
    }

    func effectiveReadRelayURLs(from relayURLs: [URL]) -> [URL] {
        if slowConnectionMode {
            return [Self.slowModeRelayURL]
        }
        let normalized = Self.normalizedRelayURLs(relayURLs)
        return normalized.isEmpty ? [Self.slowModeRelayURL] : normalized
    }

    func effectiveWriteRelayURLs(from relayURLs: [URL], fallbackReadRelayURLs: [URL] = []) -> [URL] {
        if slowConnectionMode {
            return [Self.slowModeRelayURL]
        }

        let normalizedWrite = Self.normalizedRelayURLs(relayURLs)
        if !normalizedWrite.isEmpty {
            return normalizedWrite
        }

        let normalizedFallback = Self.normalizedRelayURLs(fallbackReadRelayURLs)
        return normalizedFallback.isEmpty ? [Self.slowModeRelayURL] : normalizedFallback
    }

    var notificationsStatusDescription: String {
        switch notificationAuthorizationStatus {
        case .notDetermined:
            return notificationsEnabled
                ? "Waiting for iOS to ask for permission."
                : "Turn this on to request permission."
        case .authorized, .provisional, .ephemeral:
            return notificationsEnabled
                ? "Notifications are enabled on this device."
                : "Notifications are allowed, but this app setting is off."
        case .denied:
            return "Notifications are blocked in iOS Settings."
        @unknown default:
            return "Notification status is unavailable."
        }
    }

    var activityNotificationPreferenceSignature: String {
        [
            activityMentionNotificationsEnabled,
            activityReactionNotificationsEnabled,
            activityReplyNotificationsEnabled,
            activityReshareNotificationsEnabled,
            activityQuoteShareNotificationsEnabled
        ]
        .map { $0 ? "1" : "0" }
        .joined(separator: "-")
    }

    func isActivityNotificationEnabled(for preference: ActivityNotificationPreference) -> Bool {
        switch preference {
        case .mentions:
            return activityMentionNotificationsEnabled
        case .reactions:
            return activityReactionNotificationsEnabled
        case .replies:
            return activityReplyNotificationsEnabled
        case .reshares:
            return activityReshareNotificationsEnabled
        case .quoteShares:
            return activityQuoteShareNotificationsEnabled
        }
    }

    func refreshNotificationAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorizationStatus = settings.authorizationStatus

        if settings.authorizationStatus == .denied {
            if persistedSettings.notificationsEnabled {
                persistedSettings.notificationsEnabled = false
                persist()
            }
        }
    }

    private func scheduleNotificationAuthorizationCheck() {
        notificationAuthorizationTask?.cancel()
        notificationAuthorizationTask = Task { [weak self] in
            guard let self else { return }
            await self.resolveNotificationAuthorization()
        }
    }

    private func resolveNotificationAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        notificationAuthorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return
        case .denied:
            if persistedSettings.notificationsEnabled {
                persistedSettings.notificationsEnabled = false
                persist()
            }
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            let refreshed = await center.notificationSettings()
            notificationAuthorizationStatus = refreshed.authorizationStatus

            if !granted || !(refreshed.authorizationStatus == .authorized || refreshed.authorizationStatus == .provisional || refreshed.authorizationStatus == .ephemeral) {
                if persistedSettings.notificationsEnabled {
                    persistedSettings.notificationsEnabled = false
                    persist()
                }
            }
        @unknown default:
            if persistedSettings.notificationsEnabled {
                persistedSettings.notificationsEnabled = false
                persist()
            }
        }

        notificationAuthorizationTask = nil
    }

    private func persist() {
        guard currentAccountStorageID != nil else { return }
        guard let data = try? JSONEncoder().encode(persistedSettings) else { return }
        defaults.set(data, forKey: Self.storageKey(for: currentAccountStorageID))
    }

    nonisolated private static func storageKey(for accountStorageID: String?) -> String {
        "\(storageKeyPrefix).\(accountStorageID ?? "anonymous")"
    }

    nonisolated private static func legacyScopedStorageKey(for accountStorageID: String?) -> String {
        "\(legacyScopedStorageKeyPrefix).\(accountStorageID ?? "anonymous")"
    }

    nonisolated private static func decodeSettings(from data: Data?) -> PersistedSettings? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(PersistedSettings.self, from: data)
    }

    nonisolated private static func loadPersistedSettings(
        defaults: UserDefaults,
        accountStorageID: String?,
        allowLegacyFallback: Bool
    ) -> PersistedSettings {
        if let scopedSettings = decodeSettings(from: defaults.data(forKey: storageKey(for: accountStorageID))) {
            return scopedSettings
        }

        if let legacyScopedSettings = decodeSettings(from: defaults.data(forKey: legacyScopedStorageKey(for: accountStorageID))) {
            if let encoded = try? JSONEncoder().encode(legacyScopedSettings) {
                defaults.set(encoded, forKey: storageKey(for: accountStorageID))
            }
            return legacyScopedSettings
        }

        if allowLegacyFallback,
           let legacySettings = decodeSettings(from: defaults.data(forKey: legacyStorageKey)) {
            return legacySettings
        }

        return PersistedSettings()
    }

    nonisolated private static func migrateLegacySettingsIfNeeded(
        defaults: UserDefaults,
        accountStorageID: String,
        allowLegacyGlobalMigration: Bool
    ) -> PersistedSettings? {
        guard defaults.data(forKey: storageKey(for: accountStorageID)) == nil else { return nil }
        if let legacyScopedSettings = decodeSettings(from: defaults.data(forKey: legacyScopedStorageKey(for: accountStorageID))) {
            guard let encoded = try? JSONEncoder().encode(legacyScopedSettings) else { return legacyScopedSettings }
            defaults.set(encoded, forKey: storageKey(for: accountStorageID))
            return legacyScopedSettings
        }

        guard allowLegacyGlobalMigration else { return nil }
        guard defaults.string(forKey: legacyMigrationAccountKey) == nil else { return nil }
        guard let legacySettings = decodeSettings(from: defaults.data(forKey: legacyStorageKey)) else {
            return nil
        }
        guard let encoded = try? JSONEncoder().encode(legacySettings) else { return legacySettings }

        defaults.set(encoded, forKey: storageKey(for: accountStorageID))
        defaults.set(accountStorageID, forKey: legacyMigrationAccountKey)
        return legacySettings
    }

    nonisolated private static func normalizedSettingsAccountID(_ pubkey: String?) -> String? {
        let normalized = pubkey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalized, !normalized.isEmpty else { return nil }
        return normalized
    }

    nonisolated private static func normalizedRelayURL(_ relayURL: URL) -> URL? {
        guard var components = URLComponents(url: relayURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.query = nil
        components.fragment = nil
        if components.path == "/" {
            components.path = ""
        }

        return components.url
    }

    nonisolated private static func normalizedRelayURL(from relayInput: String) -> URL? {
        let trimmedInput = relayInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty, let relayURL = URL(string: trimmedInput) else {
            return nil
        }
        return normalizedRelayURL(relayURL)
    }

    nonisolated static func clampedWebOfTrustHops(_ value: Int) -> Int {
        min(max(value, 1), 5)
    }

    nonisolated private static func normalizedRelayURLs(_ relayURLs: [URL], fallback: [URL] = []) -> [URL] {
        var seen = Set<String>()
        var ordered: [URL] = []

        for relayURL in relayURLs {
            guard let normalized = normalizedRelayURL(relayURL) else { continue }
            let normalizedKey = normalized.absoluteString
            guard seen.insert(normalizedKey).inserted else { continue }
            ordered.append(normalized)
        }

        if ordered.isEmpty, !fallback.isEmpty {
            return normalizedRelayURLs(fallback)
        }

        return ordered
    }

    nonisolated private static func normalizedNewsAuthorPubkeys(_ pubkeys: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for pubkey in pubkeys {
            let normalized = pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard normalized.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { continue }
            guard seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }

        return ordered
    }

    nonisolated static func normalizedNewsAuthorPubkey(from rawIdentifier: String) -> String? {
        let normalized = normalizedIdentifier(rawIdentifier)
        guard !normalized.isEmpty else { return nil }

        if normalized.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil {
            return normalized
        }

        if normalized.hasPrefix("npub1") {
            return PublicKey(npub: normalized)?.hex.lowercased()
        }

        if normalized.hasPrefix("nprofile1") {
            let decoder = MentionMetadataDecoder()
            let metadata = try? decoder.decodedMetadata(from: normalized)
            return metadata?.pubkey?.lowercased()
        }

        return nil
    }

    nonisolated private static func normalizedNewsHashtags(_ hashtags: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for hashtag in hashtags {
            guard let normalized = normalizedNewsHashtag(hashtag) else { continue }
            guard seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }

        return ordered
    }

    nonisolated static func normalizedNewsHashtag(_ rawHashtag: String) -> String? {
        let normalized = rawHashtag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .lowercased()
        guard !normalized.isEmpty else { return nil }
        return normalized
    }

    nonisolated static func normalizedCustomFeedName(_ rawName: String) -> String? {
        let normalized = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return normalized
    }

    nonisolated static func normalizedCustomFeedPhrase(_ rawPhrase: String) -> String? {
        let normalized = rawPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return normalized
    }

    nonisolated private static func normalizedCustomFeedPhrases(_ phrases: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for phrase in phrases {
            guard let normalized = normalizedCustomFeedPhrase(phrase) else { continue }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { continue }
            ordered.append(normalized)
        }

        return ordered
    }

    nonisolated private static func normalizedCustomFeed(_ feed: CustomFeedDefinition) throws -> CustomFeedDefinition {
        guard let normalizedName = normalizedCustomFeedName(feed.name) else {
            throw AppSettingsError.invalidCustomFeedName
        }

        let normalizedHashtags = normalizedNewsHashtags(feed.hashtags)
        let normalizedAuthors = normalizedNewsAuthorPubkeys(feed.authorPubkeys)
        let normalizedPhrases = normalizedCustomFeedPhrases(feed.phrases)

        guard !normalizedHashtags.isEmpty || !normalizedAuthors.isEmpty || !normalizedPhrases.isEmpty else {
            throw AppSettingsError.customFeedRequiresContent
        }

        let normalizedID = feed.id
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return CustomFeedDefinition(
            id: normalizedID.isEmpty ? UUID().uuidString.lowercased() : normalizedID,
            name: normalizedName,
            iconSystemName: CustomFeedIconCatalog.normalizedIcon(feed.iconSystemName),
            hashtags: normalizedHashtags,
            authorPubkeys: normalizedAuthors,
            phrases: normalizedPhrases
        )
    }

    nonisolated private static func normalizedCustomFeeds(_ feeds: [CustomFeedDefinition]) -> [CustomFeedDefinition] {
        var seen = Set<String>()
        var ordered: [CustomFeedDefinition] = []

        for feed in feeds {
            guard let normalizedFeed = try? normalizedCustomFeed(feed) else { continue }
            guard seen.insert(normalizedFeed.id).inserted else { continue }
            ordered.append(normalizedFeed)
        }

        return ordered
    }

    nonisolated private static func normalizedIdentifier(_ raw: String) -> String {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if trimmed.hasPrefix("nostr:") {
            return String(trimmed.dropFirst("nostr:".count))
        }

        return trimmed
    }
}
