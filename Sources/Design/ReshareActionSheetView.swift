import SwiftUI

struct ReshareActionSheetView: View {
    @Environment(\.dismiss) private var dismiss

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
                        .fill(Color(.secondarySystemBackground))
                )

                if let statusMessage, !statusMessage.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(statusIsError ? .red : .green)
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(statusIsError ? .red : .secondary)
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
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("Re-share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
        .presentationDetents([.height(250), .medium])
        .presentationDragIndicator(.visible)
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
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if isWorking && title == "Repost" {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
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
