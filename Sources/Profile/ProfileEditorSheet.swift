import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ProfileEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var fields: EditableProfileFields
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var avatarUploadError: String?

    let isSaving: Bool
    let errorMessage: String?
    let onSave: (EditableProfileFields) async -> Bool
    let onUploadAvatar: (Data, String, String) async throws -> String

    init(
        initialFields: EditableProfileFields,
        isSaving: Bool,
        errorMessage: String?,
        onSave: @escaping (EditableProfileFields) async -> Bool,
        onUploadAvatar: @escaping (Data, String, String) async throws -> String
    ) {
        _fields = State(initialValue: initialFields)
        self.isSaving = isSaving
        self.errorMessage = errorMessage
        self.onSave = onSave
        self.onUploadAvatar = onUploadAvatar
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    HStack(spacing: 10) {
                        fieldIcon("person")
                        TextField("Display Name", text: $fields.displayName)
                    }
                    HStack(spacing: 10) {
                        fieldIcon("photo")
                        TextField("Avatar URL", text: $fields.avatarURLString)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()

                        PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                            if isUploadingAvatar {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 28, height: 28)
                            } else {
                                Image(systemName: "photo.badge.plus")
                                    .font(.headline)
                                    .frame(width: 28, height: 28)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving || isUploadingAvatar)
                        .accessibilityLabel("Upload profile photo")
                    }
                    HStack(alignment: .top, spacing: 10) {
                        fieldIcon("text.alignleft")
                            .padding(.top, 4)
                        TextField("Bio", text: $fields.about, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }

                Section("Links") {
                    HStack(spacing: 10) {
                        fieldIcon("globe")
                        TextField("Website", text: $fields.website)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                    }
                }

                if let avatarUploadError, !avatarUploadError.isEmpty {
                    Section {
                        Text(avatarUploadError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let didSave = await onSave(fields)
                            if didSave {
                                dismiss()
                            }
                        }
                    } label: {
                        if isSaving || isUploadingAvatar {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving || isUploadingAvatar)
                }
            }
        }
        .onChange(of: selectedAvatarItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await uploadAvatar(from: newItem)
            }
        }
    }

    private func fieldIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 18, alignment: .center)
            .accessibilityHidden(true)
    }

    @MainActor
    private func uploadAvatar(from item: PhotosPickerItem) async {
        guard !isUploadingAvatar else { return }
        isUploadingAvatar = true
        avatarUploadError = nil

        defer {
            isUploadingAvatar = false
            selectedAvatarItem = nil
        }

        do {
            let preparedMedia = try await MediaUploadPreparation.prepareUploadMedia(from: item)
            let filename = "profile-\(Int(Date().timeIntervalSince1970)).\(preparedMedia.fileExtension)"

            let avatarURL = try await onUploadAvatar(
                preparedMedia.data,
                preparedMedia.mimeType,
                filename
            )
            fields.avatarURLString = avatarURL
            avatarUploadError = nil
        } catch {
            avatarUploadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
