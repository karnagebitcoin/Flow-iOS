import SwiftUI
import UIKit

enum AppBrand {
    static let displayName = "Flow"
}

@main
struct FlowApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var authManager = AuthManager()
    @StateObject private var appSettings = AppSettingsStore.shared
    @StateObject private var relaySettings = RelaySettingsStore.shared
    @StateObject private var toastCenter = AppToastCenter()
    @StateObject private var composeSheetCoordinator = AppComposeSheetCoordinator()
    @StateObject private var breakReminderCoordinator = BreakReminderCoordinator()

    init() {
        FlowMediaCache.configureSharedURLCache()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isLoggedIn {
                    MainTabShellView()
                } else {
                    WelcomeOnboardingView()
                }
            }
            .overlay {
                GlobalProfileQRCodeBridge()
            }
            .overlay {
                BreakReminderOverlayHost(coordinator: breakReminderCoordinator)
            }
            .overlay(alignment: .top) {
                AppToastOverlay()
            }
            .environmentObject(authManager)
            .environmentObject(appSettings)
            .environmentObject(relaySettings)
            .environmentObject(toastCenter)
            .environmentObject(composeSheetCoordinator)
            .environmentObject(breakReminderCoordinator)
            .tint(appSettings.primaryColor)
            .preferredColorScheme(appSettings.preferredColorScheme)
            .environment(\.dynamicTypeSize, appSettings.dynamicTypeSize)
            .task {
                appSettings.configure(accountPubkey: authManager.currentAccount?.pubkey)
                updateBreakReminderMonitoring()
                await appSettings.refreshNotificationAuthorizationStatus()
                await presentPendingSharedComposeDraftIfPossible()
            }
            .onChange(of: authManager.currentAccount?.pubkey) { _, newValue in
                appSettings.configure(accountPubkey: newValue)
                updateBreakReminderMonitoring()
                Task {
                    await presentPendingSharedComposeDraftIfPossible()
                }
            }
            .onChange(of: appSettings.breakReminderInterval) { _, _ in
                updateBreakReminderMonitoring()
            }
            .onChange(of: composeSheetCoordinator.draft?.id) { _, newValue in
                guard newValue == nil else { return }
                Task {
                    await presentPendingSharedComposeDraftIfPossible()
                }
            }
            .onChange(of: scenePhase) { _, newValue in
                updateBreakReminderMonitoring()
                guard newValue == .active else { return }
                Task {
                    await presentPendingSharedComposeDraftIfPossible()
                }
            }
            .onOpenURL { url in
                guard FlowSharedComposeDraftStore.canHandleIncomingURL(url) else { return }
                Task {
                    await presentPendingSharedComposeDraftIfPossible()
                }
            }
        }
    }

    @MainActor
    private func presentPendingSharedComposeDraftIfPossible() async {
        guard authManager.currentAccount != nil else { return }
        guard composeSheetCoordinator.draft == nil else { return }
        guard let pendingDraft = FlowSharedComposeDraftStore.takePendingDraft(),
              !pendingDraft.attachments.isEmpty else {
            return
        }

        composeSheetCoordinator.presentSharedMedia(attachments: pendingDraft.attachments)
    }

    private func updateBreakReminderMonitoring() {
        breakReminderCoordinator.update(
            isEnabled: authManager.currentAccount != nil,
            interval: appSettings.breakReminderInterval,
            scenePhase: scenePhase
        )
    }
}

@MainActor
final class AppComposeSheetCoordinator: ObservableObject {
    @Published var draft: AppComposeSheetDraft?

    func presentNewNote() {
        draft = AppComposeSheetDraft()
    }

    func presentRemix(
        attachment: ComposeMediaAttachment,
        replyTargetEvent: NostrEvent?
    ) {
        draft = AppComposeSheetDraft(
            initialUploadedAttachments: [attachment],
            replyTargetEvent: replyTargetEvent
        )
    }

