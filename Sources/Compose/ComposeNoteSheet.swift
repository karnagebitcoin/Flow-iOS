import AVFoundation
import AVKit
import ImageIO
import NostrSDK
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ComposeNoteViewModel: ObservableObject {
    @Published var text: String = ""
    @Published private(set) var isPublishing = false
    @Published var feedbackMessage: String?
    @Published var feedbackIsError = false

    private let publishingService: ComposeNotePublishService
    private let replyPublishingService: ThreadReplyPublishService

    init(
        publishingService: ComposeNotePublishService = ComposeNotePublishService(),
        replyPublishingService: ThreadReplyPublishService = ThreadReplyPublishService()
    ) {
        self.publishingService = publishingService
        self.replyPublishingService = replyPublishingService
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var characterCount: Int {
        trimmedText.count
    }

    func publish(
        currentAccountPubkey: String?,
        currentNsec: String?,
        writeRelayURLs: [URL],
        additionalTags: [[String]] = [],
        pollDraft: ComposePollDraft? = nil,
        replyTargetEvent: NostrEvent? = nil
    ) async -> Bool {
        guard !isPublishing else { return false }

        isPublishing = true
        feedbackMessage = nil
        feedbackIsError = false

        defer {
            isPublishing = false
        }

        do {
            if let replyTargetEvent {
                _ = try await replyPublishingService.publishReply(
                    content: text,
                    replyingTo: replyTargetEvent,
                    currentAccountPubkey: currentAccountPubkey,
                    currentNsec: currentNsec,
                    writeRelayURLs: writeRelayURLs,
                    additionalTags: additionalTags
                )
                text = ""
                feedbackMessage = "Reply posted."
                feedbackIsError = false
                return true
            } else if let pollDraft {
                _ = try await publishingService.publishPoll(
                    content: text,
                    poll: pollDraft,
                    currentNsec: currentNsec,
                    writeRelayURLs: writeRelayURLs,
                    additionalTags: additionalTags
                )

                text = ""
                feedbackMessage = "Poll posted."
                feedbackIsError = false
                return true
            } else {
                _ = try await publishingService.publishNote(
                    content: text,
                    currentNsec: currentNsec,
                    writeRelayURLs: writeRelayURLs,
                    additionalTags: additionalTags
                )

                text = ""
                feedbackMessage = "Posted."
                feedbackIsError = false
                return true
            }
        } catch {
            feedbackMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            feedbackIsError = true
            return false
        }
    }
}

struct ComposeMediaAttachment: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let imetaTag: [String]
    let mimeType: String
    let fileSizeBytes: Int?

    var isImage: Bool {
        let normalized = mimeType.lowercased()
        if normalized.hasPrefix("image/") {
            return true
        }
        return [".jpg", ".jpeg", ".png", ".webp", ".gif", ".heic", ".bmp", ".svg"]
            .contains { url.path.lowercased().hasSuffix($0) }
    }

    var isVideo: Bool {
        let normalized = mimeType.lowercased()
        if normalized.hasPrefix("video/") {
            return true
        }
        return [".mp4", ".mov", ".m4v", ".webm", ".mkv"]
            .contains { url.path.lowercased().hasSuffix($0) }
    }

    var isAudio: Bool {
        let normalized = mimeType.lowercased()
        if normalized.hasPrefix("audio/") {
            return true
        }
        return [".mp3", ".m4a", ".aac", ".wav", ".ogg"]
            .contains { url.path.lowercased().hasSuffix($0) }
    }

    var isGIF: Bool {
        let normalized = mimeType.lowercased()
        if normalized.contains("gif") {
            return true
        }
        return url.pathExtension.lowercased() == "gif"
    }
}

private struct CameraCapturePermissionSnapshot: Equatable {
    let cameraStatus: AVAuthorizationStatus
    let microphoneStatus: AVAuthorizationStatus

    static func current() -> CameraCapturePermissionSnapshot {
        CameraCapturePermissionSnapshot(
            cameraStatus: AVCaptureDevice.authorizationStatus(for: .video),
            microphoneStatus: AVCaptureDevice.authorizationStatus(for: .audio)
        )
    }

    var cameraRequiresPrompt: Bool {
        cameraStatus == .notDetermined
    }

    var microphoneRequiresPrompt: Bool {
        microphoneStatus == .notDetermined
    }

    var isCameraBlocked: Bool {
        cameraStatus == .denied || cameraStatus == .restricted
    }

    var isMicrophoneBlocked: Bool {
        microphoneStatus == .denied || microphoneStatus == .restricted
    }
}

private enum CapturedCameraMedia {
    case image(data: Data, mimeType: String, fileExtension: String)
    case video(fileURL: URL, mimeType: String, fileExtension: String)
}

private enum SharedComposeImportError: LocalizedError {
    case missingFileURL
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .missingFileURL:
            return "Couldn't access the shared media."
        case .unreadableFile:
            return "Couldn't read the shared media."
        }
    }
}

struct ComposeFloatingActionButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Compose note")
    }
}

enum ComposeNoteSheetMode: Equatable {
    case newNote
    case reply
    case quote

    init(hasReplyTarget: Bool, hasQuotedEvent: Bool) {
        if hasQuotedEvent {
            self = .quote
        } else if hasReplyTarget {
            self = .reply
        } else {
            self = .newNote
        }
    }

    var navigationTitle: String {
        switch self {
        case .newNote:
            return "Compose note"
        case .reply:
            return "Reply"
        case .quote:
            return "Quote"
        }
    }

    var publishButtonTitle: String {
        switch self {
        case .reply:
            return "Reply"
        case .newNote, .quote:
            return "Post"
        }
    }

    var placeholderText: String {
        switch self {
        case .newNote:
            return "What do you want to share?"
        case .reply:
            return "Post your reply"
        case .quote:
            return "Add your thoughts"
        }
    }

    var accessibilityActionLabel: String {
        switch self {
        case .newNote:
            return "Posting"
        case .reply:
            return "Replying"
        case .quote:
            return "Quoting"
        }
    }
}

