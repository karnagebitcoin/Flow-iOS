import PhotosUI
import SwiftUI
import UIKit

struct ProfileEditorSheet: View {
    enum UploadTarget {
        case avatar
        case banner
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettingsStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var fields: EditableProfileFields
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var selectedBannerItem: PhotosPickerItem?
    @State private var avatarPreviewImage: UIImage?
    @State private var bannerPreviewImage: UIImage?
    @State private var isUploadingAvatar = false
    @State private var isUploadingBanner = false
    @State private var avatarUploadError: String?
    @State private var bannerUploadError: String?

    let previewHandle: String
    let followingCount: Int
    let isSaving: Bool
    let errorMessage: String?
    let onSave: (EditableProfileFields) async -> Bool
    let onUploadAvatar: (Data, String, String) async throws -> String
    let onUploadBanner: (Data, String, String) async throws -> String

    init(
        initialFields: EditableProfileFields,
        previewHandle: String,
        followingCount: Int,
        isSaving: Bool,
        errorMessage: String?,
        onSave: @escaping (EditableProfileFields) async -> Bool,
        onUploadAvatar: @escaping (Data, String, String) async throws -> String,
        onUploadBanner: @escaping (Data, String, String) async throws -> String
    ) {
        _fields = State(initialValue: initialFields)
        self.previewHandle = previewHandle
        self.followingCount = followingCount
        self.isSaving = isSaving
        self.errorMessage = errorMessage
        self.onSave = onSave
        self.onUploadAvatar = onUploadAvatar
        self.onUploadBanner = onUploadBanner
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    previewSection
                    imagesSection
                    profileSection
                    linksSection
                    errorsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 120)
            }
            .background(appSettings.themePalette.groupedBackground.ignoresSafeArea())
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .disabled(isBusy)
                }
            }
            .safeAreaInset(edge: .bottom) {
                saveBar
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: selectedAvatarItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await uploadImage(from: newItem, target: .avatar)
            }
        }
        .onChange(of: selectedBannerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await uploadImage(from: newItem, target: .banner)
            }
        }
    }

    private var isBusy: Bool {
        isSaving || isUploadingAvatar || isUploadingBanner
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Live Preview",
                subtitle: "See how your profile will look before you save."
            )

            ProfileEditorPreviewCard(
                fields: fields,
                previewHandle: previewHandle,
                followingCount: followingCount,
                avatarPreviewImage: avatarPreviewImage,
                bannerPreviewImage: bannerPreviewImage
            )
        }
    }

    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Images",
                subtitle: "Upload or paste links for your avatar and banner."
            )

            editorCard {
                VStack(alignment: .leading, spacing: 16) {
                    imageUploadRow(
                        title: "Banner",
                        systemImage: "photo.stack",
                        placeholder: "Banner URL",
                        text: $fields.bannerURLString,
                        isUploading: isUploadingBanner,
                        errorMessage: bannerUploadError,
                        selection: $selectedBannerItem,
                        accessibilityLabel: "Upload profile banner"
                    )

                    Divider()

                    imageUploadRow(
                        title: "Profile Photo",
                        systemImage: "person.crop.circle",
                        placeholder: "Avatar URL",
                        text: $fields.avatarURLString,
                        isUploading: isUploadingAvatar,
                        errorMessage: avatarUploadError,
                        selection: $selectedAvatarItem,
                        accessibilityLabel: "Upload profile photo"
                    )
                }
            }
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Profile",
                subtitle: "Your name and bio update the preview in real time."
            )

            editorCard {
                VStack(alignment: .leading, spacing: 16) {
                    labeledField("Display Name", systemImage: "person") {
                        TextField("Display Name", text: $fields.displayName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }

                    labeledField("Bio", systemImage: "text.alignleft", topAligned: true) {
                        TextField("Tell people about yourself", text: $fields.about, axis: .vertical)
                            .lineLimit(4...8)
                            .textInputAutocapitalization(.sentences)
                    }
                }
            }
        }
    }

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Links & Payments",
                subtitle: "These appear underneath your bio when present."
            )

            editorCard {
                VStack(alignment: .leading, spacing: 16) {
                    labeledField("Website", systemImage: "globe") {
                        TextField("Website", text: $fields.website)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                    }

                    labeledField("Payment Address", systemImage: "bolt.fill") {
                        TextField("", text: $fields.lightningAddress)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var errorsSection: some View {
        if let avatarUploadError, !avatarUploadError.isEmpty {
            errorCard(message: avatarUploadError)
        }

        if let bannerUploadError, !bannerUploadError.isEmpty {
            errorCard(message: bannerUploadError)
        }

        if let errorMessage, !errorMessage.isEmpty {
            errorCard(message: errorMessage)
        }
    }

    private var saveBar: some View {
        VStack(spacing: 10) {
            Button {
                save()
            } label: {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(saveButtonForeground)
                    }

                    Text("Save Changes")
                        .font(.headline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(saveButtonForeground)
                .background(saveButtonBackground, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(saveButtonBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
    }

    private var saveButtonBackground: Color {
        isBusy ? Color(.tertiarySystemFill) : appSettings.primaryColor
    }

    private var saveButtonForeground: Color {
        if isBusy {
            return Color(.secondaryLabel)
        }
        return colorScheme == .dark ? .black : .white
    }

    private var saveButtonBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(appSettings.appFont(.headline, weight: .bold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(appSettings.appFont(.footnote))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func editorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(appSettings.themePalette.secondaryGroupedBackground)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(appSettings.themePalette.separator.opacity(0.18), lineWidth: 0.8)
            }
    }

    private func labeledField<Content: View>(
        _ title: String,
        systemImage: String,
        topAligned: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: topAligned ? .top : .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .padding(.top, topAligned ? 4 : 0)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(appSettings.appFont(.footnote, weight: .semibold))
                    .foregroundStyle(.secondary)

                content()
                    .font(appSettings.appFont(.body))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func imageUploadRow(
        title: String,
        systemImage: String,
        placeholder: String,
        text: Binding<String>,
        isUploading: Bool,
        errorMessage: String?,
        selection: Binding<PhotosPickerItem?>,
        accessibilityLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(appSettings.appFont(.footnote, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField(placeholder, text: text)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .font(appSettings.appFont(.body))
                }

                PhotosPicker(selection: selection, matching: .images) {
                    HStack(spacing: 6) {
                        if isUploading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                        }

                        Text(isUploading ? "Uploading" : "Upload")
                    }
                    .font(appSettings.appFont(.footnote, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(appSettings.themePalette.tertiaryFill)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityLabel(accessibilityLabel)
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(appSettings.appFont(.footnote))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func errorCard(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(appSettings.appFont(.footnote))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(appSettings.themePalette.secondaryGroupedBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.18), lineWidth: 0.9)
        }
    }

    private func save() {
        Task {
            let didSave = await onSave(fields)
            if didSave {
                dismiss()
            }
        }
    }

    @MainActor
    private func uploadImage(from item: PhotosPickerItem, target: UploadTarget) async {
        switch target {
        case .avatar:
            guard !isUploadingAvatar else { return }
            isUploadingAvatar = true
            avatarUploadError = nil
        case .banner:
            guard !isUploadingBanner else { return }
            isUploadingBanner = true
            bannerUploadError = nil
        }

        defer {
            switch target {
            case .avatar:
                isUploadingAvatar = false
                selectedAvatarItem = nil
            case .banner:
                isUploadingBanner = false
                selectedBannerItem = nil
            }
        }

        do {
            let preparedMedia = try await MediaUploadPreparation.prepareUploadMedia(from: item)
            let timestamp = Int(Date().timeIntervalSince1970)
            let filenamePrefix = target == .avatar ? "profile" : "profile-banner"
            let filename = "\(filenamePrefix)-\(timestamp).\(preparedMedia.fileExtension)"

            if let previewImage = UIImage(data: preparedMedia.data) {
                switch target {
                case .avatar:
                    avatarPreviewImage = previewImage
                case .banner:
                    bannerPreviewImage = previewImage
                }
            }

            let uploadedURL: String
            switch target {
            case .avatar:
                uploadedURL = try await onUploadAvatar(
                    preparedMedia.data,
                    preparedMedia.mimeType,
                    filename
                )
                fields.avatarURLString = uploadedURL
                avatarUploadError = nil
            case .banner:
                uploadedURL = try await onUploadBanner(
                    preparedMedia.data,
                    preparedMedia.mimeType,
                    filename
                )
                fields.bannerURLString = uploadedURL
                bannerUploadError = nil
            }
        } catch {
            let resolvedError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            switch target {
            case .avatar:
                avatarUploadError = resolvedError
            case .banner:
                bannerUploadError = resolvedError
            }
        }
    }
}

private struct ProfileEditorPreviewCard: View {
    @EnvironmentObject private var appSettings: AppSettingsStore
    @Environment(\.colorScheme) private var colorScheme

    let fields: EditableProfileFields
    let previewHandle: String
    let followingCount: Int
    let avatarPreviewImage: UIImage?
    let bannerPreviewImage: UIImage?

    private static let bannerHeight: CGFloat = 178
    private static let avatarSize: CGFloat = 104

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            previewBanner

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom, spacing: 16) {
                    previewAvatar

                    Spacer(minLength: 0)

                    previewActionCapsules
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text(resolvedDisplayName)
                        .font(appSettings.appFont(size: 28, weight: .heavy))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(resolvedHandle)
                        .font(appSettings.appFont(.subheadline))
                        .foregroundStyle(appSettings.themePalette.mutedForeground)

                    HStack(spacing: 4) {
                        Text("\(max(followingCount, 0)) following")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(appSettings.appFont(.footnote, weight: .semibold))
                    .foregroundStyle(appSettings.themePalette.mutedForeground)
                }

                if !fields.about.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ProfileAboutTextView(
                        text: fields.about.trimmingCharacters(in: .whitespacesAndNewlines),
                        onProfileTap: { _ in },
                        onHashtagTap: { _ in }
                    )
                } else {
                    Text("Your bio preview will appear here.")
                        .font(appSettings.appFont(.body))
                        .foregroundStyle(appSettings.themePalette.mutedForeground)
                }

                VStack(alignment: .leading, spacing: 10) {
                    if let nip05 = normalizedValue(fields.nip05) {
                        previewInfoRow(text: nip05, systemImage: "checkmark.seal")
                    }

                    if let website = normalizedWebsiteDisplayText {
                        previewInfoRow(text: website, systemImage: "link")
                    }

                    if let lightning = normalizedValue(fields.lightningAddress) {
                        previewInfoRow(text: lightning, systemImage: "bolt.fill")
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, -(Self.avatarSize / 2))
            .padding(.bottom, 18)
        }
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(appSettings.themePalette.secondaryGroupedBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(appSettings.themePalette.separator.opacity(0.18), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var resolvedDisplayName: String {
        normalizedValue(fields.displayName) ?? "Your Name"
    }

    private var resolvedHandle: String {
        let trimmedHandle = previewHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHandle.isEmpty {
            return trimmedHandle
        }
        return "@flow"
    }

    private var normalizedWebsiteDisplayText: String? {
        guard let url = ProfileMetadataEditing.normalizedWebsiteURL(from: fields.website) else { return nil }
        let host = url.host(percentEncoded: false) ?? url.absoluteString
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty {
            return host
        }
        return "\(host)/\(path)"
    }

    @ViewBuilder
    private var previewBanner: some View {
        ZStack {
            previewBannerContent

            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    .clear,
                    appSettings.themePalette.groupedBackground.opacity(0.24)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.bannerHeight)
        .background(appSettings.themePalette.secondaryBackground)
        .clipped()
    }

    @ViewBuilder
    private var previewBannerContent: some View {
        let bannerString = fields.bannerURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bannerPreviewImage {
            Image(uiImage: bannerPreviewImage)
                .resizable()
                .scaledToFill()
        } else if let bannerURL = URL(string: bannerString), !bannerString.isEmpty {
            CachedAsyncImage(url: bannerURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    previewBannerFallback
                }
            }
        } else {
            previewBannerFallback
        }
    }

    private var previewBannerFallback: some View {
        ZStack {
            LinearGradient(
                colors: [
                    appSettings.themePalette.secondaryBackground,
                    appSettings.primaryColor.opacity(0.20),
                    appSettings.themePalette.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.40))
                .frame(width: 148, height: 148)
                .blur(radius: 18)
                .offset(x: 122, y: -46)

            Circle()
                .fill(appSettings.primaryColor.opacity(0.18))
                .frame(width: 190, height: 190)
                .blur(radius: 28)
                .offset(x: -128, y: 54)
        }
    }

    private var previewAvatar: some View {
        let avatarString = fields.avatarURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        return Group {
            if let avatarPreviewImage {
                Image(uiImage: avatarPreviewImage)
                    .resizable()
                    .scaledToFill()
            } else if let avatarURL = URL(string: avatarString), !avatarString.isEmpty {
                CachedAsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        previewAvatarFallback
                    }
                }
            } else {
                previewAvatarFallback
            }
        }
        .frame(width: Self.avatarSize, height: Self.avatarSize)
        .background(Circle().fill(appSettings.themePalette.background))
        .clipShape(Circle())
        .overlay {
            Circle().stroke(appSettings.themePalette.background, lineWidth: 4)
        }
        .overlay {
            Circle().stroke(Color(.separator).opacity(0.22), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 8)
    }

    private var previewAvatarFallback: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            appSettings.primaryColor.opacity(0.9),
                            Color(.tertiarySystemFill)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(String(resolvedDisplayName.prefix(1)).uppercased())
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var previewActionCapsules: some View {
        HStack(spacing: 10) {
            previewActionCapsule(systemImage: "qrcode")
            previewActionCapsule(systemImage: "ellipsis")
            previewPrimaryActionCapsule(text: "Follow")
        }
    }

    private func previewActionCapsule(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 42, height: 40)
            .background(
                Capsule(style: .continuous)
                    .fill(appSettings.themePalette.tertiaryFill)
            )
    }

    private func previewPrimaryActionCapsule(text: String) -> some View {
        Text(text)
            .font(appSettings.appFont(.subheadline, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? .black : .white)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(
                Capsule(style: .continuous)
                    .fill(appSettings.primaryColor)
            )
    }

    private func previewInfoRow(text: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(appSettings.themePalette.mutedForeground)
                .frame(width: 16)

            Text(text)
                .font(appSettings.appFont(.footnote))
                .foregroundStyle(appSettings.themePalette.mutedForeground)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func normalizedValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
