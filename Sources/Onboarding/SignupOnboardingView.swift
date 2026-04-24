import NostrSDK
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor
struct SignupOnboardingView: View {
    private static let onboardingProfilePublishTimeout: TimeInterval = 3.5

    private enum Step: Int, CaseIterable {
        case name
        case about
        case image
        case interests
        case notifications
    }

    private enum PrimaryColorOption: String, CaseIterable, Identifiable {
        case coral
        case azure
        case emerald
        case violet
        case fuchsia
        case teal

        var id: String { rawValue }

        var title: String {
            switch self {
            case .coral:
                return "Coral"
            case .azure:
                return "Azure"
            case .emerald:
                return "Emerald"
            case .violet:
                return "Violet"
            case .fuchsia:
                return "Fuchsia"
            case .teal:
                return "Teal"
            }
        }

        var color: Color {
            switch self {
            case .coral:
                return Color(red: 1.00, green: 0.32, blue: 0.42)
            case .azure:
                return Color(red: 0.16, green: 0.52, blue: 0.95)
            case .emerald:
                return Color(red: 0.12, green: 0.67, blue: 0.44)
            case .violet:
                return Color(red: 0.58, green: 0.36, blue: 0.96)
            case .fuchsia:
                return Color(red: 0.92, green: 0.25, blue: 0.58)
            case .teal:
                return Color(red: 0.12, green: 0.66, blue: 0.67)
            }
        }
    }

    private enum OnboardingButtonStyleOption: Hashable, Identifiable {
        case solid(PrimaryColorOption)
        case holographic(HolographicGradientOption)

        static let defaultOption: Self = .holographic(.softHolographicSheen)

        static var allOptions: [Self] {
            PrimaryColorOption.allCases.map(Self.solid) +
                HolographicGradientOption.allCases.map(Self.holographic)
        }

        var id: String {
            switch self {
            case .solid(let option):
                return "solid-\(option.rawValue)"
            case .holographic(let option):
                return "holographic-\(option.rawValue)"
            }
        }

        var title: String {
            switch self {
            case .solid(let option):
                return option.title
            case .holographic(let option):
                return option.title
            }
        }

        var primaryColor: Color {
            switch self {
            case .solid(let option):
                return option.color
            case .holographic(let option):
                return option.defaultLinkColor
            }
        }

        var buttonTextColor: Color {
            switch self {
            case .solid:
                return .white
            case .holographic:
                return .black
            }
        }

