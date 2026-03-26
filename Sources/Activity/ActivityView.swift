import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore

    @StateObject private var viewModel = ActivityViewModel()
    @State private var selectedThreadRoute: ActivityThreadRoute?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Activity filter", selection: $viewModel.selectedFilter) {
                        ForEach(ActivityFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .accessibilityLabel("Activity filter")
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                if viewModel.isLoading && viewModel.visibleItems.isEmpty {
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
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.large)
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
            .onChange(of: viewModel.selectedFilter) { _, _ in
                Task {
                    await viewModel.selectedFilterChanged()
                }
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
            .navigationDestination(item: $selectedThreadRoute) { route in
                ThreadDetailView(
                    initialItem: route.initialItem,
                    relayURL: viewModel.primaryRelayURL,
                    readRelayURLs: effectiveReadRelayURLs,
                    initialReplyScrollTargetID: route.initialReplyScrollTargetID
                )
            }
        }
    }

    private var effectiveReadRelayURLs: [URL] {
        appSettings.effectiveReadRelayURLs(from: relaySettings.readRelayURLs)
    }

    private var emptyStateRow: some View {
        VStack(spacing: 6) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
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

    private func threadRoute(for item: ActivityRow) -> ActivityThreadRoute? {
        switch item.action {
        case .mention:
            if item.event.isReplyNote {
                let destinationEvent = item.target.event ?? item.event
                let shouldScrollToReply = destinationEvent.id.lowercased() != item.event.id.lowercased()
                return ActivityThreadRoute(
                    initialItem: FeedItem(event: destinationEvent, profile: nil),
                    initialReplyScrollTargetID: shouldScrollToReply ? item.event.id.lowercased() : nil
                )
            }

            return ActivityThreadRoute(
                initialItem: FeedItem(event: item.event, profile: nil),
                initialReplyScrollTargetID: nil
            )

        case .reaction:
            guard let destinationEvent = item.target.event else { return nil }
            return ActivityThreadRoute(
                initialItem: FeedItem(event: destinationEvent, profile: nil),
                initialReplyScrollTargetID: nil
            )
        }
    }
}

private struct ActivityRowCell: View {
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
        case .reaction(let reaction):
            if let customEmojiURL = reaction.customEmojiImageURL {
                AsyncImage(url: customEmojiURL) { phase in
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
                .clipShape(Circle())
            } else {
                fallbackReactionSymbol(for: reaction)
            }
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
        case .mention:
            if let sourceSnippet, !sourceSnippet.isEmpty {
                return sourceSnippet
            }
            return targetSnippet
        case .reaction:
            return targetSnippet
        }
    }

    private var showsImagePill: Bool {
        switch item.action {
        case .mention:
            if item.event.hasMedia {
                return true
            }
            return previewText == nil && (item.target.event?.hasMedia ?? false)
        case .reaction:
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
