import NostrSDK
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var premiumStore: FlowPremiumStore
    @EnvironmentObject private var breakReminderCoordinator: BreakReminderCoordinator
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @ObservedObject var sheetState: SettingsSheetState

    var body: some View {
        ZStack {
            appSettings.themePalette.sheetBackground
                .ignoresSafeArea()

            NavigationStack(path: navigationPathBinding) {
                ThemedSettingsForm {
                    ThemedSettingsSection {
                        SettingsValueNavigationRow(
                            title: "General",
                            systemImage: "slider.horizontal.3",
                            value: .general
                        )

                        SettingsValueNavigationRow(
                            title: "Appearance",
                            systemImage: "paintbrush",
                            value: .appearance
                        )

                        SettingsValueNavigationRow(
                            title: "Feeds",
                            systemImage: "newspaper",
                            value: .feeds
                        )

                        SettingsValueNavigationRow(
                            title: "Notifications",
                            systemImage: "bell.badge",
                            value: .notifications
                        )

                        SettingsValueNavigationRow(
                            title: "Media",
                            systemImage: "photo.on.rectangle.angled",
                            value: .media
                        )

                        SettingsValueNavigationRow(
                            title: "Muted Content",
                            systemImage: "speaker.slash",
                            value: .mutedContent
                        )

                        SettingsValueNavigationRow(
                            title: "Keys",
                            systemImage: "key",
                            value: .keys
                        )

                        SettingsValueNavigationRow(
                            title: "Connection",
                            subtitle: connectionSummaryText,
                            systemImage: "dot.radiowaves.left.and.right",
                            value: .connection
                        )
                    }

                    ThemedSettingsSection {
                        SettingsValueNavigationRow(
                            title: "Halo Plus",
                            subtitle: flowPlusSummaryText,
                            systemImage: "sparkles",
                            value: .flowPlus
                        )
                    }
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(for: SettingsDestination.self) { destination in
                    settingsDestinationView(for: destination)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ThemedToolbarDoneButton {
                            dismiss()
                        }
                    }
                }
                .overlay {
                    BreakReminderOverlayHost(coordinator: breakReminderCoordinator)
                }
                .task {
                    await appSettings.refreshNotificationAuthorizationStatus()
                }
                .sheet(isPresented: isShowingPrimaryColorPickerBinding) {
                    SettingsNativeColorPicker(
                        title: "Primary Color",
                        color: Binding(
                            get: { appSettings.primaryColor },
                            set: { appSettings.primaryColor = $0 }
                        ),
                        onDismiss: {
                            sheetState.isShowingPrimaryColorPicker = false
                        }
                    )
                    .preferredColorScheme(appSettings.preferredColorScheme)
                }
            }
        }
        .presentationBackground(appSettings.themePalette.sheetBackground)
        .preferredColorScheme(appSettings.preferredColorScheme)
    }

    private var connectionSummaryText: String {
        let count = Set(relaySettings.readRelays + relaySettings.writeRelays).count
        return "Connected to \(count) \(count == 1 ? "source" : "sources")"
    }

    private var flowPlusSummaryText: String {
        if premiumStore.isFlowPlusActive {
            return "Themes and typography unlocked"
        }

        if let previewTheme = appSettings.previewTheme, previewTheme.requiresFlowPlus {
            return "Previewing \(previewTheme.title)"
        }

        if appSettings.hasFlowPlusCustomizationAccess {
            return "Temporary testing unlock active"
        }

        return "Themes, typography, and extras"
    }

    private var navigationPathBinding: Binding<[SettingsDestination]> {
        Binding(
            get: { sheetState.navigationPath },
            set: { sheetState.navigationPath = $0 }
        )
    }

    private var isShowingPrimaryColorPickerBinding: Binding<Bool> {
        Binding(
            get: { sheetState.isShowingPrimaryColorPicker },
            set: { sheetState.isShowingPrimaryColorPicker = $0 }
        )
    }

    @ViewBuilder
    private func settingsDestinationView(for destination: SettingsDestination) -> some View {
        switch destination {
        case .general:
            SettingsGeneralView()
        case .appearance:
            SettingsAppearanceView(
                onOpenPrimaryColorPicker: {
                    sheetState.isShowingPrimaryColorPicker = true
                }
            )
        case .flowPlus:
            SettingsFlowPlusView()
        case .feeds:
            SettingsFeedsView()
        case .notifications:
            SettingsNotificationsView()
        case .media:
            SettingsMediaView()
        case .mutedContent:
            SettingsMutedContentView()
        case .keys:
            KeysView()
        case .connection:
            RelaySettingsView()
        }
    }
}

@MainActor
final class SettingsSheetState: ObservableObject {
    @Published var navigationPath: [SettingsDestination] = []
    @Published var isShowingPrimaryColorPicker = false

