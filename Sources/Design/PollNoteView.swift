import SwiftUI

struct PollNoteView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var relaySettings: RelaySettingsStore

    let event: NostrEvent
    let poll: NostrPollMetadata

    @State private var selectedOptionIDs = Set<String>()
    @State private var isSubmittingVote = false
    @State private var feedbackMessage: String?
    @State private var feedbackIsError = false
    @State private var resultsSnapshot = PollResultsSnapshot.empty

    private let resultsStore = PollResultsStore.shared
    private let votePublishService = PollVotePublishService()
    private static let prioritizedAutoLoadDelayNanos: UInt64 = 180_000_000
    private static let deferredAutoLoadDelayNanos: UInt64 = 650_000_000

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            if let subtitleText {
                Text(subtitleText)
                    .font(.footnote)
                    .foregroundStyle(pollMetadataForeground)
            }

            VStack(spacing: 8) {
                ForEach(poll.options) { option in
                    optionButton(for: option)
                }
            }

            footerRow

            if let feedbackMessage, !feedbackMessage.isEmpty {
                Text(feedbackMessage)
                    .font(.footnote)
                    .foregroundStyle(feedbackIsError ? .red : pollMetadataForeground)
            }

            if poll.format == .nip88, canSelectOptions {
                Button {
                    Task {
                        await submitVote()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSubmittingVote {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Vote")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmitVote)
                .opacity(canSubmitVote ? 1 : 0.45)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(pollCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(pollCardBorder, lineWidth: 0.8)
        )
        .onReceive(resultsStore.publisher(for: event.id)) { snapshot in
            resultsSnapshot = snapshot
        }
        .task(id: taskIdentifier) {
            resultsSnapshot = resultsStore.snapshot(for: event.id)
            await scheduleResultsLoadIfNeeded()
        }
    }

    private var taskIdentifier: String {
        "\(event.id.lowercased())|\(poll.endsAt ?? 0)|\(currentPubkey ?? "anon")"
    }

    private var currentPubkey: String? {
        let normalized = auth.currentAccount?.pubkey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    private var currentNsec: String? {
        auth.currentNsec?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var pollResults: NostrPollResults? {
        resultsSnapshot.results
    }

    private var isLoadingResults: Bool {
        resultsSnapshot.isLoading
    }

    private var votedOptionIDs: Set<String> {
        Set(pollResults?.selectedOptionIDs(for: currentPubkey) ?? [])
    }

    private var isExpired: Bool {
        guard let endsAt = poll.endsAt else { return false }
        return Int(Date().timeIntervalSince1970) > endsAt
    }

    private var isAuthoredByCurrentUser: Bool {
        currentPubkey == event.pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var hasVoted: Bool {
        !votedOptionIDs.isEmpty
    }

    private var canSelectOptions: Bool {
        poll.format == .nip88 && !isExpired && !hasVoted
    }

    private var canSubmitVote: Bool {
        canSelectOptions &&
        !selectedOptionIDs.isEmpty &&
        currentNsec != nil &&
        !isSubmittingVote
    }

    private var shouldShowResults: Bool {
        poll.isLegacyZapPoll || isAuthoredByCurrentUser || hasVoted || isExpired
    }

    private var subtitleText: String? {
        var lines: [String] = []

        if poll.pollType.allowsMultipleChoices {
            lines.append("Select one or more options.")
        }

        if poll.isLegacyZapPoll {
            lines.append("Zap poll voting isn't supported in Halo yet.")
        } else if currentNsec == nil && !hasVoted && !isExpired {
            lines.append("Sign in with a private key to vote.")
        }

        if let endsAt = poll.endsAt {
            let endDate = Date(timeIntervalSince1970: TimeInterval(endsAt))
            let formattedDate = endDate.formatted(date: .abbreviated, time: .shortened)
            lines.append(isExpired ? "Ended \(formattedDate)" : "Ends \(formattedDate)")
        }

        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: " ")
    }

    private var shouldShowRefreshControl: Bool {
        poll.format == .nip88 && (isAuthoredByCurrentUser || hasVoted || isExpired)
    }

    private var shouldAutoLoadResults: Bool {
        guard poll.format == .nip88 else { return false }
        if isExpired || isAuthoredByCurrentUser || hasVoted {
            return true
        }
        return currentPubkey != nil
    }

    private var autoLoadDelayNanos: UInt64 {
        if isExpired || isAuthoredByCurrentUser || hasVoted {
            return Self.prioritizedAutoLoadDelayNanos
        }
        return Self.deferredAutoLoadDelayNanos
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            badgeRow

            Spacer(minLength: 0)

            if shouldShowRefreshControl {
                refreshButton
            }
        }
    }

    private var badgeRow: some View {
        HStack(spacing: 8) {
            if isExpired {
                statusBadge(
                    "Ended",
                    foregroundColor: .orange,
                    backgroundColor: Color.orange.opacity(0.14)
                )
            } else if hasVoted {
                statusBadge(
                    "Voted",
                    foregroundColor: .accentColor,
                    backgroundColor: Color.accentColor.opacity(0.14)
                )
            } else {
                statusBadge(
                    "Open",
                    foregroundColor: .green,
                    backgroundColor: Color.green.opacity(0.14)
                )
            }

            if poll.pollType.allowsMultipleChoices {
                statusBadge(
                    "Multiple Choice",
                    foregroundColor: pollNeutralBadgeForeground,
                    backgroundColor: pollNeutralBadgeBackground
                )
            }

            if poll.isLegacyZapPoll {
                statusBadge(
                    "Zap Poll",
                    foregroundColor: .orange,
                    backgroundColor: Color.orange.opacity(0.14)
                )
            }
        }
    }

    private var refreshButton: some View {
        Button {
            Task {
                await refreshResults()
            }
        } label: {
            Group {
                if isLoadingResults {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
            }
            .foregroundStyle(pollRefreshButtonForeground)
            .frame(width: 30, height: 30)
            .background(
                Circle()
                    .fill(pollRefreshButtonBackground)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoadingResults)
        .accessibilityLabel("Refresh poll results")
        .accessibilityHint("Fetch the latest votes from the poll's relays.")
    }

    private func statusBadge(
        _ text: String,
        foregroundColor: Color,
        backgroundColor: Color
    ) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(backgroundColor)
            )
    }

    private func optionButton(for option: NostrPollOption) -> some View {
        let voteCount = pollResults?.voteCount(for: option.id) ?? 0
        let fillFraction = shouldShowResults ? (pollResults?.fraction(for: option.id) ?? 0) : 0
        let isWinningOption = shouldShowResults && (pollResults?.winningOptionIDs.contains(option.id) ?? false)
        let isSelectedForSubmission = selectedOptionIDs.contains(option.id)
        let isSelectedInExistingVote = votedOptionIDs.contains(option.id)
        let isHighlighted = isSelectedForSubmission || isSelectedInExistingVote

        return Button {
            toggleSelection(for: option.id)
        } label: {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(pollOptionBackground)

                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(fillColor(isWinningOption: isWinningOption, isHighlighted: isHighlighted))
                        .frame(
                            width: max(
                                proxy.size.width * fillFraction,
                                shouldShowResults ? 0 : (isSelectedForSubmission ? 52 : 0)
                            )
                        )
                }
                .allowsHitTesting(false)

                HStack(alignment: .center, spacing: 10) {
                    if let imageURL = option.imageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(pollImagePlaceholderBackground)
                                    .overlay {
                                        Image(systemName: "photo")
                                            .foregroundStyle(pollImagePlaceholderForeground)
                                    }
                            }
                        }
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.label)
                            .font(.subheadline.weight(isWinningOption ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if shouldShowResults {
                            Text("\(voteCount) vote\(voteCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(pollMetadataForeground)
                        }
                    }

                    if isSelectedInExistingVote {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                    } else if shouldShowResults {
                        Text(fillFraction.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isWinningOption ? appSettings.primaryColor : pollMetadataForeground)
                    } else {
                        Image(systemName: isSelectedForSubmission ? "checkmark.circle.fill" : "circle")
                            .font(.headline)
                            .foregroundStyle(isSelectedForSubmission ? Color.accentColor : pollMetadataForeground)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            }
            .frame(minHeight: 58)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        borderColor(
                            isWinningOption: isWinningOption,
                            isHighlighted: isHighlighted
                        ),
                        lineWidth: 0.8
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSelectOptions)
    }

    private var footerRow: some View {
        HStack(spacing: 10) {
            Text("\((pollResults?.totalVotes ?? 0)) vote\((pollResults?.totalVotes ?? 0) == 1 ? "" : "s")")
                .font(.footnote)
                .foregroundStyle(pollMetadataForeground)

            Spacer(minLength: 0)

            if isLoadingResults {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func fillColor(
        isWinningOption: Bool,
        isHighlighted: Bool
    ) -> Color {
        if shouldShowResults {
            return isWinningOption
                ? (appSettings.themePalette.pollStyle?.optionWinningBackground ?? Color.accentColor.opacity(0.20))
                : (appSettings.themePalette.pollStyle?.optionResultBackground ?? Color(.quaternarySystemFill))
        }
        if isHighlighted {
            return appSettings.themePalette.pollStyle?.optionSelectedBackground ?? Color.accentColor.opacity(0.18)
        }
        return .clear
    }

    private func borderColor(
        isWinningOption: Bool,
        isHighlighted: Bool
    ) -> Color {
        if shouldShowResults, isWinningOption {
            return appSettings.themePalette.pollStyle?.optionWinningBorder ?? Color.accentColor.opacity(0.35)
        }
        if isHighlighted {
            return appSettings.themePalette.pollStyle?.optionSelectedBorder ?? Color.accentColor.opacity(0.42)
        }
        return appSettings.themePalette.pollStyle?.optionBorder ?? Color(.separator).opacity(0.22)
    }

    private var pollCardBackground: Color {
        appSettings.themePalette.pollStyle?.cardBackground ?? Color(.secondarySystemBackground)
    }

    private var pollCardBorder: Color {
        appSettings.themePalette.pollStyle?.cardBorder ?? Color(.separator).opacity(0.28)
    }

    private var pollMetadataForeground: Color {
        appSettings.themePalette.pollStyle?.metadataForeground ?? .secondary
    }

    private var pollOptionBackground: Color {
        appSettings.themePalette.pollStyle?.optionBackground ?? Color(.tertiarySystemFill)
    }

    private var pollImagePlaceholderBackground: Color {
        appSettings.themePalette.pollStyle?.imagePlaceholderBackground ?? Color(.quaternarySystemFill)
    }

    private var pollImagePlaceholderForeground: Color {
        appSettings.themePalette.pollStyle?.imagePlaceholderForeground ?? .secondary
    }

    private var pollNeutralBadgeBackground: Color {
        appSettings.themePalette.pollStyle?.neutralBadgeBackground ?? Color(.tertiarySystemFill)
    }

    private var pollNeutralBadgeForeground: Color {
        appSettings.themePalette.pollStyle?.neutralBadgeForeground ?? .secondary
    }

    private var pollRefreshButtonBackground: Color {
        appSettings.themePalette.pollStyle?.refreshButtonBackground ?? Color(.tertiarySystemFill)
    }

    private var pollRefreshButtonForeground: Color {
        appSettings.themePalette.pollStyle?.refreshButtonForeground ?? .secondary
    }

    private func toggleSelection(for optionID: String) {
        guard canSelectOptions else { return }

        feedbackMessage = nil
        feedbackIsError = false

        if poll.pollType.allowsMultipleChoices {
            if selectedOptionIDs.contains(optionID) {
                selectedOptionIDs.remove(optionID)
            } else {
                selectedOptionIDs.insert(optionID)
            }
            return
        }

        if selectedOptionIDs.contains(optionID) {
            selectedOptionIDs.remove(optionID)
        } else {
            selectedOptionIDs = [optionID]
        }
    }

    private func loadResultsIfNeeded() async {
        guard poll.format == .nip88 else { return }
        await resultsStore.loadResultsIfNeeded(
            for: event,
            poll: poll,
            relayURLs: effectiveReadRelayURLs
        )
    }

    private func scheduleResultsLoadIfNeeded() async {
        guard shouldAutoLoadResults else { return }

        do {
            try await Task.sleep(nanoseconds: autoLoadDelayNanos)
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        await loadResultsIfNeeded()
    }

    private func refreshResults() async {
        guard poll.format == .nip88 else { return }

        do {
            _ = try await resultsStore.refreshResults(
                for: event,
                poll: poll,
                relayURLs: effectiveReadRelayURLs
            )
        } catch {
            feedbackMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            feedbackIsError = true
        }
    }

    private func submitVote() async {
        guard poll.format == .nip88 else { return }
        guard !selectedOptionIDs.isEmpty else {
            feedbackMessage = PollVotePublishError.missingSelection.errorDescription
            feedbackIsError = true
            return
        }
        guard let currentNsec else {
            feedbackMessage = PollVotePublishError.missingPrivateKey.errorDescription
            feedbackIsError = true
            return
        }
        guard let currentPubkey else {
            feedbackMessage = PollVotePublishError.missingPrivateKey.errorDescription
            feedbackIsError = true
            return
        }

        isSubmittingVote = true
        defer {
            isSubmittingVote = false
        }

        do {
            let latestResults = try await resultsStore.refreshResults(
                for: event,
                poll: poll,
                relayURLs: effectiveReadRelayURLs
            )
            if !latestResults.selectedOptionIDs(for: currentPubkey).isEmpty {
                selectedOptionIDs.removeAll()
                feedbackMessage = "You've already voted in this poll."
                feedbackIsError = false
                return
            }

            _ = try await votePublishService.publishVote(
                pollEvent: event,
                selectedOptionIDs: Array(selectedOptionIDs),
                currentNsec: currentNsec,
                relayURLs: effectiveVoteRelayURLs
            )
            resultsStore.applyOptimisticVote(
                pollEventID: event.id,
                poll: poll,
                pubkey: currentPubkey,
                selectedOptionIDs: Array(selectedOptionIDs)
            )
            selectedOptionIDs.removeAll()
            feedbackMessage = "Vote submitted."
            feedbackIsError = false
        } catch {
            feedbackMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            feedbackIsError = true
        }
    }

    private var effectiveReadRelayURLs: [URL] {
        appSettings.effectiveReadRelayURLs(from: relaySettings.readRelayURLs)
    }

    private var effectiveVoteRelayURLs: [URL] {
        if !poll.relayURLs.isEmpty {
            return poll.relayURLs
        }
        return appSettings.effectiveWriteRelayURLs(
            from: relaySettings.writeRelayURLs,
            fallbackReadRelayURLs: effectiveReadRelayURLs
        )
    }
}