        var buttonGradient: LinearGradient {
            switch self {
            case .solid(let option):
                return LinearGradient(
                    colors: [option.color, option.color],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .holographic(let option):
                return option.buttonGradient
            }
        }

        var bannerGradient: LinearGradient {
            switch self {
            case .solid(let option):
                return LinearGradient(
                    colors: [
                        option.color.opacity(0.92),
                        option.color.opacity(0.54),
                        Color(.systemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .holographic(let option):
                return option.uiGradient
            }
        }

        var isHolographic: Bool {
            if case .holographic = self {
                return true
            }
            return false
        }
    }

    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var relaySettings: RelaySettingsStore
    @EnvironmentObject private var appSettings: AppSettingsStore
    @Environment(\.colorScheme) private var colorScheme

    let canSwitchToSignIn: Bool
    let onSwitchToSignIn: () -> Void
    let onComplete: () -> Void

    @State private var step: Step = .name
    @State private var pendingAccount: GeneratedNostrAccount?
    @State private var displayName = ""
    @State private var handle = ""
    @State private var about = ""
    @State private var selectedButtonStyleOption: OnboardingButtonStyleOption = .defaultOption
    @State private var hasEditedHandle = false
    @State private var selectedTopics = Set<InterestTopic>()
    @State private var signupPrivateKeyBackupEnabled = true
    @State private var signupNotificationsEnabled = false
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var selectedAvatarData: Data?
    @State private var selectedAvatarPreviewImage: UIImage?
    @State private var selectedAvatarMIMEType = "image/jpeg"
    @State private var selectedAvatarFileExtension = "jpg"
    @State private var selectedBannerItem: PhotosPickerItem?
    @State private var selectedBannerData: Data?
    @State private var selectedBannerPreviewImage: UIImage?
    @State private var selectedBannerMIMEType = "image/jpeg"
    @State private var selectedBannerFileExtension = "jpg"
    @State private var isPreparingAccount = false
    @State private var isLoadingAvatar = false
    @State private var isLoadingBanner = false
    @State private var isFinishing = false
    @State private var errorMessage: String?
    @State private var animateFinishingButton = false

    private let relayClient = NostrRelayClient()

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    content

                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 20)
                    }

                    footerActions
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
            }
        }
        .background(Color(.systemBackground))
        .tint(onboardingInputTint)
        .task {
            await preparePendingAccountIfNeeded()
        }
        .onChange(of: selectedAvatarItem) { _, newValue in
            guard let newValue else { return }
            Task {
                await loadAvatar(from: newValue)
            }
        }
        .onChange(of: selectedBannerItem) { _, newValue in
            guard let newValue else { return }
            Task {
                await loadBanner(from: newValue)
            }
        }
        .onChange(of: displayName) { _, newValue in
            guard !hasEditedHandle else { return }
            handle = suggestedHandle(from: newValue)
        }
        .onChange(of: isFinishing) { _, isActive in
            guard isActive else {
                animateFinishingButton = false
                return
            }

            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                animateFinishingButton = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isPreparingAccount && pendingAccount == nil {
            VStack(spacing: 14) {
                ProgressView()
                Text("Creating your account…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            switch step {
            case .name:
                nameStep
            case .image:
                imageStep
            case .about:
                aboutStep
            case .interests:
                interestsStep
            case .notifications:
                notificationsStep
            }
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepIntro(
                title: "What should we call you?",
                subtitle: "We’ll use this on your profile. You can change it later."
            )

            onboardingFieldCard {
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Name")
                    TextField("Enter your name", text: $displayName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .font(.body)
                }
            }

            onboardingFieldCard {
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("Handle")
                    HStack(spacing: 8) {
                        Text("@")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("yourhandle", text: handleBinding)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body)
                    }
                }
            }
        }
    }

    private var imageStep: some View {
        let avatarIsLoading = isLoadingAvatar
        let bannerIsLoading = isLoadingBanner
        let uploadButtonTextColor = selectedButtonStyleOption.buttonTextColor
        let uploadButtonGradient = selectedButtonStyleOption.buttonGradient

        return VStack(alignment: .leading, spacing: 18) {
            stepIntro(
                title: "Make it feel like you.",
                subtitle: "Pick a banner style or upload your own image. You can change all of this later."
            )

            OnboardingProfilePreviewCard(
                displayName: welcomeName,
                handle: normalizedHandle,
                about: about,
                avatarPreviewImage: selectedAvatarPreviewImage,
                bannerPreviewImage: selectedBannerPreviewImage,
                styleOption: selectedButtonStyleOption
            )

            onboardingFieldCard {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Banner & Buttons")
                        Text(selectedButtonStyleOption.title)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(OnboardingButtonStyleOption.allOptions) { option in
                                buttonStyleChip(for: option)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollClipDisabled()

                    HStack(spacing: 10) {
                        PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                            OnboardingImageUploadButton(
                                title: "Profile photo",
                                systemImage: "person.crop.circle",
                                isLoading: avatarIsLoading,
                                foregroundColor: uploadButtonTextColor,
                                backgroundGradient: uploadButtonGradient
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isFinishing || isLoadingAvatar || isLoadingBanner)

                        PhotosPicker(selection: $selectedBannerItem, matching: .images) {
                            OnboardingImageUploadButton(
                                title: "Banner image",
                                systemImage: "photo.on.rectangle.angled",
                                isLoading: bannerIsLoading,
                                foregroundColor: uploadButtonTextColor,
                                backgroundGradient: uploadButtonGradient
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isFinishing || isLoadingAvatar || isLoadingBanner)
                    }
                }
            }
        }
    }

    private var aboutStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepIntro(
                title: "A preview of you",
                subtitle: "Write a short bio now, or skip and shape this later."
            )

            onboardingFieldCard {
                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel("About you")

                    ZStack(alignment: .topLeading) {
                        if about.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Tell people a little about yourself…")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $about)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled(false)
                    }
                    .font(.body)
                    .frame(minHeight: 124)
                    .scrollContentBackground(.hidden)
                }
            }
        }
    }

    private var interestsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepIntro(
                title: "Pick your interests",
                subtitle: "Choose a few topics to shape your first feed."
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 140), spacing: 10),
                    GridItem(.flexible(minimum: 140), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(InterestTopic.allCases) { topic in
                    interestChip(for: topic)
                }
            }
        }
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepIntro(
                title: "Protect your account",
                subtitle: "Your Interests feed is ready. We’ll save your private key in Keychain. Keep iCloud backup on to restore it on your devices."
            )

            onboardingFieldCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "icloud.and.arrow.up.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(onboardingSecondaryAccent)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("iCloud Keychain Backup")
                                .font(.headline)

                            Text("Keep a private backup so you can restore this account on another device.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Back Up Private Key", isOn: privateKeyBackupBinding)
                        .tint(onboardingToggleTint)

                    Text(signupPrivateKeyBackupStatusDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            onboardingFieldCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(onboardingSecondaryAccent)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Stay in Halo")
                                .font(.headline)

                            Text("Enable notifications here and iOS will ask for permission right away.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Enable Notifications", isOn: notificationsBinding)
                        .tint(onboardingToggleTint)

                    Text(signupNotificationsStatusDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var footerActions: some View {
        VStack(spacing: 12) {
            Button {
                handlePrimaryAction()
            } label: {
                HStack(spacing: 8) {
                    if isFinishing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(primaryButtonForeground)
                    }
                    Text(primaryButtonTitle)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(primaryButtonBackground, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(primaryButtonBorder, lineWidth: 1)
                }
                .foregroundStyle(primaryButtonForeground)
                .scaleEffect(isFinishing && animateFinishingButton ? 0.985 : 1)
                .shadow(
                    color: primaryButtonShadowColor,
                    radius: primaryButtonShadowRadius,
                    y: primaryButtonShadowYOffset
                )
            }
            .buttonStyle(.plain)
            .disabled(primaryActionDisabled)

            HStack {
                if step != .name {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            errorMessage = nil
                            switch step {
                            case .name:
                                break
                            case .about:
                                step = .name
                            case .image:
                                step = .about
                            case .interests:
                                step = .image
                            case .notifications:
                                step = .interests
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if canSkipCurrentStep {
                    Button("Skip for now") {
                        advanceFromOptionalStep()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 4)
        }
        .padding(.bottom, 18)
    }

    private func onboardingFieldCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func stepIntro(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom("SF Pro Display", size: 31).weight(.bold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func interestChip(for topic: InterestTopic) -> some View {
        let isSelected = selectedTopics.contains(topic)

        return Button {
            if isSelected {
                selectedTopics.remove(topic)
            } else {
                selectedTopics.insert(topic)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: topic.iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? onboardingChipSelectedForeground : onboardingSecondaryAccent)

                Text(topic.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? onboardingChipSelectedForeground : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(onboardingChipSelectedForeground.opacity(0.92))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? onboardingChipSelectedFill : AnyShapeStyle(onboardingChipFill))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isSelected ? onboardingChipSelectedStroke : Color(.separator).opacity(0.28),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func buttonStyleChip(for option: OnboardingButtonStyleOption) -> some View {
        let isSelected = selectedButtonStyleOption == option

        return Button {
            selectedButtonStyleOption = option
        } label: {
            Circle()
                .fill(option.buttonGradient)
                .frame(width: 42, height: 42)
                .overlay {
                    Circle()
                        .stroke(
                            isSelected ? Color.white.opacity(0.95) : Color.white.opacity(0.24),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                }
                .overlay {
                    Circle()
                        .stroke(Color.black.opacity(isSelected ? 0.18 : 0.08), lineWidth: 0.8)
                }
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(option.buttonTextColor, option.primaryColor.opacity(0.95))
                            .background(Circle().fill(Color.white))
                            .offset(x: 2, y: 2)
                    }
                }
                .shadow(
                    color: option.primaryColor.opacity(isSelected ? 0.24 : 0.12),
                    radius: isSelected ? 10 : 6,
                    y: 4
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var handleBinding: Binding<String> {
        Binding(
            get: { handle },
            set: { newValue in
                hasEditedHandle = true
                handle = normalizeHandle(newValue)
            }
        )
    }

    private var primaryButtonTitle: String {
        switch step {
        case .name:
            return "Continue"
        case .image:
            return "Continue"
        case .about:
            return "Continue"
        case .interests:
            return "Continue"
        case .notifications:
            return isFinishing ? "Generating your feed…" : "Finish"
        }
    }

    private var primaryActionDisabled: Bool {
        if isPreparingAccount || isLoadingAvatar || isLoadingBanner || isFinishing || pendingAccount == nil {
            return true
        }

        switch step {
        case .name:
            return normalizedDisplayName.isEmpty || normalizedHandle.isEmpty
        case .image:
            return false
        case .about:
            return false
        case .interests:
            return selectedTopics.isEmpty
        case .notifications:
            return false
        }
    }

    private var primaryButtonBackground: AnyShapeStyle {
        primaryActionDisabled
            ? AnyShapeStyle(Color(.tertiarySystemFill))
            : AnyShapeStyle(onboardingPrimaryButtonFill)
    }

    private var primaryButtonForeground: Color {
        primaryActionDisabled ? Color(.secondaryLabel) : onboardingPrimaryButtonForeground
    }

    private var primaryButtonBorder: Color {
        if primaryActionDisabled {
            return Color(.separator).opacity(0.16)
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.08)
            : onboardingInk.opacity(0.16)
    }

    private var primaryButtonShadowColor: Color {
        guard !primaryActionDisabled else { return .clear }
        if isFinishing {
            return Color.black.opacity(animateFinishingButton ? 0.18 : 0.10)
        }
        return colorScheme == .light ? Color.black.opacity(0.08) : .clear
    }

    private var primaryButtonShadowRadius: CGFloat {
        if isFinishing {
            return 18
        }
        return colorScheme == .light && !primaryActionDisabled ? 10 : 0
    }

    private var primaryButtonShadowYOffset: CGFloat {
        if isFinishing {
            return 8
        }
        return colorScheme == .light && !primaryActionDisabled ? 5 : 0
    }

    private var onboardingInk: Color {
        Color(red: 0.06, green: 0.10, blue: 0.18)
    }

    private var onboardingPrimaryButtonFill: LinearGradient {
        selectedButtonStyleOption.buttonGradient
    }

    private var onboardingPrimaryButtonForeground: Color {
        selectedButtonStyleOption.buttonTextColor
    }

    private var onboardingSecondaryAccent: Color {
        Color(.secondaryLabel)
    }

    private var onboardingToggleTint: Color {
        Color(.systemGreen)
    }

    private var onboardingInputTint: Color {
        colorScheme == .dark ? .white : onboardingInk
    }

    private var onboardingChipFill: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : Color(.systemGray6)
    }

    private var onboardingChipSelectedFill: AnyShapeStyle {
        AnyShapeStyle(selectedButtonStyleOption.buttonGradient)
    }

    private var onboardingChipSelectedForeground: Color {
        selectedButtonStyleOption.buttonTextColor
    }

    private var onboardingChipSelectedStroke: Color {
        selectedButtonStyleOption.primaryColor.opacity(colorScheme == .dark ? 0.54 : 0.38)
    }

    private var normalizedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedHandle: String {
        normalizeHandle(handle.isEmpty ? suggestedHandle(from: displayName) : handle)
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { signupNotificationsEnabled },
            set: { signupNotificationsEnabled = $0 }
        )
    }

    private var privateKeyBackupBinding: Binding<Bool> {
        Binding(
            get: { signupPrivateKeyBackupEnabled },
            set: { signupPrivateKeyBackupEnabled = $0 }
        )
    }

    private var signupPrivateKeyBackupStatusDescription: String {
        signupPrivateKeyBackupEnabled
            ? "On. Your private key will be saved to iCloud Keychain so you can restore it on your devices."
            : "Off. Your private key will stay in this device’s Keychain and will not sync to iCloud."
    }

    private var signupNotificationsStatusDescription: String {
        signupNotificationsEnabled
            ? "iOS will ask for permission when you finish."
            : "Off for now. You can change this later in Settings."
    }

    private var welcomeName: String {
        normalizedDisplayName.isEmpty ? "there" : normalizedDisplayName
    }

    private var canSkipCurrentStep: Bool {
        switch step {
        case .image, .about:
            return true
        case .name, .interests, .notifications:
            return false
        }
    }

    private func handlePrimaryAction() {
        errorMessage = nil

        switch step {
        case .name:
            guard !normalizedDisplayName.isEmpty else {
                errorMessage = "Enter your name to continue."
                return
            }
            guard !normalizedHandle.isEmpty else {
                errorMessage = "Pick a handle to continue."
                return
            }
            withAnimation(.easeInOut(duration: 0.18)) {
                step = .about
            }

        case .about:
            withAnimation(.easeInOut(duration: 0.18)) {
                step = .image
            }

        case .image:
            withAnimation(.easeInOut(duration: 0.18)) {
                step = .interests
            }

        case .interests:
            withAnimation(.easeInOut(duration: 0.18)) {
                step = .notifications
            }

        case .notifications:
            Task {
                await finishSignup()
            }
        }
    }

    private func advanceFromOptionalStep() {
        errorMessage = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            switch step {
            case .about:
                step = .image
            case .image:
                step = .interests
            case .notifications:
                break
            case .name, .interests:
                break
            }
        }
    }

    @MainActor
    private func preparePendingAccountIfNeeded() async {
        guard pendingAccount == nil, !isPreparingAccount else { return }
        isPreparingAccount = true
        defer { isPreparingAccount = false }

        guard let keypair = Keypair() else {
            errorMessage = "Couldn’t generate a new keypair right now."
            return
        }

        pendingAccount = GeneratedNostrAccount(
            pubkey: keypair.publicKey.hex,
            npub: keypair.publicKey.npub,
            nsec: keypair.privateKey.nsec
        )
    }

    @MainActor
    private func loadAvatar(from item: PhotosPickerItem) async {
        guard !isLoadingAvatar else { return }
        isLoadingAvatar = true
        errorMessage = nil

        defer {
            isLoadingAvatar = false
            selectedAvatarItem = nil
        }

        do {
            let preparedMedia = try await MediaUploadPreparation.prepareProfileImageUpload(from: item)
            selectedAvatarData = preparedMedia.data
            selectedAvatarPreviewImage = preparedMedia.previewImage ?? UIImage(data: preparedMedia.data)
            selectedAvatarMIMEType = preparedMedia.mimeType
            selectedAvatarFileExtension = preparedMedia.fileExtension
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func loadBanner(from item: PhotosPickerItem) async {
        guard !isLoadingBanner else { return }
        isLoadingBanner = true
        errorMessage = nil

        defer {
            isLoadingBanner = false
            selectedBannerItem = nil
        }

        do {
            let preparedMedia = try await MediaUploadPreparation.prepareProfileBannerUpload(from: item)
            selectedBannerData = preparedMedia.data
            selectedBannerPreviewImage = preparedMedia.previewImage ?? UIImage(data: preparedMedia.data)
            selectedBannerMIMEType = preparedMedia.mimeType
            selectedBannerFileExtension = preparedMedia.fileExtension
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func finishSignup() async {
        guard !isFinishing, let pendingAccount else { return }
        isFinishing = true
        errorMessage = nil

        do {
            let account = try auth.loginWithNsecOrHex(
                pendingAccount.nsec,
                backupPrivateKeyToICloud: signupPrivateKeyBackupEnabled
            )
            onComplete()

            appSettings.configure(accountPubkey: account.pubkey)
            appSettings.theme = .system
            applySelectedButtonStyle()
            if signupNotificationsEnabled {
                appSettings.notificationsEnabled = true
            }

            relaySettings.configure(accountPubkey: account.pubkey, nsec: auth.currentNsec ?? pendingAccount.nsec)
            relaySettings.seedDefaultRelaysForCurrentAccount(publishToBootstrapRelays: true)

            let avatarURL: String?
            do {
                avatarURL = try await uploadAvatarIfNeeded(using: pendingAccount)
            } catch {
                avatarURL = nil
            }

            let bannerURL: String?
            do {
                bannerURL = try await uploadBannerIfNeeded(using: pendingAccount)
            } catch {
                bannerURL = nil
            }

            let interestTopics = InterestTopic.allCases.filter { selectedTopics.contains($0) }
            let interestHashtags = InterestTopic.combinedHashtags(for: interestTopics)

            try? await publishProfileMetadata(
                account: pendingAccount,
                displayName: normalizedDisplayName,
                handle: normalizedHandle,
                about: about.trimmingCharacters(in: .whitespacesAndNewlines),
                avatarURLString: avatarURL,
                bannerURLString: bannerURL
            )

            InterestFeedStore.shared.configure(accountPubkey: pendingAccount.pubkey)
            InterestFeedStore.shared.seedFromOnboarding(interestTopics)
            if interestHashtags.isEmpty {
                InterestFeedStore.shared.setHashtags([])
            }

            UserDefaults.standard.set(
                HomePrimaryFeedSource.interests.storageValue,
                forKey: HomeFeedViewModel.persistedFeedSourceKey(pubkey: pendingAccount.pubkey.lowercased())
            )

            isFinishing = false
            return
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isFinishing = false
    }

    private func uploadAvatarIfNeeded(using account: GeneratedNostrAccount) async throws -> String? {
        guard let selectedAvatarData, !selectedAvatarData.isEmpty else { return nil }

        let filename = "avatar-\(Int(Date().timeIntervalSince1970)).\(selectedAvatarFileExtension)"
        let url = try await ProfileMediaUploadService.shared.uploadProfileImage(
            data: selectedAvatarData,
            mimeType: selectedAvatarMIMEType,
            filename: filename,
            nsec: account.nsec
        )
        return url.absoluteString
    }

    private func uploadBannerIfNeeded(using account: GeneratedNostrAccount) async throws -> String? {
        guard let selectedBannerData, !selectedBannerData.isEmpty else { return nil }

        let filename = "banner-\(Int(Date().timeIntervalSince1970)).\(selectedBannerFileExtension)"
        let url = try await ProfileMediaUploadService.shared.uploadProfileImage(
            data: selectedBannerData,
            mimeType: selectedBannerMIMEType,
            filename: filename,
            nsec: account.nsec
        )
        return url.absoluteString
    }

    private func applySelectedButtonStyle() {
        appSettings.primaryColor = selectedButtonStyleOption.primaryColor
        appSettings.buttonTextColor = selectedButtonStyleOption.buttonTextColor

        switch selectedButtonStyleOption {
        case .solid:
            appSettings.clearButtonGradient()
        case .holographic(let option):
            appSettings.buttonGradientOption = option
        }
    }

    private func publishProfileMetadata(
        account: GeneratedNostrAccount,
        displayName: String,
        handle: String,
        about: String,
        avatarURLString: String?,
        bannerURLString: String?
    ) async throws {
        guard let keypair = Keypair(nsec: account.nsec.lowercased()) else {
            throw AuthManagerError.invalidNsecOrHex
        }

        let fields = EditableProfileFields(
            avatarURLString: avatarURLString ?? "",
            bannerURLString: bannerURLString ?? "",
            displayName: displayName,
            handle: handle,
            about: about,
            website: "",
            nip05: "",
            lightningAddress: ""
        )
        let content = try ProfileMetadataEditing.mergedContent(
            fields: fields,
            baseJSON: ["name": handle]
        )
        let event = try NostrSDK.NostrEvent.Builder<NostrSDK.NostrEvent>(kind: .metadata)
            .content(content)
            .build(signedBy: keypair)

        let eventData = try JSONEncoder().encode(event)

        let relayURLs = appSettings.effectiveWriteRelayURLs(
            from: relaySettings.writeRelayURLs,
            fallbackReadRelayURLs: relaySettings.readRelayURLs
        )
        let publishCoordinator = OnboardingProfilePublishCoordinator(
            expectedRelayCount: relayURLs.count
        )
        for relayURL in relayURLs {
            let publishEventData = eventData
            let eventID = event.id
            Task.detached(priority: .userInitiated) { [relayClient] in
                do {
                    try await relayClient.publishEvent(
                        relayURL: relayURL,
                        eventData: publishEventData,
                        eventID: eventID,
                        timeout: Self.onboardingProfilePublishTimeout
                    )
                    await publishCoordinator.recordSuccess(relayURL)
                } catch {
                    await publishCoordinator.recordFailure(error)
                }
            }
        }

        _ = try await publishCoordinator.waitForFirstSuccess()

        let localEvent = NostrEvent(
            id: event.id.lowercased(),
            pubkey: event.pubkey.lowercased(),
            createdAt: Int(event.createdAt),
            kind: event.kind.rawValue,
            tags: event.tags.map { [$0.name, $0.value] + $0.otherParameters },
            content: event.content,
            sig: event.signature ?? ""
        )
        await SeenEventStore.shared.store(events: [localEvent])

        if let profile = NostrProfile.decode(from: content) {
            await ProfileCache.shared.store(profiles: [account.pubkey.lowercased(): profile], missed: [])
        }
        NotificationCenter.default.post(
            name: .profileMetadataUpdated,
            object: nil,
            userInfo: ["pubkey": account.pubkey.lowercased()]
        )
    }

    private struct OnboardingImageUploadButton: View {
        let title: String
        let systemImage: String
        let isLoading: Bool
        let foregroundColor: Color
        let backgroundGradient: LinearGradient

        var body: some View {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(foregroundColor)
                } else {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                }

                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .foregroundStyle(foregroundColor)
            .background(backgroundGradient, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(0.10), lineWidth: 0.8)
            }
        }
    }

    private struct OnboardingProfilePreviewCard: View {
        let displayName: String
        let handle: String
        let about: String
        let avatarPreviewImage: UIImage?
        let bannerPreviewImage: UIImage?
        let styleOption: OnboardingButtonStyleOption

        private static let bannerHeight: CGFloat = 132
        private static let avatarSize: CGFloat = 82

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                previewBanner

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom, spacing: 12) {
                        previewAvatar

                        Spacer(minLength: 0)

                        HStack(spacing: 8) {
                            previewIconCapsule(systemImage: "qrcode")
                            previewIconCapsule(systemImage: "ellipsis")
                            previewFollowCapsule
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(resolvedDisplayName)
                            .font(.system(size: 24, weight: .heavy, design: .default))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(resolvedHandle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(resolvedAbout)
                        .font(.body)
                        .foregroundStyle(about.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, -(Self.avatarSize / 2))
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color(.separator).opacity(0.18), lineWidth: 0.8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 8)
        }

        private var resolvedDisplayName: String {
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Your Name" : trimmed
        }

        private var resolvedHandle: String {
            let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return "@\(trimmed)"
            }

            return "@halo"
        }

        private var resolvedAbout: String {
            let trimmed = about.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Your bio preview will appear here." : trimmed
        }

        private var previewBanner: some View {
            ZStack {
                previewBannerContent

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.08),
                        .clear,
                        Color(.secondarySystemBackground).opacity(0.34)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.bannerHeight)
            .clipped()
        }

        @ViewBuilder
        private var previewBannerContent: some View {
            if let bannerPreviewImage {
                Image(uiImage: bannerPreviewImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle()
                        .fill(styleOption.bannerGradient)

                    Circle()
                        .fill(Color.white.opacity(styleOption.isHolographic ? 0.36 : 0.22))
                        .frame(width: 126, height: 126)
                        .blur(radius: 20)
                        .offset(x: 116, y: -38)

                    Circle()
                        .fill(styleOption.primaryColor.opacity(0.24))
                        .frame(width: 154, height: 154)
                        .blur(radius: 24)
                        .offset(x: -118, y: 48)
                }
            }
        }

        private var previewAvatar: some View {
            Group {
                if let avatarPreviewImage {
                    Image(uiImage: avatarPreviewImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Circle()
                            .fill(styleOption.buttonGradient)

                        Text(String(resolvedDisplayName.prefix(1)).uppercased())
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(styleOption.buttonTextColor)
                    }
                }
            }
            .frame(width: Self.avatarSize, height: Self.avatarSize)
            .background(Circle().fill(Color(.systemBackground)))
            .clipShape(Circle())
            .overlay {
                Circle().stroke(Color(.secondarySystemBackground), lineWidth: 4)
            }
            .overlay {
                Circle().stroke(Color(.separator).opacity(0.22), lineWidth: 0.8)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 12, y: 7)
        }

        private func previewIconCapsule(systemImage: String) -> some View {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 38, height: 36)
                .background(Color(.tertiarySystemFill), in: Capsule(style: .continuous))
        }

        private var previewFollowCapsule: some View {
            Text("Follow")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(styleOption.buttonTextColor)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(styleOption.buttonGradient, in: Capsule(style: .continuous))
        }
    }

    private func suggestedHandle(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return normalizeHandle(trimmed)
    }

    private func normalizeHandle(_ value: String) -> String {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))

        let filtered = trimmed.filter { character in
            if character == "_" || character == "." {
                return true
            }
            return character.unicodeScalars.allSatisfy { scalar in
                CharacterSet.alphanumerics.contains(scalar) || CharacterSet.letters.contains(scalar)
            }
        }
        return filtered.lowercased()
    }
}

private actor OnboardingProfilePublishCoordinator {
    private let expectedRelayCount: Int
    private var completedFailureCount = 0
    private var firstSuccessfulRelay: URL?
    private var firstError: Error?
    private var continuation: CheckedContinuation<URL, Error>?
    private var isResolved = false

    init(expectedRelayCount: Int) {
        self.expectedRelayCount = expectedRelayCount
    }

    func waitForFirstSuccess() async throws -> URL {
        if let firstSuccessfulRelay {
            return firstSuccessfulRelay
        }

        if completedFailureCount >= expectedRelayCount {
            throw firstError ?? RelayClientError.publishRejected("Couldn’t publish your profile yet.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func recordSuccess(_ relayURL: URL) {
        guard !isResolved else { return }
        firstSuccessfulRelay = relayURL
        isResolved = true
        continuation?.resume(returning: relayURL)
        continuation = nil
    }

    func recordFailure(_ error: Error) {
        guard !isResolved else { return }
        completedFailureCount += 1
        if firstError == nil {
            firstError = error
        }

        guard completedFailureCount >= expectedRelayCount else { return }
        isResolved = true
        continuation?.resume(
            throwing: firstError ?? RelayClientError.publishRejected("Couldn’t publish your profile yet.")
        )
        continuation = nil
    }
}
