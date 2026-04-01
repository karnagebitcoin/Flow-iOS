import SwiftUI

struct NoteReportSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let noteAuthorName: String
    let onSubmit: @Sendable (NoteReportType, String) async throws -> Void

    @State private var selectedType: NoteReportType?
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(NoteReportType.allCases) { type in
                        Button {
                            selectedType = type
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: type.systemImage)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(selectedType == type ? Color.accentColor : .secondary)
                                    .frame(width: 26)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(type.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    Text(type.subtitle)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer(minLength: 10)

                                Image(systemName: selectedType == type ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(
                                        selectedType == type
                                            ? AnyShapeStyle(Color.accentColor)
                                            : AnyShapeStyle(.tertiary)
                                    )
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Reason")
                } footer: {
                    Text("Reports are sent as a moderation event that apps and sources can interpret using NIP-56.")
                }

                Section("Additional Details") {
                    ZStack(alignment: .topLeading) {
                        if details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Optional context")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }

                        TextEditor(text: $details)
                            .frame(minHeight: 120)
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
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Report Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Sending..." : "Send") {
                        submit()
                    }
                    .disabled(selectedType == nil || isSubmitting)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
        .accessibilityLabel("Report note from \(noteAuthorName)")
    }

    private func submit() {
        guard let selectedType, !isSubmitting else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                try await onSubmit(selectedType, details)
                await MainActor.run {
                    isSubmitting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }
}