    func reset() {
        navigationPath.removeAll()
        isShowingPrimaryColorPicker = false
    }
}

enum SettingsDestination: Hashable {
    case general
    case appearance
    case flowPlus
    case feeds
    case notifications
    case media
    case mutedContent
    case keys
    case connection
}

private struct SettingsNavigationRow<Destination: View>: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    let title: String
    let subtitle: String?
    let systemImage: String
    let destination: Destination

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(appSettings.primaryColor)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(appSettings.appFont(.body, weight: .regular))
                        .foregroundStyle(.primary)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(appSettings.appFont(.footnote))
                            .foregroundStyle(appSettings.themePalette.mutedForeground)
                    }
                }

                Spacer(minLength: 8)
            }
        }
    }
}

private struct SettingsValueNavigationRow: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    let title: String
    let subtitle: String?
    let systemImage: String
    let value: SettingsDestination

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        value: SettingsDestination
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.value = value
    }

    var body: some View {
        NavigationLink(value: value) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(appSettings.primaryColor)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(appSettings.appFont(.body, weight: .regular))
                        .foregroundStyle(.primary)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(appSettings.appFont(.footnote))
                            .foregroundStyle(appSettings.themePalette.mutedForeground)
                    }
                }

                Spacer(minLength: 8)
            }
        }
    }
}

private struct SettingsToggleRow: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    let title: String
    @Binding var isOn: Bool
    let footer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: $isOn)

            Text(footer)
                .font(.footnote)
                .foregroundStyle(appSettings.themePalette.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

struct NotificationPreferencesView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    var navigationTitleText: String = "Notifications"
    var titleDisplayMode: NavigationBarItem.TitleDisplayMode = .large

    var body: some View {
        ThemedSettingsForm {
            Section("System Notifications") {
                NotificationPreferencesToggleRow(
                    title: "Enable Notifications",
                    isOn: Binding(
                        get: { appSettings.notificationsEnabled },
                        set: { appSettings.notificationsEnabled = $0 }
                    ),
                    footer: appSettings.notificationsStatusDescription
                )
            }

            Section {
                Toggle("Mentions", isOn: Binding(
                    get: { appSettings.activityMentionNotificationsEnabled },
                    set: { appSettings.activityMentionNotificationsEnabled = $0 }
                ))

                Toggle("Reactions", isOn: Binding(
                    get: { appSettings.activityReactionNotificationsEnabled },
                    set: { appSettings.activityReactionNotificationsEnabled = $0 }
                ))

                Toggle("Replies", isOn: Binding(
                    get: { appSettings.activityReplyNotificationsEnabled },
                    set: { appSettings.activityReplyNotificationsEnabled = $0 }
                ))

                Toggle("Reshares", isOn: Binding(
                    get: { appSettings.activityReshareNotificationsEnabled },
                    set: { appSettings.activityReshareNotificationsEnabled = $0 }
                ))

                Toggle("Quote Shares", isOn: Binding(
                    get: { appSettings.activityQuoteShareNotificationsEnabled },
                    set: { appSettings.activityQuoteShareNotificationsEnabled = $0 }
                ))
            } header: {
                Text("Pulse Alerts")
            } footer: {
                Text("These controls decide which Pulse events trigger the in-app bell badge and future notification delivery.")
            }
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(titleDisplayMode)
        .task {
            await appSettings.refreshNotificationAuthorizationStatus()
        }
    }
}

struct SettingsFormSurfaceStyle {
    let formBackground: Color
    let cardBackground: Color
    let cardBorder: Color
    let subcardBackground: Color
    let controlBackground: Color
    let navigationBackground: Color
}

extension AppSettingsStore {
    func settingsFormSurfaceStyle(for colorScheme: ColorScheme) -> SettingsFormSurfaceStyle {
        let palette = themePalette
        let subcardBackground = colorScheme == .light
            ? palette.sheetCardBackground
            : palette.sheetInsetBackground

        return SettingsFormSurfaceStyle(
            formBackground: palette.sheetBackground,
            cardBackground: palette.sheetCardBackground,
            cardBorder: palette.sheetCardBorder,
            subcardBackground: subcardBackground,
            controlBackground: palette.sheetInsetBackground,
            navigationBackground: palette.sheetBackground
        )
    }
}

struct ThemedSettingsForm<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettingsStore

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let effectiveColorScheme = appSettings.preferredColorScheme ?? colorScheme
        let surfaceStyle = appSettings.settingsFormSurfaceStyle(for: effectiveColorScheme)

        return Form {
            content
                .listRowBackground(surfaceStyle.cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(surfaceStyle.formBackground)
        .tint(appSettings.primaryColor)
        .listRowSeparatorTint(surfaceStyle.cardBorder)
        .listSectionSeparatorTint(surfaceStyle.cardBorder)
        .toolbarBackground(surfaceStyle.navigationBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(effectiveColorScheme, for: .navigationBar)
        .presentationBackground(surfaceStyle.formBackground)
        .preferredColorScheme(appSettings.preferredColorScheme)
    }
}

struct ThemedToolbarDoneButton: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    var title: String = "Done"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(appSettings.appFont(.subheadline, weight: .semibold))
                .foregroundStyle(appSettings.themePalette.foreground)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    appSettings.themePalette.navigationControlBackground,
                    in: Capsule(style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}

struct ThemedSettingsSection: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    private let title: LocalizedStringKey?
    private let content: AnyView
    private let header: AnyView?
    private let footer: AnyView?

    init<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = AnyView(content())
        self.header = nil
        self.footer = nil
    }

    init<Content: View>(
        @ViewBuilder content: () -> Content
    ) {
        self.title = nil
        self.content = AnyView(content())
        self.header = nil
        self.footer = nil
    }

    init<Content: View, Header: View, Footer: View>(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = nil
        self.content = AnyView(content())
        self.header = AnyView(header())
        self.footer = AnyView(footer())
    }

    var body: some View {
        sectionBody
            .listRowBackground(appSettings.themePalette.sheetCardBackground)
    }

    @ViewBuilder
    private var sectionBody: some View {
        if let header, let footer {
            Section {
                content
            } header: {
                header
            } footer: {
                footer
            }
        } else if let title {
            Section(title) {
                content
            }
        } else {
            Section {
                content
            }
        }
    }
}