    func presentSharedMedia(attachments: [SharedComposeAttachment]) {
        draft = AppComposeSheetDraft(
            initialSharedAttachments: attachments
        )
    }

    func dismiss() {
        draft = nil
    }
}

struct AppComposeSheetDraft: Identifiable {
    let id = UUID()
    var initialText: String = ""
    var initialAdditionalTags: [[String]] = []
    var initialUploadedAttachments: [ComposeMediaAttachment] = []
    var initialSharedAttachments: [SharedComposeAttachment] = []
    var replyTargetEvent: NostrEvent? = nil
    var quotedEvent: NostrEvent? = nil
    var quotedDisplayNameHint: String? = nil
    var quotedHandleHint: String? = nil
    var quotedAvatarURLHint: URL? = nil
}

private struct GlobalProfileQRCodeBridge: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthManager

    @State private var isMonitoringOrientation = false

    private let overlayController = GlobalProfileQRCodeOverlayController.shared

    var body: some View {
        Color.clear
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onAppear {
                guard !isMonitoringOrientation else { return }
                isMonitoringOrientation = true
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                syncPresentation()
            }
            .onDisappear {
                guard isMonitoringOrientation else { return }
                isMonitoringOrientation = false
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
                overlayController.dismiss()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                syncPresentation()
            }
            .onChange(of: auth.currentAccount?.id) { _, _ in
                syncPresentation(forceRefresh: true)
            }
            .onChange(of: scenePhase) { _, _ in
                syncPresentation(forceRefresh: true)
            }
    }

    private func syncPresentation(forceRefresh: Bool = false) {
        overlayController.update(
            orientation: UIDevice.current.orientation,
            currentAccount: auth.currentAccount,
            scenePhase: scenePhase,
            forceRefresh: forceRefresh
        )
    }
}

@MainActor
private final class GlobalProfileQRCodeOverlayController {
    static let shared = GlobalProfileQRCodeOverlayController()

    private var overlayWindow: UIWindow?
    private var pendingPresentationTask: Task<Void, Never>?
    private var presentedPubkey: String?

    func update(
        orientation: UIDeviceOrientation,
        currentAccount: AuthAccount?,
        scenePhase: ScenePhase,
        forceRefresh: Bool = false
    ) {
        guard scenePhase == .active, let currentAccount else {
            dismiss()
            return
        }

        switch orientation {
        case .portraitUpsideDown:
            presentIfNeeded(for: currentAccount, forceRefresh: forceRefresh)
        case .faceUp, .faceDown, .unknown:
            break
        default:
            dismiss()
        }
    }

    func dismiss() {
        pendingPresentationTask?.cancel()
        pendingPresentationTask = nil
        overlayWindow?.isHidden = true
        overlayWindow = nil
        presentedPubkey = nil
    }

    private func presentIfNeeded(for account: AuthAccount, forceRefresh: Bool) {
        let shouldRefresh = forceRefresh || presentedPubkey != account.pubkey
        guard shouldRefresh || overlayWindow == nil else { return }

        pendingPresentationTask?.cancel()
        presentedPubkey = account.pubkey

        pendingPresentationTask = Task { [weak self] in
            guard let self else { return }

            let presentation = await self.buildPresentation(for: account)
            guard !Task.isCancelled else { return }
            self.show(presentation)
        }
    }

    private func buildPresentation(for account: AuthAccount) async -> GlobalProfileQRCodePresentation {
        let profile = await ProfileCache.shared.cachedProfile(pubkey: account.pubkey)

        return GlobalProfileQRCodePresentation(
            displayName: preferredDisplayName(from: profile, fallbackPubkey: account.pubkey),
            handle: preferredHandle(from: profile, fallbackPubkey: account.pubkey),
            avatarURL: preferredAvatarURL(from: profile),
            qrCodeImage: QRCodeRenderer.render(payload: "nostr:\(account.npub)")
        )
    }