struct ComposeNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var toastCenter: AppToastCenter
    @State private var isEditorFocused = false
    @StateObject private var viewModel = ComposeNoteViewModel()
    @StateObject private var speechTranscriber = ComposeSpeechTranscriber()
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var mediaAttachments: [ComposeMediaAttachment] = []
    @State private var capturePermissions = CameraCapturePermissionSnapshot.current()
    @State private var isShowingCapturePermissionSheet = false
    @State private var isShowingCameraCapture = false
    @State private var isRequestingCaptureAccess = false
    @State private var isUploadingMedia = false
    @State private var pollDraft: ComposePollDraft?
    @State private var profileDisplayName = "Account"
    @State private var profileAvatarURL: URL?
    @State private var profileFallbackSymbol = "A"
    @State private var replyTargetDisplayName: String?
    @State private var replyTargetHandle: String?
    @State private var replyTargetAvatarURL: URL?
    @State private var quotedDisplayName: String?
    @State private var quotedHandle: String?
    @State private var quotedAvatarURL: URL?
    @State private var hasAppliedInitialDraft = false
    @State private var hasAppliedInitialAttachments = false
    @State private var hasAppliedInitialSharedAttachments = false
    @State private var previewingMediaAttachment: ComposeMediaAttachment?
    @State private var isShowingKlipyGIFPicker = false

    private let mediaUploadService = MediaUploadService.shared
    private let klipyGIFService = KlipyGIFService.shared
    private let profileService = NostrFeedService()

    let currentAccountPubkey: String?
    let currentNsec: String?
    let writeRelayURLs: [URL]
    var initialText: String = ""
    var initialAdditionalTags: [[String]] = []
    var initialUploadedAttachments: [ComposeMediaAttachment] = []
    var initialSharedAttachments: [SharedComposeAttachment] = []
    var replyTargetEvent: NostrEvent? = nil
    var replyTargetDisplayNameHint: String? = nil
    var replyTargetHandleHint: String? = nil
    var replyTargetAvatarURLHint: URL? = nil
    var quotedEvent: NostrEvent? = nil
    var quotedDisplayNameHint: String? = nil
    var quotedHandleHint: String? = nil
    var quotedAvatarURLHint: URL? = nil
    var onPublished: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            standardComposerLayout
                .background(appSettings.themePalette.groupedBackground)
            .navigationTitle(composerNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    composeToolbarAvatar
                    publishToolbarButton
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(appSettings.themePalette.groupedBackground)
        .task {
            applyInitialDraftIfNeeded()
            applyInitialAttachmentsIfNeeded()
            await applyInitialSharedAttachmentsIfNeeded()
            isEditorFocused = true
            await refreshComposeAccountSummary()
            await refreshReplyTargetAuthorSummaryIfNeeded()
            await refreshQuotedAuthorSummaryIfNeeded()
        }
        .onDisappear {
            cleanupInitialSharedAttachments()
        }
        .onChange(of: selectedMediaItems) { _, newValue in
            guard !newValue.isEmpty else { return }
            let items = newValue
            selectedMediaItems = []
            Task {
                await handleMediaSelection(items)
            }
        }
        .onChange(of: currentAccountPubkey) { _, _ in
            Task {
                await refreshComposeAccountSummary()
            }
        }
        .sheet(isPresented: $isShowingCapturePermissionSheet) {
            CameraCapturePermissionSheet(
                permissions: capturePermissions,
                isRequestingAccess: isRequestingCaptureAccess,
                onContinue: {
                    Task {
                        await requestCameraCaptureAccess()
                    }
                },
                onOpenSettings: openSystemSettings,
                onCancel: {
                    isShowingCapturePermissionSheet = false
                }
            )
            .presentationDetents([.height(365)])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $isShowingCameraCapture) {
            CameraCaptureView(
                onCapture: { capturedMedia in
                    isShowingCameraCapture = false
                    Task {
                        await handleCapturedCameraMedia(capturedMedia)
                    }
                },
                onCancel: {
                    isShowingCameraCapture = false
                }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $previewingMediaAttachment) { attachment in
            ComposeMediaAttachmentPreviewSheet(attachment: attachment)
        }
        .sheet(isPresented: $isShowingKlipyGIFPicker) {
            ComposeKlipyGIFPickerSheet(currentAccountPubkey: currentAccountPubkey) { selection in
                Task {
                    await handleKlipyGIFSelection(selection)
                }
            }
        }
    }

    private var mode: ComposeNoteSheetMode {
        ComposeNoteSheetMode(
            hasReplyTarget: replyTargetEvent != nil,
            hasQuotedEvent: quotedEvent != nil
        )
    }

    private var isQuoteComposer: Bool {
        mode == .quote
    }

    private var isReplyComposer: Bool {
        mode == .reply
    }

    private var composerNavigationTitle: String {
        mode.navigationTitle
    }

    private var publishButtonTitle: String {
        mode.publishButtonTitle
    }

    private var standardComposerLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isReplyComposer {
                    replyTargetPreviewCard
                } else if isQuoteComposer {
                    quotePreviewCard
                }
                composeCard
                statusSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var publishToolbarButton: some View {
        Button {
            Task {
                await publish()
            }
        } label: {
            Group {
                if viewModel.isPublishing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Text(publishButtonTitle)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(appSettings.primaryGradient, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canPublish)
        .opacity(canPublish ? 1 : 0.45)
    }

    private var composeToolbarAvatar: some View {
        composeAvatar(size: 34)
            .overlay {
                Circle()
                    .stroke(appSettings.themePalette.separator.opacity(0.22), lineWidth: 0.8)
            }
            .accessibilityLabel("\(mode.accessibilityActionLabel) as \(profileDisplayName)")
    }

    private var composeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if viewModel.text.isEmpty {
                    Text(mode.placeholderText)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                }

                composeTextView(horizontalPadding: 8, verticalPadding: 8)
                    .frame(minHeight: 180)
            }
            .background(appSettings.themePalette.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            if !mediaAttachments.isEmpty {
                mediaAttachmentPreviewList
            }

            if let _ = pollDraft, canAttachPoll {
                ComposePollEditorView(
                    draft: pollDraftBinding,
                    onRemove: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            pollDraft = nil
                        }
                    }
                )
            }

            HStack {
                PhotosPicker(
                    selection: $selectedMediaItems,
                    selectionBehavior: .ordered,
                    matching: .any(of: [.images, .videos])
                ) {
                    Group {
                        if isUploadingMedia {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 18, weight: .medium))
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isUploadingMedia || viewModel.isPublishing)

                cameraAttachmentButton(symbolFont: .system(size: 18, weight: .medium))

                Button {
                    isShowingKlipyGIFPicker = true
                } label: {
                    Text("GIF")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(appSettings.themePalette.tertiaryFill)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isUploadingMedia || viewModel.isPublishing)

                Button {
                    Task {
                        await handleSpeechToggle()
                    }
                } label: {
                    Group {
                        if speechTranscriber.isRecording {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 15, weight: .semibold))
                        } else if speechTranscriber.isTranscribing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "waveform")
                                .font(.system(size: 17, weight: .medium))
                        }
                    }
                    .foregroundStyle(speechTranscriber.isRecording ? Color.white : Color.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        speechTranscriber.isRecording ? Color.accentColor : appSettings.themePalette.tertiaryFill,
                        in: Circle()
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isPublishing || isUploadingMedia)

                if canAttachPoll {
                    Button {
                        togglePollDraft()
                    } label: {
                        Image(systemName: pollDraft == nil ? "chart.bar.xaxis" : "chart.bar.fill")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(pollDraft == nil ? Color.secondary : Color.white)
                            .frame(width: 32, height: 32)
                            .background(
                                pollDraft == nil ? appSettings.themePalette.tertiaryFill : appSettings.primaryColor,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isPublishing || isUploadingMedia)
                    .accessibilityLabel(pollDraft == nil ? "Add poll" : "Edit poll")
                }

                if speechTranscriber.isRecording {
                    Text(formatVoiceDuration(milliseconds: speechTranscriber.elapsedMs))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(viewModel.characterCount) characters")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if currentNsec == nil {
                    Label("nsec required", systemImage: "lock.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if writeRelayURLs.isEmpty {
                    Label("No publish sources", systemImage: "wifi.slash")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusSection: some View {
        Group {
            if viewModel.isPublishing {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Posting to \(configuredPublishSourceCount) source\(configuredPublishSourceCount == 1 ? "" : "s")...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 2)
            } else if let feedbackMessage = viewModel.feedbackMessage, !feedbackMessage.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: viewModel.feedbackIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(viewModel.feedbackIsError ? .red : .green)

                    Text(feedbackMessage)
                        .font(.footnote)
                        .foregroundStyle(viewModel.feedbackIsError ? .red : .secondary)

                    Spacer()
                }
                .padding(12)
                .background(
                    (viewModel.feedbackIsError ? Color.red.opacity(0.08) : Color.green.opacity(0.08)),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            } else if speechTranscriber.isTranscribing {
                infoBanner(
                    systemImage: "waveform.badge.magnifyingglass",
                    text: "Transcribing speech..."
                )
            } else if currentNsec == nil {
                infoBanner(
                    systemImage: "lock.fill",
                    text: "This account can read feeds, but it needs an nsec to publish notes."
                )
            } else if writeRelayURLs.isEmpty {
                infoBanner(
                    systemImage: "wifi.slash",
                    text: "Add at least one publish source to post notes."
                )
            } else if let pollValidationMessage {
                infoBanner(
                    systemImage: "chart.bar.xaxis",
                    text: pollValidationMessage
                )
            }
        }
    }

    @ViewBuilder
    private func composeTextView(horizontalPadding: CGFloat, verticalPadding: CGFloat) -> some View {
        ComposeMultilineTextView(
            text: $viewModel.text,
            isFocused: $isEditorFocused
        )
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
    }

    private var canPublish: Bool {
        let baseIsReadyToPublish =
            currentNsec != nil &&
            !writeRelayURLs.isEmpty &&
            !speechTranscriber.isRecording &&
            !speechTranscriber.isTranscribing &&
            !viewModel.isPublishing

        guard baseIsReadyToPublish else { return false }

        if let pollDraft {
            return !viewModel.trimmedText.isEmpty && pollDraft.hasMinimumOptions
        }

        return !viewModel.trimmedText.isEmpty || !mediaAttachments.isEmpty || quotedEvent != nil
    }

    private var canAttachPoll: Bool {
        mode == .newNote
    }

    private var pollDraftBinding: Binding<ComposePollDraft> {
        Binding(
            get: { pollDraft ?? .defaultDraft() },
            set: { pollDraft = $0 }
        )
    }

    private var pollValidationMessage: String? {
        guard let pollDraft else { return nil }
        if viewModel.trimmedText.isEmpty {
            return "Polls need a question."
        }
        if !pollDraft.hasMinimumOptions {
            return "Add at least two option labels before posting."
        }
        return nil
    }

    private func composeAvatar(size: CGFloat) -> some View {
        Group {
            if let profileAvatarURL {
                AsyncImage(url: profileAvatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        composeAvatarFallback
                    }
                }
            } else {
                composeAvatarFallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var composeAvatarFallback: some View {
        ZStack {
            Circle().fill(appSettings.themePalette.secondaryFill)
            Text(String(profileFallbackSymbol.prefix(1)).uppercased())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var quotedAvatarFallback: some View {
        ZStack {
            Circle().fill(appSettings.themePalette.secondaryFill)
            Text(String(quotedDisplayNameResolved.prefix(1)).uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var replyTargetAvatarFallback: some View {
        ZStack {
            Circle().fill(appSettings.themePalette.secondaryFill)
            Text(String(replyTargetDisplayNameResolved.prefix(1)).uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var renderedReplyTargetEvent: NostrEvent? {
        guard let replyTargetEvent else { return nil }
        return Self.renderEventForQuotePreview(replyTargetEvent)
    }

    private var replyTargetDisplayNameResolved: String {
        if let replyTargetDisplayName {
            let trimmed = replyTargetDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        if let event = renderedReplyTargetEvent {
            return String(event.pubkey.prefix(8))
        }
        return "Reply target"
    }

    private var replyTargetHandleResolved: String {
        if let replyTargetHandle {
            let trimmed = replyTargetHandle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
            }
        }
        if let event = renderedReplyTargetEvent {
            return "@\(String(event.pubkey.prefix(8)).lowercased())"
        }
        return "@unknown"
    }

    private var quotedDisplayNameResolved: String {
        if let quotedDisplayName {
            let trimmed = quotedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        if let event = renderedQuotedEvent {
            return String(event.pubkey.prefix(8))
        }
        return "Quoted note"
    }

    private var quotedHandleResolved: String {
        if let quotedHandle {
            let trimmed = quotedHandle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
            }
        }
        if let event = renderedQuotedEvent {
            return "@\(String(event.pubkey.prefix(8)).lowercased())"
        }
        return "@unknown"
    }

    private var renderedQuotedEvent: NostrEvent? {
        guard let quotedEvent else { return nil }
        return Self.renderEventForQuotePreview(quotedEvent)
    }

    private var replyTargetPreviewText: String {
        guard let event = renderedReplyTargetEvent else { return "" }
        return Self.previewText(for: event)
    }

    private var quotedPreviewText: String {
        guard let event = renderedQuotedEvent else { return "" }
        return Self.previewText(for: event, maximumLength: 220)
    }

    private var replyTargetPreviewImageURLs: [URL] {
        guard let event = renderedReplyTargetEvent else { return [] }
        return Self.previewImageURLs(for: event)
    }

    private var quotedPreviewImageURLs: [URL] {
        guard let event = renderedQuotedEvent else { return [] }
        return Self.previewImageURLs(for: event)
    }

    private var replyTargetHasVideo: Bool {
        guard let event = renderedReplyTargetEvent else { return false }
        return Self.previewHasVideo(for: event)
    }

    private var replyTargetHasAudio: Bool {
        guard let event = renderedReplyTargetEvent else { return false }
        return Self.previewHasAudio(for: event)
    }

    private var hasQuotedVideo: Bool {
        guard let event = renderedQuotedEvent else { return false }
        return Self.previewHasVideo(for: event)
    }

    private var hasQuotedAudio: Bool {
        guard let event = renderedQuotedEvent else { return false }
        return Self.previewHasAudio(for: event)
    }

    private var replyTargetPreviewCard: some View {
        Group {
            if let event = renderedReplyTargetEvent {
                composerContextPreviewCard(
                    title: "Replying to",
                    event: event,
                    displayName: replyTargetDisplayNameResolved,
                    handle: replyTargetHandleResolved,
                    avatarURL: replyTargetAvatarURL,
                    previewText: replyTargetPreviewText,
                    imageURLs: replyTargetPreviewImageURLs,
                    hasVideo: replyTargetHasVideo,
                    hasAudio: replyTargetHasAudio,
                    videoSummary: "Note includes video",
                    audioSummary: "Note includes audio"
                ) {
                    replyTargetAvatarFallback
                }
            }
        }
    }

    private var quotePreviewCard: some View {
        Group {
            if let event = renderedQuotedEvent {
                composerContextPreviewCard(
                    title: "Quoting",
                    event: event,
                    displayName: quotedDisplayNameResolved,
                    handle: quotedHandleResolved,
                    avatarURL: quotedAvatarURL,
                    previewText: quotedPreviewText,
                    imageURLs: quotedPreviewImageURLs,
                    hasVideo: hasQuotedVideo,
                    hasAudio: hasQuotedAudio,
                    videoSummary: "Quoted note includes video",
                    audioSummary: "Quoted note includes audio"
                ) {
                    quotedAvatarFallback
                }
            }
        }
    }

    @ViewBuilder
    private func composerContextPreviewCard<Fallback: View>(
        title: String,
        event: NostrEvent,
        displayName: String,
        handle: String,
        avatarURL: URL?,
        previewText: String,
        imageURLs: [URL],
        hasVideo: Bool,
        hasAudio: Bool,
        videoSummary: String,
        audioSummary: String,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 10) {
                composerContextAvatar(avatarURL: avatarURL, fallback: fallback)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Text(handle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Text(RelativeTimestampFormatter.shortString(from: event.createdAtDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(previewText)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    composerContextPreviewMedia(
                        imageURLs: imageURLs,
                        hasVideo: hasVideo,
                        hasAudio: hasAudio,
                        videoSummary: videoSummary,
                        audioSummary: audioSummary
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(appSettings.themePalette.secondaryBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(appSettings.themePalette.separator.opacity(0.3), lineWidth: 0.8)
        )
    }

    @ViewBuilder
    private func composerContextAvatar<Fallback: View>(
        avatarURL: URL?,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) -> some View {
        Group {
            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback()
                    }
                }
            } else {
                fallback()
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
    }

    @ViewBuilder
    private func composerContextPreviewMedia(
        imageURLs: [URL],
        hasVideo: Bool,
        hasAudio: Bool,
        videoSummary: String,
        audioSummary: String
    ) -> some View {
        if !imageURLs.isEmpty {
            HStack(spacing: 8) {
                ForEach(Array(imageURLs.enumerated()), id: \.offset) { _, url in
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            appSettings.themePalette.tertiaryFill
                                .overlay {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                }
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(appSettings.themePalette.tertiaryFill)
                        @unknown default:
                            appSettings.themePalette.tertiaryFill
                        }
                    }
                    .frame(height: 170)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        } else if hasVideo || hasAudio {
            HStack(spacing: 8) {
                Image(systemName: hasVideo ? "video" : "waveform")
                Text(hasVideo ? videoSummary : audioSummary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(appSettings.themePalette.tertiaryFill)
            )
        }
    }

    private var mediaAttachmentPreviewList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(mediaAttachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        CompactMediaAttachmentPreview(
                            url: attachment.url,
                            mimeType: attachment.mimeType,
                            fileSizeBytes: attachment.fileSizeBytes,
                            colorScheme: colorScheme,
                            onTap: {
                                previewingMediaAttachment = attachment
                            }
                        )

                        Button {
                            removeMediaAttachment(attachment)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove attachment")
                    }
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 1)
        }
    }

    private func cameraAttachmentButton(symbolFont: Font) -> some View {
        Button {
            handleCameraButtonTap()
        } label: {
            Image(systemName: "camera")
                .font(symbolFont)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(isUploadingMedia || viewModel.isPublishing || isRequestingCaptureAccess)
        .accessibilityLabel("Capture photo or video")
    }

    private func infoBanner(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(12)
        .background(appSettings.themePalette.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func refreshComposeAccountSummary() async {
        guard let currentAccountPubkey else {
            profileDisplayName = "Account"
            profileAvatarURL = nil
            profileFallbackSymbol = "A"
            return
        }

        let normalizedPubkey = currentAccountPubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedPubkey.isEmpty else { return }

        let fallbackIdentifier = shortNostrIdentifier(normalizedPubkey)
        profileDisplayName = fallbackIdentifier
        profileAvatarURL = nil
        profileFallbackSymbol = String(fallbackIdentifier.prefix(1)).uppercased()

        if let cachedProfile = await profileService.cachedProfile(pubkey: normalizedPubkey) {
            applyComposeProfile(cachedProfile, pubkey: normalizedPubkey)
        }

        let readRelayURLs = RelaySettingsStore.shared.readRelayURLs
        let fallbackRelayURLs = RelaySettingsStore.defaultReadRelayURLs.compactMap(URL.init(string:))
        let relayTargets = readRelayURLs.isEmpty ? fallbackRelayURLs : readRelayURLs
        guard !relayTargets.isEmpty else { return }

        if let fetchedProfile = await profileService.fetchProfile(relayURLs: relayTargets, pubkey: normalizedPubkey) {
            applyComposeProfile(fetchedProfile, pubkey: normalizedPubkey)
        }
    }

    private func applyComposeProfile(_ profile: NostrProfile, pubkey: String) {
        if let displayName = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            profileDisplayName = displayName
        } else if let name = profile.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            profileDisplayName = name
        } else {
            profileDisplayName = String(pubkey.prefix(8))
        }

        profileFallbackSymbol = String(profileDisplayName.prefix(1)).uppercased()

        if let picture = profile.picture?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: picture),
           url.scheme != nil {
            profileAvatarURL = url
        } else {
            profileAvatarURL = nil
        }
    }

    private func refreshReplyTargetAuthorSummaryIfNeeded() async {
        guard let replyTargetEvent else { return }

        if let replyTargetDisplayNameHint {
            let trimmed = replyTargetDisplayNameHint.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                replyTargetDisplayName = trimmed
            }
        }

        if let replyTargetHandleHint {
            let trimmed = replyTargetHandleHint.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                replyTargetHandle = trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
            }
        }

        if let replyTargetAvatarURLHint {
            replyTargetAvatarURL = replyTargetAvatarURLHint
        }

        let normalizedPubkey = replyTargetEvent.pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedPubkey.isEmpty else { return }

        if let cachedProfile = await profileService.cachedProfile(pubkey: normalizedPubkey) {
            applyReplyTargetProfile(cachedProfile, pubkey: normalizedPubkey)
        }

        let readRelayURLs = RelaySettingsStore.shared.readRelayURLs
        let fallbackRelayURLs = RelaySettingsStore.defaultReadRelayURLs.compactMap(URL.init(string:))
        let relayTargets = readRelayURLs.isEmpty ? fallbackRelayURLs : readRelayURLs
        guard !relayTargets.isEmpty else { return }

        if let fetchedProfile = await profileService.fetchProfile(relayURLs: relayTargets, pubkey: normalizedPubkey) {
            applyReplyTargetProfile(fetchedProfile, pubkey: normalizedPubkey)
        } else {
            if replyTargetDisplayName == nil {
                replyTargetDisplayName = String(normalizedPubkey.prefix(8))
            }
            if replyTargetHandle == nil {
                replyTargetHandle = "@\(String(normalizedPubkey.prefix(8)).lowercased())"
            }
        }
    }

    private func applyReplyTargetProfile(_ profile: NostrProfile, pubkey: String) {
        if let displayName = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            replyTargetDisplayName = displayName
        } else if let name = profile.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            replyTargetDisplayName = name
        } else if replyTargetDisplayName == nil {
            replyTargetDisplayName = String(pubkey.prefix(8))
        }

        let handleSeed = (profile.name ?? profile.displayName ?? String(pubkey.prefix(8)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        if !handleSeed.isEmpty {
            replyTargetHandle = "@\(handleSeed)"
        } else if replyTargetHandle == nil {
            replyTargetHandle = "@\(String(pubkey.prefix(8)).lowercased())"
        }

        if let picture = profile.picture?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: picture),
           url.scheme != nil {
            replyTargetAvatarURL = url
        }
    }

    private func refreshQuotedAuthorSummaryIfNeeded() async {
        guard let quotedEvent else { return }

        if let quotedDisplayNameHint {
            let trimmed = quotedDisplayNameHint.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                quotedDisplayName = trimmed
            }
        }

        if let quotedHandleHint {
            let trimmed = quotedHandleHint.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                quotedHandle = trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
            }
        }

        if let quotedAvatarURLHint {
            quotedAvatarURL = quotedAvatarURLHint
        }

        let normalizedPubkey = quotedEvent.pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedPubkey.isEmpty else { return }

        if let cachedProfile = await profileService.cachedProfile(pubkey: normalizedPubkey) {
            applyQuotedProfile(cachedProfile, pubkey: normalizedPubkey)
        }

        let readRelayURLs = RelaySettingsStore.shared.readRelayURLs
        let fallbackRelayURLs = RelaySettingsStore.defaultReadRelayURLs.compactMap(URL.init(string:))
        let relayTargets = readRelayURLs.isEmpty ? fallbackRelayURLs : readRelayURLs
        guard !relayTargets.isEmpty else { return }

        if let fetchedProfile = await profileService.fetchProfile(relayURLs: relayTargets, pubkey: normalizedPubkey) {
            applyQuotedProfile(fetchedProfile, pubkey: normalizedPubkey)
        } else {
            if quotedDisplayName == nil {
                quotedDisplayName = String(normalizedPubkey.prefix(8))
            }
            if quotedHandle == nil {
                quotedHandle = "@\(String(normalizedPubkey.prefix(8)).lowercased())"
            }
        }
    }

    private func applyQuotedProfile(_ profile: NostrProfile, pubkey: String) {
        if let displayName = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            quotedDisplayName = displayName
        } else if let name = profile.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            quotedDisplayName = name
        } else if quotedDisplayName == nil {
            quotedDisplayName = String(pubkey.prefix(8))
        }

        let handleSeed = (profile.name ?? profile.displayName ?? String(pubkey.prefix(8)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        if !handleSeed.isEmpty {
            quotedHandle = "@\(handleSeed)"
        } else if quotedHandle == nil {
            quotedHandle = "@\(String(pubkey.prefix(8)).lowercased())"
        }

        if let picture = profile.picture?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: picture),
           url.scheme != nil {
            quotedAvatarURL = url
        }
    }

    private func handleCameraButtonTap() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            viewModel.feedbackMessage = "This device doesn't have an available camera right now."
            viewModel.feedbackIsError = true
            return
        }

        let permissions = CameraCapturePermissionSnapshot.current()
        capturePermissions = permissions

        if permissions.isCameraBlocked {
            isShowingCapturePermissionSheet = true
            return
        }

        if permissions.cameraRequiresPrompt || permissions.microphoneRequiresPrompt {
            isShowingCapturePermissionSheet = true
            return
        }

        presentCameraCapture(using: permissions)
    }

    private func requestCameraCaptureAccess() async {
        guard !isRequestingCaptureAccess else { return }
        isRequestingCaptureAccess = true
        defer { isRequestingCaptureAccess = false }

        var permissions = CameraCapturePermissionSnapshot.current()

        if permissions.cameraRequiresPrompt {
            _ = await requestCaptureAccess(for: .video)
            permissions = CameraCapturePermissionSnapshot.current()
        }

        guard !permissions.isCameraBlocked else {
            capturePermissions = permissions
            return
        }

        if permissions.microphoneRequiresPrompt {
            _ = await requestCaptureAccess(for: .audio)
            permissions = CameraCapturePermissionSnapshot.current()
        }

        capturePermissions = permissions
        isShowingCapturePermissionSheet = false
        presentCameraCapture(using: permissions)
    }

    private func requestCaptureAccess(for mediaType: AVMediaType) async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: mediaType) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func presentCameraCapture(using permissions: CameraCapturePermissionSnapshot) {
        capturePermissions = permissions

        if permissions.isMicrophoneBlocked {
            viewModel.feedbackMessage = "Microphone access is off. You can still take photos, but video capture with sound may be limited until you enable it in app settings."
            viewModel.feedbackIsError = false
        } else {
            viewModel.feedbackMessage = nil
            viewModel.feedbackIsError = false
        }

        isShowingCameraCapture = true
    }

    private func handleCapturedCameraMedia(_ capturedMedia: CapturedCameraMedia) async {
        guard !isUploadingMedia else { return }
        viewModel.feedbackMessage = nil
        viewModel.feedbackIsError = false

        guard let normalizedNsec = currentNsec?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalizedNsec.isEmpty else {
            viewModel.feedbackMessage = "Sign in with a private key to upload media."
            viewModel.feedbackIsError = true
            return
        }

        isUploadingMedia = true
        defer {
            isUploadingMedia = false
        }

        do {
            let attachment = try await uploadCapturedMediaAttachment(capturedMedia, normalizedNsec: normalizedNsec)
            if !mediaAttachments.contains(where: { $0.url == attachment.url }) {
                mediaAttachments.append(attachment)
                removeUploadedMediaURLIfPresent(attachment.url)
            }
            isEditorFocused = true
        } catch {
            viewModel.feedbackMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't upload media right now."
            viewModel.feedbackIsError = true
        }
    }

    private func handleMediaSelection(_ items: [PhotosPickerItem]) async {
        guard !isUploadingMedia else { return }
        viewModel.feedbackMessage = nil
        viewModel.feedbackIsError = false

        guard let normalizedNsec = currentNsec?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalizedNsec.isEmpty else {
            viewModel.feedbackMessage = "Sign in with a private key to upload media."
            viewModel.feedbackIsError = true
            return
        }

        isUploadingMedia = true
        defer {
            isUploadingMedia = false
        }

        var failedUploads = 0
        var firstError: Error?

        for item in items {
            do {
                let attachment = try await uploadMediaAttachment(from: item, normalizedNsec: normalizedNsec)

                if !mediaAttachments.contains(where: { $0.url == attachment.url }) {
                    mediaAttachments.append(attachment)
                    removeUploadedMediaURLIfPresent(attachment.url)
                }
            } catch {
                failedUploads += 1
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if failedUploads > 0 {
            let successfulUploads = items.count - failedUploads
            let detailedMessage = (firstError as? LocalizedError)?.errorDescription ?? firstError?.localizedDescription
            if successfulUploads > 0 {
                if let detailedMessage, !detailedMessage.isEmpty {
                    viewModel.feedbackMessage = "Uploaded \(successfulUploads) attachment\(successfulUploads == 1 ? "" : "s"), but \(failedUploads) failed: \(detailedMessage)"
                } else {
                    viewModel.feedbackMessage = "Uploaded \(successfulUploads) attachment\(successfulUploads == 1 ? "" : "s"), but \(failedUploads) failed."
                }
            } else {
                viewModel.feedbackMessage = detailedMessage ?? "Couldn't upload media right now."
            }
            viewModel.feedbackIsError = true
        }

        if failedUploads < items.count {
            isEditorFocused = true
        }
    }

    private func uploadMediaAttachment(from item: PhotosPickerItem, normalizedNsec: String) async throws -> ComposeMediaAttachment {
        let preparedMedia = try await MediaUploadPreparation.prepareUploadMedia(from: item)
        let filename = "note-\(UUID().uuidString).\(preparedMedia.fileExtension)"

        let result = try await mediaUploadService.uploadMedia(
            data: preparedMedia.data,
            mimeType: preparedMedia.mimeType,
            filename: filename,
            nsec: normalizedNsec,
            provider: .blossom
        )

        return ComposeMediaAttachment(
            url: result.url,
            imetaTag: result.imetaTag,
            mimeType: preparedMedia.mimeType,
            fileSizeBytes: preparedMedia.data.count
        )
    }

    private func handleKlipyGIFSelection(_ selection: KlipyGIFAttachmentCandidate) async {
        guard !isUploadingMedia else { return }
        viewModel.feedbackMessage = nil
        viewModel.feedbackIsError = false

        guard let normalizedNsec = currentNsec?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalizedNsec.isEmpty else {
            viewModel.feedbackMessage = "Sign in with a private key to upload media."
            viewModel.feedbackIsError = true
            return
        }

        isUploadingMedia = true
        defer {
            isUploadingMedia = false
        }

        do {
            let attachment = try await uploadKlipyGIFAttachment(selection, normalizedNsec: normalizedNsec)

            if !mediaAttachments.contains(where: { $0.url == attachment.url }) {
                mediaAttachments.append(attachment)
                removeUploadedMediaURLIfPresent(attachment.url)
            }

            isEditorFocused = true
            toastCenter.show("GIF added")

            Task {
                await klipyGIFService.registerShare(
                    slug: selection.slug,
                    customerID: selection.customerID,
                    query: selection.searchQuery
                )
            }
        } catch {
            viewModel.feedbackMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't add that GIF right now."
            viewModel.feedbackIsError = true
        }
    }

    private func uploadKlipyGIFAttachment(
        _ selection: KlipyGIFAttachmentCandidate,
        normalizedNsec: String
    ) async throws -> ComposeMediaAttachment {
        let downloadedData = try await klipyGIFService.downloadGIFData(for: selection)
        let preparedMedia = try MediaUploadPreparation.prepareUploadMedia(
            data: downloadedData,
            mimeType: selection.mimeType,
            fileExtension: selection.fileExtension
        )
        let filename = "gif-\(UUID().uuidString).\(preparedMedia.fileExtension)"

        let result = try await mediaUploadService.uploadMedia(
            data: preparedMedia.data,
            mimeType: preparedMedia.mimeType,
            filename: filename,
            nsec: normalizedNsec,
            provider: .blossom
        )

        return ComposeMediaAttachment(
            url: result.url,
            imetaTag: result.imetaTag,
            mimeType: preparedMedia.mimeType,
            fileSizeBytes: preparedMedia.data.count
        )
    }

    private func uploadCapturedMediaAttachment(
        _ capturedMedia: CapturedCameraMedia,
        normalizedNsec: String
    ) async throws -> ComposeMediaAttachment {
        let preparedMedia: PreparedUploadMedia

        switch capturedMedia {
        case .image(let imageData, let capturedMimeType, let capturedFileExtension):
            preparedMedia = try MediaUploadPreparation.prepareUploadMedia(
                data: imageData,
                mimeType: capturedMimeType,
                fileExtension: capturedFileExtension
            )

        case .video(let fileURL, let capturedMimeType, let capturedFileExtension):
            preparedMedia = try await MediaUploadPreparation.prepareUploadMedia(
                fileURL: fileURL,
                mimeType: capturedMimeType,
                fileExtension: capturedFileExtension
            )
        }

        let filename = "note-\(UUID().uuidString).\(preparedMedia.fileExtension)"
        let result = try await mediaUploadService.uploadMedia(
            data: preparedMedia.data,
            mimeType: preparedMedia.mimeType,
            filename: filename,
            nsec: normalizedNsec,
            provider: .blossom
        )

        return ComposeMediaAttachment(
            url: result.url,
            imetaTag: result.imetaTag,
            mimeType: preparedMedia.mimeType,
            fileSizeBytes: preparedMedia.data.count
        )
    }

    private func uploadSharedComposeAttachment(
        _ sharedAttachment: SharedComposeAttachment,
        normalizedNsec: String
    ) async throws -> ComposeMediaAttachment {
        let preparedMedia = try await prepareSharedComposeAttachmentForUpload(sharedAttachment)
        let filename = "note-\(UUID().uuidString).\(preparedMedia.fileExtension)"
        let result = try await mediaUploadService.uploadMedia(
            data: preparedMedia.data,
            mimeType: preparedMedia.mimeType,
            filename: filename,
            nsec: normalizedNsec,
            provider: .blossom
        )

        return ComposeMediaAttachment(
            url: result.url,
            imetaTag: result.imetaTag,
            mimeType: preparedMedia.mimeType,
            fileSizeBytes: preparedMedia.data.count
        )
    }

    private func removeMediaAttachment(_ attachment: ComposeMediaAttachment) {
        mediaAttachments.removeAll { $0.id == attachment.id }
    }

    private func removeUploadedMediaURLIfPresent(_ url: URL) {
        let urlString = url.absoluteString
        guard viewModel.text.contains(urlString) else { return }

        viewModel.text = viewModel.text
            .replacingOccurrences(of: "\n\(urlString)", with: "")
            .replacingOccurrences(of: urlString, with: "")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleSpeechToggle() async {
        let errorMessage = await speechTranscriber.toggleRecording { transcript in
            appendSpeechToDraft(transcript)
        }

        if let errorMessage {
            viewModel.feedbackMessage = errorMessage
            viewModel.feedbackIsError = true
        }
    }

    private func appendSpeechToDraft(_ transcript: String) {
        let normalized = transcript
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        if viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            viewModel.text = normalized
        } else {
            let needsSeparator = !(viewModel.text.hasSuffix(" ") || viewModel.text.hasSuffix("\n"))
            viewModel.text += needsSeparator ? " \(normalized)" : normalized
        }
        isEditorFocused = true
    }

    private func formatVoiceDuration(milliseconds: Int) -> String {
        let safeMilliseconds = max(milliseconds, 0)
        let totalSeconds = safeMilliseconds / 1_000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func defaultFileExtension(for mimeType: String) -> String {
        let normalized = mimeType.lowercased()
        if normalized.contains("jpeg") || normalized.contains("jpg") {
            return "jpg"
        }
        if normalized.contains("png") {
            return "png"
        }
        if normalized.contains("heic") {
            return "heic"
        }
        if normalized.contains("gif") {
            return "gif"
        }
        if normalized.contains("webp") {
            return "webp"
        }
        if normalized.contains("quicktime") || normalized.contains("mov") {
            return "mov"
        }
        if normalized.contains("mp4") {
            return "mp4"
        }
        if normalized.contains("mpeg") || normalized.contains("mp3") {
            return "mp3"
        }
        if normalized.contains("m4a") {
            return "m4a"
        }
        return "bin"
    }

    private func openSystemSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }

    private func togglePollDraft() {
        withAnimation(.easeInOut(duration: 0.18)) {
            if pollDraft == nil {
                pollDraft = .defaultDraft()
            } else {
                pollDraft = nil
            }
        }
    }

    private func publish() async {
        guard canPublish else {
            if currentNsec == nil {
                viewModel.feedbackMessage = "This account needs an nsec to publish notes."
            } else if writeRelayURLs.isEmpty {
                viewModel.feedbackMessage = "No publish sources are configured."
            } else if let pollValidationMessage {
                viewModel.feedbackMessage = pollValidationMessage
            } else {
                viewModel.feedbackMessage = currentNsec == nil
                    ? "This account needs an nsec to publish notes."
                    : writeRelayURLs.isEmpty
                        ? "No publish sources are configured."
                        : "Write a note or attach media before posting."
            }
            viewModel.feedbackIsError = true
            return
        }

        let publishTags = mediaAttachments.map(\.imetaTag) + initialAdditionalTags
        let isPublishingPoll = pollDraft != nil
        let didPublish = await viewModel.publish(
            currentAccountPubkey: currentAccountPubkey,
            currentNsec: currentNsec,
            writeRelayURLs: writeRelayURLs,
            additionalTags: publishTags,
            pollDraft: pollDraft,
            replyTargetEvent: replyTargetEvent
        )

        guard didPublish else { return }

        mediaAttachments.removeAll()
        pollDraft = nil
        onPublished?()
        if isPublishingPoll {
            toastCenter.show("Poll posted")
        } else {
            toastCenter.show(replyTargetEvent == nil ? "Note posted" : "Reply posted")
        }
        dismiss()
    }

    private func applyInitialDraftIfNeeded() {
        guard !hasAppliedInitialDraft else { return }
        hasAppliedInitialDraft = true

        guard viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !initialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        viewModel.text = initialText
    }

    private func applyInitialAttachmentsIfNeeded() {
        guard !hasAppliedInitialAttachments else { return }
        hasAppliedInitialAttachments = true

        guard !initialUploadedAttachments.isEmpty else { return }

        for attachment in initialUploadedAttachments {
            guard !mediaAttachments.contains(where: { $0.url == attachment.url }) else { continue }
            mediaAttachments.append(attachment)
            removeUploadedMediaURLIfPresent(attachment.url)
        }
    }

    private var configuredPublishSourceCount: Int {
        let normalized = Set(writeRelayURLs.map { $0.absoluteString.lowercased() })
        return normalized.count
    }

    private func applyInitialSharedAttachmentsIfNeeded() async {
        guard !hasAppliedInitialSharedAttachments else { return }
        hasAppliedInitialSharedAttachments = true

        guard !initialSharedAttachments.isEmpty else { return }

        viewModel.feedbackMessage = nil
        viewModel.feedbackIsError = false

        guard let normalizedNsec = currentNsec?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalizedNsec.isEmpty else {
            viewModel.feedbackMessage = "Sign in with a private key to upload media."
            viewModel.feedbackIsError = true
            return
        }

        isUploadingMedia = true
        defer {
            isUploadingMedia = false
        }

        var failedUploads = 0
        var firstError: Error?

        for sharedAttachment in initialSharedAttachments {
            do {
                let attachment = try await uploadSharedComposeAttachment(
                    sharedAttachment,
                    normalizedNsec: normalizedNsec
                )

                if !mediaAttachments.contains(where: { $0.url == attachment.url }) {
                    mediaAttachments.append(attachment)
                    removeUploadedMediaURLIfPresent(attachment.url)
                }

                FlowSharedComposeDraftStore.cleanupAttachmentFiles([sharedAttachment])
            } catch {
                failedUploads += 1
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if failedUploads > 0 {
            let successfulUploads = initialSharedAttachments.count - failedUploads
            let detailedMessage = (firstError as? LocalizedError)?.errorDescription ?? firstError?.localizedDescription
            if successfulUploads > 0 {
                if let detailedMessage, !detailedMessage.isEmpty {
                    viewModel.feedbackMessage = "Added \(successfulUploads) attachment\(successfulUploads == 1 ? "" : "s"), but \(failedUploads) failed: \(detailedMessage)"
                } else {
                    viewModel.feedbackMessage = "Added \(successfulUploads) attachment\(successfulUploads == 1 ? "" : "s"), but \(failedUploads) failed."
                }
            } else {
                viewModel.feedbackMessage = detailedMessage ?? "Couldn't upload media right now."
            }
            viewModel.feedbackIsError = true
        }

        if failedUploads < initialSharedAttachments.count {
            isEditorFocused = true
        }
    }

    private func cleanupInitialSharedAttachments() {
        guard !initialSharedAttachments.isEmpty else { return }
        FlowSharedComposeDraftStore.cleanupAttachmentFiles(initialSharedAttachments)
    }

    private func prepareSharedComposeAttachmentForUpload(
        _ sharedAttachment: SharedComposeAttachment
    ) async throws -> PreparedUploadMedia {
        guard let fileURL = sharedAttachment.resolvedFileURL else {
            throw SharedComposeImportError.missingFileURL
        }

        let mimeType = sharedAttachment.mimeType
        let normalizedMimeType = mimeType.lowercased()
        let normalizedFileExtension = sharedAttachment.fileExtension.lowercased()

        if normalizedMimeType.hasPrefix("video/") ||
            ["mp4", "mov", "m4v", "webm", "mkv"].contains(normalizedFileExtension) {
            return try await MediaUploadPreparation.prepareUploadMedia(
                fileURL: fileURL,
                mimeType: mimeType,
                fileExtension: normalizedFileExtension
            )
        }

        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            throw SharedComposeImportError.unreadableFile
        }

        return try MediaUploadPreparation.prepareUploadMedia(
            data: data,
            mimeType: mimeType,
            fileExtension: normalizedFileExtension
        )
    }

    private static func renderEventForQuotePreview(_ event: NostrEvent) -> NostrEvent {
        guard event.kind == 6 || event.kind == 16 else { return event }
        guard let embedded = decodeEmbeddedEvent(from: event.content) else { return event }
        guard embedded.kind != 6 && embedded.kind != 16 else { return event }
        return embedded
    }

    private static func previewText(for event: NostrEvent, maximumLength: Int? = nil) -> String {
        let tokens = NoteContentParser.tokenize(event: event)
        var fragments: [String] = []
        for token in tokens {
            switch token.type {
            case .text:
                let trimmed = token.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    fragments.append(trimmed)
                }
            default:
                continue
            }
        }

        let combined = fragments.joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let previewSource = combined.isEmpty
            ? event.content.trimmingCharacters(in: .whitespacesAndNewlines)
            : combined
        guard !previewSource.isEmpty else {
            return "Note"
        }
        guard let maximumLength else {
            return previewSource
        }
        return String(previewSource.prefix(maximumLength))
    }

    private static func previewImageURLs(for event: NostrEvent, limit: Int = 2) -> [URL] {
        let tokens = NoteContentParser.tokenize(event: event)
        var urls: [URL] = []
        var seen = Set<String>()
        for token in tokens where token.type == .image {
            guard let url = URL(string: token.value), url.scheme != nil else { continue }
            let normalized = url.absoluteString.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            urls.append(url)
            if urls.count == limit {
                break
            }
        }
        return urls
    }

    private static func previewHasVideo(for event: NostrEvent) -> Bool {
        NoteContentParser
            .tokenize(event: event)
            .contains(where: { $0.type == .video })
    }

    private static func previewHasAudio(for event: NostrEvent) -> Bool {
        NoteContentParser
            .tokenize(event: event)
            .contains(where: { $0.type == .audio })
    }

    private static func decodeEmbeddedEvent(from content: String) -> NostrEvent? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard let id = object["id"] as? String,
              let pubkey = object["pubkey"] as? String,
              let createdAt = object["created_at"] as? Int,
              let kind = object["kind"] as? Int,
              let content = object["content"] as? String,
              let sig = object["sig"] as? String else {
            return nil
        }

        let rawTags = object["tags"] as? [[Any]] ?? []
        let tags = rawTags.map { tag in
            tag.map { element in
                if let string = element as? String {
                    return string
                }
                return String(describing: element)
            }
        }

        return NostrEvent(
            id: id,
            pubkey: pubkey,
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: sig
        )
    }
}

private struct ComposeMediaAttachmentPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let attachment: ComposeMediaAttachment
    @State private var isAnimatingGIF = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                if attachment.isVideo {
                    VideoPreviewPlayer(url: attachment.url)
                        .ignoresSafeArea(edges: .bottom)
                } else if attachment.isImage {
                    ComposeAttachmentImagePreview(
                        url: attachment.url,
                        animateGIF: attachment.isGIF && isAnimatingGIF
                    )
                    .padding()
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: attachment.isAudio ? "waveform" : "paperclip")
                            .font(.system(size: 34, weight: .medium))
                        Text("Preview isn't available for this attachment.")
                            .font(.body)
                    }
                    .foregroundStyle(.white.opacity(0.84))
                }
            }
            .toolbar {
                if attachment.isGIF {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(isAnimatingGIF ? "Pause" : "Animate") {
                            isAnimatingGIF.toggle()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

private struct ComposeAttachmentImagePreview: View {
    let url: URL
    let animateGIF: Bool

    @State private var animatedImage: UIImage?
    @State private var animatedImageLoadFailed = false

    var body: some View {
        Group {
            if animateGIF {
                animatedPreview
            } else {
                staticPreview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: animateGIF) {
            guard animateGIF, animatedImage == nil, !animatedImageLoadFailed else { return }

            let decodedImage: UIImage? = await Task.detached(priority: .userInitiated) {
                guard let data = await FlowImageCache.shared.data(for: url) else {
                    return nil
                }
                return ComposeGIFImageDecoder.image(from: data)
            }.value

            guard !Task.isCancelled else { return }
            animatedImage = decodedImage
            animatedImageLoadFailed = decodedImage == nil
        }
    }

    @ViewBuilder
    private var staticPreview: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .tint(.white)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            case .failure:
                previewFailureIcon
            @unknown default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var animatedPreview: some View {
        if let animatedImage {
            ComposeAnimatedUIImageView(
                image: animatedImage,
                contentMode: .scaleAspectFit
            )
        } else if animatedImageLoadFailed {
            staticPreview
        } else {
            ProgressView()
                .tint(.white)
        }
    }

    private var previewFailureIcon: some View {
        Image(systemName: "exclamationmark.triangle")
            .font(.largeTitle)
            .foregroundStyle(.white.opacity(0.8))
    }
}

private struct VideoPreviewPlayer: View {
    @State private var player: AVPlayer

    init(url: URL) {
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .background(Color.black)
            .onDisappear {
                player.pause()
            }
    }
}

private struct ComposeAnimatedUIImageView: UIViewRepresentable {
    let image: UIImage
    let contentMode: UIView.ContentMode

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.backgroundColor = .clear
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = false
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        imageView.stopAnimating()
        imageView.contentMode = contentMode
        imageView.image = image
        if image.images != nil {
            imageView.startAnimating()
        }
    }

    static func dismantleUIView(_ imageView: UIImageView, coordinator: ()) {
        imageView.stopAnimating()
        imageView.image = nil
    }
}

private enum ComposeGIFImageDecoder {
    static func image(from data: Data) -> UIImage? {
        guard data.starts(with: [0x47, 0x49, 0x46]),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1 else {
            return UIImage(data: data)
        }

        var frames: [UIImage] = []
        frames.reserveCapacity(frameCount)
        var totalDuration: TimeInterval = 0

        for index in 0..<frameCount {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            totalDuration += frameDuration(forFrameAt: index, source: source)
            frames.append(UIImage(cgImage: frame, scale: UIScreen.main.scale, orientation: .up))
        }

        guard !frames.isEmpty else {
            return UIImage(data: data)
        }

        return UIImage.animatedImage(
            with: frames,
            duration: max(totalDuration, Double(frames.count) * 0.1)
        )
    }

    private static func frameDuration(forFrameAt index: Int, source: CGImageSource) -> TimeInterval {
        let defaultDelay = 0.1
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return defaultDelay
        }

        let unclampedDelay = (gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
        let delay = (gifProperties[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
        let frameDelay = unclampedDelay ?? delay ?? defaultDelay
        return frameDelay < 0.02 ? defaultDelay : frameDelay
    }
}

private struct CameraCapturePermissionSheet: View {
    let permissions: CameraCapturePermissionSnapshot
    let isRequestingAccess: Bool
    let onContinue: () -> Void
    let onOpenSettings: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: permissions.isCameraBlocked ? "camera.fill.badge.ellipsis" : "camera.badge.ellipsis")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text(title)
                    .font(.title3.weight(.semibold))

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                if permissions.isCameraBlocked {
                    Button {
                        onOpenSettings()
                    } label: {
                        Text("Open Settings")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        onContinue()
                    } label: {
                        Group {
                            if isRequestingAccess {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Continue")
                                    .font(.headline.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRequestingAccess)
                }

                Button("Not now") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .padding(20)
    }

    private var title: String {
        if permissions.isCameraBlocked {
            return "Turn on camera access"
        }
        return "Camera and microphone access"
    }

    private var message: String {
        if permissions.isCameraBlocked {
            return "To capture photos or videos for your note, \(AppBrand.displayName) needs camera access. Microphone access is used for video capture with sound. You can change this any time later in app settings."
        }
        return "To capture photos or videos for your note, \(AppBrand.displayName) needs access to your camera and microphone. You can change this any time later in app settings."
    }
}

private struct ComposeMultilineTextView: UIViewRepresentable {
    @EnvironmentObject private var appSettings: AppSettingsStore
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = appSettings.appUIFont(.body)
        textView.typingAttributes[.font] = appSettings.appUIFont(.body)
        textView.adjustsFontForContentSizeCategory = false
        textView.textColor = .label
        textView.tintColor = .label
        textView.autocorrectionType = .yes
        textView.spellCheckingType = .yes
        textView.smartQuotesType = .yes
        textView.smartDashesType = .yes
        textView.smartInsertDeleteType = .yes
        textView.keyboardType = .default
        textView.returnKeyType = .default
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let preferredFont = appSettings.appUIFont(.body)
        if uiView.font != preferredFont {
            uiView.font = preferredFont
            uiView.typingAttributes[.font] = preferredFont
        }

        if uiView.text != text {
            uiView.text = text
            uiView.selectedRange = NSRange(location: uiView.text.utf16.count, length: 0)
        }

        if isFocused {
            guard uiView.window != nil, !uiView.isFirstResponder else { return }
            DispatchQueue.main.async {
                if uiView.window != nil && !uiView.isFirstResponder {
                    uiView.becomeFirstResponder()
                }
            }
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var text: String
        @Binding private var isFocused: Bool

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            _text = text
            _isFocused = isFocused
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isFocused = false
        }
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (CapturedCameraMedia) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.mediaTypes = supportedMediaTypes
        picker.videoQuality = .typeMedium
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    private var supportedMediaTypes: [String] {
        let available = Set(UIImagePickerController.availableMediaTypes(for: .camera) ?? [])
        let preferred = [UTType.image.identifier, UTType.movie.identifier]
        let filtered = preferred.filter { available.contains($0) }
        return filtered.isEmpty ? [UTType.image.identifier] : filtered
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraCaptureView

        init(parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let mediaType = info[.mediaType] as? String else {
                parent.onCancel()
                return
            }

            if mediaType == UTType.movie.identifier,
               let mediaURL = info[.mediaURL] as? URL {
                let fileExtension = mediaURL.pathExtension.isEmpty ? "mov" : mediaURL.pathExtension.lowercased()
                let mimeType = UTType(filenameExtension: fileExtension)?.preferredMIMEType ?? "video/quicktime"
                parent.onCapture(.video(fileURL: mediaURL, mimeType: mimeType, fileExtension: fileExtension))
                return
            }

            if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage,
               let imageData = image.jpegData(compressionQuality: 0.92) {
                parent.onCapture(.image(data: imageData, mimeType: "image/jpeg", fileExtension: "jpg"))
                return
            }

            parent.onCancel()
        }
    }
}