private struct NotificationPreferencesToggleRow: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    let title: String
    @Binding var isOn: Bool
    let footer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: $isOn)

            Text(footer)
                .font(.footnote)
                .foregroundStyle(appSettings.themePalette.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsAppearanceView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    let onOpenPrimaryColorPicker: () -> Void

    private var appearanceThemeOptions: [AppThemeOption] {
        AppThemeOption.allCases.filter { !$0.requiresFlowPlus }
    }

    var body: some View {
        ThemedSettingsForm {
            Section("Appearance") {
                Button {
                    guard appSettings.canCustomizePrimaryColor else { return }
                    onOpenPrimaryColorPicker()
                } label: {
                    HStack(spacing: 12) {
                        Text("Primary Color")
                            .foregroundStyle(.primary)

                        Spacer(minLength: 12)

                        Circle()
                            .fill(appSettings.primaryColor)
                            .frame(width: 22, height: 22)
                            .overlay {
                                Circle()
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            }

                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!appSettings.canCustomizePrimaryColor)
                .opacity(appSettings.canCustomizePrimaryColor ? 1 : 0.55)

                if !appSettings.canCustomizePrimaryColor {
                    Text("This theme includes its own accent color.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Theme")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ],
                        spacing: 10
                    ) {
                        ForEach(appearanceThemeOptions) { option in
                            themeOptionCard(for: option)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Section("Font Size") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "textformat.size")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(appSettings.primaryColor)
                        Text("Font Size")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    FlowCapsuleTabBar(
                        selection: $appSettings.fontSize,
                        items: AppFontSize.allCases,
                        title: { $0.title }
                    )

                    Text("Applies to note text and interface labels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section("Preview") {
                notePreviewCard
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.large)
    }

    private var notePreviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note Preview")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(appSettings.themePalette.tertiaryFill)
                        .overlay {
                            Text("A")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("alex")
                            .font(appSettings.appFont(.subheadline, weight: .semibold))
                        Text("@alex")
                            .font(appSettings.appFont(.caption1))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Text("2 hr")
                        .font(appSettings.appFont(.caption2))
                        .foregroundStyle(.secondary)
                }

                NoteContentView(event: Self.previewEvent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(appSettings.themePalette.secondaryBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .environment(\.dynamicTypeSize, appSettings.dynamicTypeSize)
            .id("\(appSettings.fontSize.rawValue)-\(appSettings.activeFontOption.rawValue)")
        }
        .padding(.vertical, 2)
    }

    private func themeOptionCard(for option: AppThemeOption) -> some View {
        let isSelected = appSettings.theme == option

        return Button {
            guard option.isEnabled else { return }
            appSettings.theme = option
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(themePreviewFill(for: option))
                        .frame(height: 60)
                        .overlay {
                            Image(systemName: option.iconName)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(themePreviewForeground(for: option))
                        }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(appSettings.primaryColor)
                            .padding(8)
                    } else if !option.isEnabled {
                        Text("Soon")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(appSettings.themePalette.chromeBackground.opacity(0.82), in: Capsule(style: .continuous))
                            .padding(8)
                    }
                }

                Text(option.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(option.isEnabled ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(appSettings.themePalette.secondaryBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? appSettings.primaryColor : appSettings.themePalette.separator.opacity(0.18),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .opacity(option.isEnabled ? 1 : 0.72)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!option.isEnabled)
    }

    private func themePreviewFill(for option: AppThemeOption) -> LinearGradient {
        switch option {
        case .system:
            return LinearGradient(
                colors: [Color(.systemGray6), Color(.systemGray4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .black:
            return LinearGradient(
                colors: [Color(red: 0.08, green: 0.08, blue: 0.10), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .white:
            return LinearGradient(
                colors: [Color.white, Color(.systemGray6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .sakura:
            return AppThemeOption.sakura.fixedPrimaryGradient ?? LinearGradient(
                colors: [
                    Color(red: 0.976, green: 0.659, blue: 1.0),
                    Color(red: 1.0, green: 0.404, blue: 0.941)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dracula:
            return AppThemeOption.dracula.fixedPrimaryGradient ?? LinearGradient(
                colors: [
                    Color(red: 0.741, green: 0.576, blue: 0.976),
                    Color(red: 1.0, green: 0.475, blue: 0.776)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .gamer:
            return AppThemeOption.gamer.fixedPrimaryGradient ?? LinearGradient(
                colors: [
                    Color(red: 0.553, green: 0.408, blue: 1.0),
                    Color(red: 0.329, green: 0.920, blue: 0.996)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dark:
            return LinearGradient(
                colors: [Color(red: 0.19, green: 0.16, blue: 0.28), Color(red: 0.09, green: 0.08, blue: 0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .light:
            return LinearGradient(
                colors: [Color(red: 0.99, green: 0.95, blue: 0.86), Color(red: 0.94, green: 0.98, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func themePreviewForeground(for option: AppThemeOption) -> Color {
        switch option {
        case .white, .light, .system:
            return Color(.label).opacity(0.75)
        case .sakura:
            return Color(red: 0.45, green: 0.21, blue: 0.32)
        case .dracula:
            return Color(red: 0.973, green: 0.973, blue: 0.949).opacity(0.92)
        case .gamer:
            return Color.white.opacity(0.92)
        case .black, .dark:
            return .white.opacity(0.85)
        }
    }

    private static var previewEvent: NostrEvent {
        NostrEvent(
            id: String(repeating: "a", count: 64),
            pubkey: String(repeating: "b", count: 64),
            createdAt: Int(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Switching font size here updates note readability in the feed. #flow",
            sig: String(repeating: "c", count: 128)
        )
    }
}

private struct SettingsNativeColorPicker: UIViewControllerRepresentable {
    let title: String
    @Binding var color: Color
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let controller = UIColorPickerViewController()
        controller.title = title
        controller.supportsAlpha = false
        controller.selectedColor = UIColor(color)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIColorPickerViewController, context: Context) {
        let currentUIColor = UIColor(color)
        if controller.selectedColor != currentUIColor {
            controller.selectedColor = currentUIColor
        }
    }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        @Binding private var color: Color
        private let onDismiss: () -> Void

        init(color: Binding<Color>, onDismiss: @escaping () -> Void) {
            _color = color
            self.onDismiss = onDismiss
        }

        func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
            color = Color(viewController.selectedColor)
        }

        func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
            onDismiss()
        }
    }
}

private struct SettingsGeneralView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    @State private var previewQuote: BreakReminderQuote?
    @State private var lastPreviewQuoteID: String?
    @StateObject private var liveReactsPreviewCoordinator = LiveReactsCoordinator()

    var body: some View {
        ThemedSettingsForm {
            Section {
                LabeledContent("Break Reminder") {
                    Picker("Break Reminder", selection: breakReminderIntervalBinding) {
                        ForEach(BreakReminderInterval.allCases) { interval in
                            Text(interval.title).tag(interval)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Button {
                    presentPreviewReminder()
                } label: {
                    Label("Preview Break Reminder", systemImage: "hourglass.bottomhalf.filled")
                }

                SettingsToggleRow(
                    title: "Reaction Fountain",
                    isOn: Binding(
                        get: { appSettings.liveReactsEnabled },
                        set: { appSettings.liveReactsEnabled = $0 }
                    ),
                    footer: "Animate incoming reactions from the Pulse tab area in real time while Halo is open."
                )

                Button {
                    liveReactsPreviewCoordinator.emitPreviewSequence()
                } label: {
                    Label("Simulate Reaction Fountain", systemImage: "sparkles")
                }

                SettingsToggleRow(
                    title: "Hide NSFW Content",
                    isOn: Binding(
                        get: { appSettings.hideNSFWContent },
                        set: { appSettings.hideNSFWContent = $0 }
                    ),
                    footer: "Automatically hide notes tagged as NSFW."
                )

                SettingsToggleRow(
                    title: "Text Only Mode",
                    isOn: Binding(
                        get: { appSettings.textOnlyMode },
                        set: { appSettings.textOnlyMode = $0 }
                    ),
                    footer: "Strip media from notes and profiles to reduce bandwidth usage. Images and videos are replaced with placeholders."
                )

                SettingsToggleRow(
                    title: "Slow Connection Mode",
                    isOn: Binding(
                        get: { appSettings.slowConnectionMode },
                        set: { appSettings.slowConnectionMode = $0 }
                    ),
                    footer: "Connect only to relay.damus.io and hide reactions to reduce relay load."
                )
            } header: {
                Text("General")
            } footer: {
                Text("When enabled, Halo shows a gentle break reminder after the app has stayed open continuously for this long. Leaving the app or closing the reminder resets the timer. Use Preview to test the sheet right away.")
            }
        }
        .navigationTitle("General")
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if let previewQuote {
                BreakReminderOverlayPresentation(
                    quote: previewQuote,
                    onDismiss: dismissPreviewReminder
                )
            }
        }
        .overlay(alignment: .bottomTrailing) {
            GeometryReader { proxy in
                let previewWidth = max(84, min(proxy.size.width * 0.26, 118))

                LiveReactsOverlayHost(coordinator: liveReactsPreviewCoordinator)
                    .frame(width: previewWidth, height: 250, alignment: .bottom)
                    .offset(x: -18, y: -18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .allowsHitTesting(false)
        }
    }

    private var breakReminderIntervalBinding: Binding<BreakReminderInterval> {
        Binding(
            get: { appSettings.breakReminderInterval },
            set: { appSettings.breakReminderInterval = $0 }
        )
    }

    private func presentPreviewReminder() {
        let quote = BreakReminderQuote.next(excluding: lastPreviewQuoteID)
        lastPreviewQuoteID = quote.id

        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            previewQuote = quote
        }
    }

    private func dismissPreviewReminder() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            previewQuote = nil
        }
    }
}

private struct SettingsMediaView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    @State private var mediaCacheSizeDescription = "Calculating..."
    @State private var isClearingMediaCache = false
    @State private var isShowingClearMediaCacheConfirmation = false

    var body: some View {
        ThemedSettingsForm {
            Section {
                SettingsToggleRow(
                    title: "Blur Media From People I Don't Follow",
                    isOn: Binding(
                        get: { appSettings.blurMediaFromUnfollowedAuthors },
                        set: { appSettings.blurMediaFromUnfollowedAuthors = $0 }
                    ),
                    footer: "Images and videos from accounts you don't follow stay blurred until you tap to reveal them."
                )
            } header: {
                Text("Media")
            } footer: {
                Text("This only applies while you're signed in and does not blur your own posts.")
            }

            Section {
                LabeledContent("Stored Media") {
                    if isClearingMediaCache {
                        ProgressView()
                    } else {
                        Text(mediaCacheSizeDescription)
                            .foregroundStyle(.secondary)
                    }
                }

                NavigationLink {
                    SettingsMediaDiagnosticsView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Diagnostics")
                            .foregroundStyle(.primary)

                        Text("Cache hit rate, source breakdown, and payload totals.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }

                Button(role: .destructive) {
                    isShowingClearMediaCacheConfirmation = true
                } label: {
                    Text(isClearingMediaCache ? "Clearing..." : "Clear Media Cache")
                }
                .disabled(isClearingMediaCache)
            } header: {
                Text("Cache")
            } footer: {
                Text("Avatars and note images stay on disk so repeat visits and scrolling feel faster. Clearing this only removes cached media bytes, not your account or notes.")
            }
        }
        .navigationTitle("Media")
        .navigationBarTitleDisplayMode(.large)
        .alert("Clear Media Cache?", isPresented: $isShowingClearMediaCacheConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearMediaCache()
            }
        } message: {
            Text("This will remove cached avatars and note images from this device. Your account and notes will not be affected.")
        }
        .task {
            await refreshMediaCacheSize()
        }
    }

    private func refreshMediaCacheSize() async {
        let bytes = await FlowImageCache.shared.totalCacheSizeBytes()
        let description = bytes > 0
            ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            : "Empty"
        await MainActor.run {
            mediaCacheSizeDescription = description
        }
    }

    private func clearMediaCache() {
        guard !isClearingMediaCache else { return }
        isClearingMediaCache = true

        Task {
            await FlowImageCache.shared.clearAllCachedImages()
            await FlowImageCache.shared.resetDiagnostics()
            await refreshMediaCacheSize()
            await MainActor.run {
                isClearingMediaCache = false
            }
        }
    }
}

private struct SettingsMediaDiagnosticsView: View {
    @State private var diagnostics = FlowMediaCacheDiagnostics()
    @State private var flowDBDiagnostics = FlowNostrDBDiagnostics()

    var body: some View {
        ThemedSettingsForm {
            Section {
                diagnosticMetricRow(
                    title: "Cache Hit Rate",
                    value: cacheHitRateDescription
                )
                diagnosticMetricRow(
                    title: "Tracked Requests",
                    value: diagnostics.trackedRequestCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Cache Hits",
                    value: diagnostics.cacheHitCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Network-backed Misses",
                    value: diagnostics.cacheMissCount.formatted()
                )
            } header: {
                Text("Overview")
            } footer: {
                Text("Counts the current app session for on-demand requests that go through the shared Halo media cache. Background prefetch warmups are excluded.")
            }

            Section {
                diagnosticMetricRow(
                    title: "Image Memory Hits",
                    value: diagnostics.imageMemoryHitCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Data Memory Hits",
                    value: diagnostics.dataMemoryHitCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Disk Hits",
                    value: diagnostics.diskHitCount.formatted()
                )
                diagnosticMetricRow(
                    title: "URL Cache Hits",
                    value: diagnostics.urlCacheHitCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Network Fetches",
                    value: diagnostics.networkFetchCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Network Failures",
                    value: diagnostics.networkFailureCount.formatted()
                )
            } header: {
                Text("Request Sources")
            } footer: {
                Text("This covers the shared Halo media cache path. Some screens still use system image loading, and video playback has its own pipeline.")
            }

            Section {
                diagnosticMetricRow(
                    title: "Cached Payload",
                    value: byteDescription(diagnostics.cacheServedByteCount)
                )
                diagnosticMetricRow(
                    title: "Network Payload",
                    value: byteDescription(diagnostics.networkServedByteCount)
                )
            } header: {
                Text("Payload")
            } footer: {
                Text("Payload totals use the encoded media bytes known to the shared cache.")
            }

            Section {
                diagnosticMetricRow(
                    title: "DB Open",
                    value: flowDBDiagnostics.isOpen ? "Yes" : "No"
                )
                diagnosticMetricRow(
                    title: "DB Directory",
                    value: flowDBDiagnostics.databaseDirectoryExists ? "Present" : "Missing"
                )
                diagnosticMetricRow(
                    title: "Open Mapsize",
                    value: byteDescription(flowDBDiagnostics.openMapsizeBytes)
                )
                diagnosticMetricRow(
                    title: "Last Attempted Mapsize",
                    value: byteDescription(flowDBDiagnostics.lastAttemptedMapsizeBytes)
                )
                diagnosticMetricRow(
                    title: "Ingest Calls",
                    value: flowDBDiagnostics.ingestCallCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Successful Ingests",
                    value: flowDBDiagnostics.successfulIngestCallCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Persisted Events",
                    value: flowDBDiagnostics.persistedEventCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Persisted Profiles",
                    value: flowDBDiagnostics.persistedProfileCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Session Ingested Events",
                    value: flowDBDiagnostics.sessionIngestedEventCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Session Ingested Profiles",
                    value: flowDBDiagnostics.sessionIngestedProfileCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Local Event Lookups",
                    value: flowDBDiagnostics.eventLookupCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Local Profile Lookups",
                    value: flowDBDiagnostics.profileLookupCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Local Follow List Reads",
                    value: flowDBDiagnostics.followListLookupCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Local Timeline Queries",
                    value: flowDBDiagnostics.queryCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Recent Event Overlay",
                    value: flowDBDiagnostics.recentOverlayEventCount.formatted()
                )
                diagnosticMetricRow(
                    title: "Replaceable Overlay",
                    value: flowDBDiagnostics.recentReplaceableOverlayCount.formatted()
                )
                diagnosticMetricRow(
                    title: "On-Device Size",
                    value: byteDescription(flowDBDiagnostics.diskUsageBytes)
                )
            } header: {
                Text("Halo DB")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Persisted values reflect what is already committed into the local nostrdb store. Session ingested values reflect what the current app run has pushed through the ingester, even if writer threads have not finished compacting everything yet.")
                    Text("Path: \(flowDBDiagnostics.databasePath)")
                    if let error = flowDBDiagnostics.lastOpenError, !error.isEmpty {
                        Text("Last open error: \(error)")
                    }
                }
            }

            Section {
                Button("Reset Session Diagnostics", role: .destructive) {
                    resetDiagnostics()
                }
            } footer: {
                Text("Reset before a fresh troubleshooting pass if you want a clean session baseline.")
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshDiagnostics()
        }
        .refreshable {
            await refreshDiagnostics()
        }
    }

    private var cacheHitRateDescription: String {
        guard diagnostics.trackedRequestCount > 0 else { return "No data yet" }
        return diagnostics.cacheHitRate.formatted(
            .percent.precision(.fractionLength(1))
        )
    }

    @ViewBuilder
    private func diagnosticMetricRow(title: String, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func byteDescription(_ byteCount: Int64) -> String {
        guard byteCount > 0 else { return "0 bytes" }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func refreshDiagnostics() async {
        let snapshot = await FlowImageCache.shared.diagnosticsSnapshot()
        let flowDBSnapshot = FlowNostrDB.shared.diagnosticsSnapshot()
        await MainActor.run {
            diagnostics = snapshot
            flowDBDiagnostics = flowDBSnapshot
        }
    }

    private func resetDiagnostics() {
        Task {
            await FlowImageCache.shared.resetDiagnostics()
            FlowNostrDB.shared.resetSessionDiagnostics()
            await refreshDiagnostics()
        }
    }
}

private struct SettingsFeedsView: View {
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
        .navigationBarTitleDisplayMode(.large)
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

    fileprivate static let searchableRelayURLs: [URL] = [
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

private enum MutedContentTab: String, CaseIterable, Identifiable {
    case words = "Words"
    case users = "Users"

    var id: String { rawValue }
}

private struct SettingsMutedContentView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @ObservedObject private var muteStore = MuteStore.shared
    @State private var selectedTab: MutedContentTab = .words
    @State private var mutedUserProfiles: [String: NostrProfile] = [:]
    @State private var isLoadingMutedUsers = false

    var body: some View {
        ThemedSettingsForm {
            Section {
                FlowCapsuleTabBar(
                    selection: $selectedTab,
                    items: MutedContentTab.allCases,
                    title: { $0.rawValue }
                )
            }

            if selectedTab == .words {
                mutedWordsSections
            } else {
                mutedUsersSections
            }

            if let error = muteStore.lastPublishError, !error.isEmpty {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Muted Content")
        .navigationBarTitleDisplayMode(.large)
        .task {
            muteStore.configure(
                accountPubkey: auth.currentAccount?.pubkey,
                nsec: auth.currentNsec,
                readRelayURLs: relaySettings.readRelayURLs,
                writeRelayURLs: relaySettings.writeRelayURLs
            )
            muteStore.refreshFromRelay()
        }
        .task(id: mutedUsersFetchKey) {
            guard selectedTab == .users else { return }
            await loadMutedUserProfiles()
        }
        .onChange(of: selectedTab) { _, newValue in
            guard newValue == .users else { return }
            Task {
                await loadMutedUserProfiles()
            }
        }
    }

    @ViewBuilder
    private var mutedWordsSections: some View {
        Section {
            ForEach(orderedKeywordLists) { list in
                NavigationLink {
                    SettingsMutedKeywordListDetailView(listID: list.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Text(list.title)
                                .font(.body.weight(.medium))

                            Spacer(minLength: 8)

                            if list.allowsToggle {
                                Text(list.isEnabled ? "On" : "Off")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(list.isEnabled ? .secondary : .tertiary)
                            } else {
                                Text("Private")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text("\(list.wordCount) term\(list.wordCount == 1 ? "" : "s")")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text(list.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("Lists")
        } footer: {
            Text("Add any word, phrase, or hashtag to hide matching notes instantly across your feeds.")
        }
    }

    @ViewBuilder
    private var mutedUsersSections: some View {
        if orderedMutedPubkeys.isEmpty {
            Section {
                Text("No muted people yet.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Muted Users")
            } footer: {
                Text("Mute people from a note menu or profile, and they’ll appear here.")
            }
        } else {
            Section {
                if isLoadingMutedUsers && mutedUserProfiles.isEmpty {
                    ProgressView("Loading muted users...")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(orderedMutedPubkeys, id: \.self) { pubkey in
                    NavigationLink {
                        ProfileView(
                            pubkey: pubkey,
                            relayURL: effectivePrimaryRelayURL,
                            readRelayURLs: effectiveReadRelayURLs,
                            writeRelayURLs: effectiveWriteRelayURLs
                        )
                    } label: {
                        MutedUserRow(
                            pubkey: pubkey,
                            profile: mutedUserProfiles[pubkey]
                        )
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            muteStore.toggleMute(pubkey)
                        } label: {
                            Label("Unmute", systemImage: "speaker.wave.2")
                        }
                        .tint(.secondary)
                    }
                }
            } header: {
                Text("Muted Users")
            } footer: {
                Text("Muted people are hidden immediately. Unmute from here at any time.")
            }
        }
    }

    private var orderedKeywordLists: [MutedKeywordListState] {
        muteStore.mutedKeywordLists.sorted { lhs, rhs in
            if lhs.id == "other" { return true }
            if rhs.id == "other" { return false }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private var orderedMutedPubkeys: [String] {
        muteStore.mutedPubkeys.sorted()
    }

    private var effectiveReadRelayURLs: [URL] {
        let urls = relaySettings.readRelayURLs.isEmpty ? relaySettings.writeRelayURLs : relaySettings.readRelayURLs
        return urls.isEmpty ? [AppSettingsStore.slowModeRelayURL] : urls
    }

    private var effectiveWriteRelayURLs: [URL] {
        let urls = relaySettings.writeRelayURLs.isEmpty ? effectiveReadRelayURLs : relaySettings.writeRelayURLs
        return urls.isEmpty ? [AppSettingsStore.slowModeRelayURL] : urls
    }

    private var effectivePrimaryRelayURL: URL {
        effectiveReadRelayURLs.first ?? AppSettingsStore.slowModeRelayURL
    }

    private var mutedUsersFetchKey: String {
        let pubkeyKey = orderedMutedPubkeys.joined(separator: "|")
        let relayKey = effectiveReadRelayURLs.map(\.absoluteString).joined(separator: "|")
        return "\(selectedTab.rawValue)|\(pubkeyKey)|\(relayKey)"
    }

    @MainActor
    private func loadMutedUserProfiles() async {
        let pubkeys = orderedMutedPubkeys
        guard !pubkeys.isEmpty else {
            mutedUserProfiles = [:]
            isLoadingMutedUsers = false
            return
        }

        isLoadingMutedUsers = true
        let profiles = await NostrFeedService().fetchProfiles(
            relayURLs: effectiveReadRelayURLs,
            pubkeys: pubkeys
        )
        guard !Task.isCancelled else { return }
        mutedUserProfiles = profiles
        isLoadingMutedUsers = false
    }
}

private struct MutedUserRow: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    let pubkey: String
    let profile: NostrProfile?

    var body: some View {
        HStack(spacing: 12) {
            mutedUserAvatar

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Text(handle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let nip05, !nip05.isEmpty {
                    Text(nip05)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var mutedUserAvatar: some View {
        Group {
            if let avatarURL {
                CachedAsyncImage(url: avatarURL) { phase in
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
        .frame(width: 42, height: 42)
        .clipShape(Circle())
    }

    private var fallbackAvatar: some View {
        Circle()
            .fill(appSettings.themePalette.tertiaryFill)
            .overlay {
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
    }

    private var displayName: String {
        let trimmedDisplayName = profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedDisplayName, !trimmedDisplayName.isEmpty {
            return trimmedDisplayName
        }

        let trimmedName = profile?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, !trimmedName.isEmpty {
            return trimmedName
        }

        return shortNostrIdentifier(pubkey)
    }

    private var handle: String {
        let trimmedName = profile?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, !trimmedName.isEmpty {
            return "@\(trimmedName.lowercased())"
        }

        return "@\(shortNostrIdentifier(pubkey).lowercased())"
    }

    private var nip05: String? {
        let trimmed = profile?.nip05?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private var avatarURL: URL? {
        guard let rawValue = profile?.picture?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }
        return URL(string: rawValue)
    }
}

private struct SettingsMutedKeywordListDetailView: View {
    @ObservedObject private var muteStore = MuteStore.shared
    @State private var draftWord = ""

    let listID: String

    var body: some View {
        ThemedSettingsForm {
            if let list = currentList {
                if list.allowsToggle {
                    Section {
                        Toggle("Use this list", isOn: listEnabledBinding(for: list))
                    } footer: {
                        Text("Turn this off to stop filtering these terms without deleting the list.")
                    }
                }

                if list.allowsAddingWords {
                    Section("Add Term") {
                        TextField("Add word, phrase, or hashtag", text: $draftWord)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(addDraftWord)

                        Button("Add Term") {
                            addDraftWord()
                        }
                        .disabled(normalizedDraftWord.isEmpty)
                    }
                }

                Section {
                    if list.words.isEmpty {
                        Text("No terms in this list.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(list.words, id: \.self) { word in
                            HStack(spacing: 12) {
                                Text(word)
                                    .font(.body)

                                Spacer(minLength: 8)

                                if list.id != "other" {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }

                                Button {
                                    muteStore.removeWord(word, from: list.id)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(word)")
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    muteStore.removeWord(word, from: list.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Muted Terms")
                } footer: {
                    Text(list.allowsAddingWords
                         ? "Removing a term updates your private encrypted mute list immediately."
                         : "These are private muted terms already stored on your account.")
                }
            }

            if let error = muteStore.lastPublishError, !error.isEmpty {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(currentList?.title ?? "Muted Terms")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var currentList: MutedKeywordListState? {
        muteStore.mutedKeywordLists.first(where: { $0.id == listID })
    }

    private var normalizedDraftWord: String {
        draftWord
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func listEnabledBinding(for list: MutedKeywordListState) -> Binding<Bool> {
        Binding(
            get: {
                muteStore.mutedKeywordLists.first(where: { $0.id == list.id })?.isEnabled ?? list.isEnabled
            },
            set: { isEnabled in
                muteStore.setKeywordListEnabled(list.id, isEnabled: isEnabled)
            }
        )
    }

    private func addDraftWord() {
        let trimmed = normalizedDraftWord
        guard !trimmed.isEmpty else { return }
        muteStore.addWord(trimmed, to: listID)
        draftWord = ""
    }
}

private struct SettingsNotificationsView: View {
    var body: some View {
        NotificationPreferencesView()
    }
}
