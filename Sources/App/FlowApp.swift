import SwiftUI

enum AppBrand {
    static let displayName = "Flow"
}

@main
struct FlowApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var appSettings = AppSettingsStore.shared
    @StateObject private var relaySettings = RelaySettingsStore.shared
    @StateObject private var toastCenter = AppToastCenter()

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
            .overlay(alignment: .top) {
                AppToastOverlay()
            }
            .environmentObject(authManager)
            .environmentObject(appSettings)
            .environmentObject(relaySettings)
            .environmentObject(toastCenter)
            .tint(appSettings.primaryColor)
            .preferredColorScheme(appSettings.preferredColorScheme)
            .environment(\.dynamicTypeSize, appSettings.dynamicTypeSize)
            .task {
                appSettings.configure(accountPubkey: authManager.currentAccount?.pubkey)
                await appSettings.refreshNotificationAuthorizationStatus()
            }
            .onChange(of: authManager.currentAccount?.pubkey) { _, newValue in
                appSettings.configure(accountPubkey: newValue)
            }
        }
    }
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
