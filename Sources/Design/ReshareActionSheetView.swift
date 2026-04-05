import SwiftUI

struct ReshareActionSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettingsStore

    let isWorking: Bool
    let statusMessage: String?
    let statusIsError: Bool
    let onRepost: () -> Void
    let onQuote: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 0) {
                    actionRow(title: "Repost", icon: "arrow.2.squarepath", action: onRepost)
                    Divider().padding(.leading, 16)
                    actionRow(title: "Quote", icon: "quote.bubble", action: onQuote)
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(appSettings.themePalette.modalBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(appSettings.themePalette.separator.opacity(0.35), lineWidth: 0.8)
                )

                if let statusMessage, !statusMessage.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(statusIsError ? .red : .green)
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(statusIsError ? .red : appSettings.themePalette.secondaryForeground)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill((statusIsError ? Color.red : Color.green).opacity(0.09))
                    )
                } else {
                    Text("Share this note as a repost, or add your own context with a quote.")
                        .font(.footnote)
                        .foregroundStyle(appSettings.themePalette.secondaryForeground)
                        .padding(.horizontal, 2)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("Re-share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ThemedToolbarDoneButton {
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
        .presentationDetents([.height(250), .medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(appSettings.themePalette.sheetBackground)
    }

    @ViewBuilder
    private func actionRow(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(appSettings.themePalette.foreground)
                Spacer(minLength: 0)
                if isWorking && title == "Repost" {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(appSettings.themePalette.iconMutedForeground)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }
}