    private func show(_ presentation: GlobalProfileQRCodePresentation) {
        guard let windowScene = activeWindowScene() else { return }

        let content = PresentedProfileQRCodeView(
            trigger: .automatic,
            displayName: presentation.displayName,
            handle: presentation.handle,
            avatarURL: presentation.avatarURL,
            qrCodeImage: presentation.qrCodeImage,
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        let hostingController = UIHostingController(rootView: content)
        hostingController.view.backgroundColor = .black

        if let overlayWindow {
            overlayWindow.rootViewController = hostingController
            overlayWindow.isHidden = false
            return
        }

        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        window.windowLevel = .alert + 1
        window.rootViewController = hostingController
        window.isHidden = false

        overlayWindow = window
    }

    private func activeWindowScene() -> UIWindowScene? {
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        return windowScenes.first(where: { scene in
            scene.activationState == .foregroundActive &&
                scene.windows.contains(where: \.isKeyWindow)
        }) ?? windowScenes.first(where: { $0.activationState == .foregroundActive })
            ?? windowScenes.first(where: { $0.activationState == .foregroundInactive })
    }

    private func preferredDisplayName(from profile: NostrProfile?, fallbackPubkey: String) -> String {
        if let displayName = trimmedNonEmpty(profile?.displayName) {
            return displayName
        }
        if let name = trimmedNonEmpty(profile?.name) {
            return name
        }
        return shortNostrIdentifier(fallbackPubkey)
    }

    private func preferredHandle(from profile: NostrProfile?, fallbackPubkey: String) -> String {
        if let name = trimmedNonEmpty(profile?.name) {
            return "@\(normalizedHandleComponent(from: name))"
        }
        if let displayName = trimmedNonEmpty(profile?.displayName) {
            return "@\(normalizedHandleComponent(from: displayName))"
        }
        return "@\(shortNostrIdentifier(fallbackPubkey).lowercased())"
    }

    private func preferredAvatarURL(from profile: NostrProfile?) -> URL? {
        guard let picture = trimmedNonEmpty(profile?.picture),
              let url = URL(string: picture),
              url.scheme != nil else {
            return nil
        }
        return url
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func normalizedHandleComponent(from value: String) -> String {
        let compact = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        return compact.isEmpty ? "user" : compact
    }
}

private struct GlobalProfileQRCodePresentation {
    let displayName: String
    let handle: String?
    let avatarURL: URL?
    let qrCodeImage: UIImage?
}

enum AppToastStyle {
    case success
    case info
    case error

    var iconName: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .info:
            return "checkmark.circle"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .success:
            return .green
        case .info:
            return .accentColor
        case .error:
            return .red
        }
    }
}

struct AppToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let style: AppToastStyle
}

@MainActor
final class AppToastCenter: ObservableObject {
    @Published private(set) var toast: AppToast?

    private var dismissalTask: Task<Void, Never>?

    func show(_ message: String, style: AppToastStyle = .success, duration: TimeInterval = 2.2) {
        dismissalTask?.cancel()

        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            toast = AppToast(message: message, style: style)
        }

        dismissalTask = Task { [weak self] in
            let safeDuration = max(duration, 0.8)
            let nanoseconds = UInt64(safeDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    self?.toast = nil
                }
            }
        }
    }

    func dismiss() {
        dismissalTask?.cancel()
        dismissalTask = nil

        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            toast = nil
        }
    }
}

struct AppToastOverlay: View {
    @EnvironmentObject private var toastCenter: AppToastCenter

    var body: some View {
        VStack(spacing: 0) {
            if let toast = toastCenter.toast {
                AppToastBanner(toast: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: toastCenter.toast?.id)
    }
}

private struct AppToastBanner: View {
    let toast: AppToast

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: toast.style.iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(toast.style.accentColor)

            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(toast.style.accentColor.opacity(0.22), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .combine)
    }
}
