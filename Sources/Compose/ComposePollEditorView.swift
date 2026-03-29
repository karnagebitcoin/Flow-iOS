import SwiftUI

struct ComposePollEditorView: View {
    @Binding var draft: ComposePollDraft

    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("Poll", systemImage: "chart.bar.xaxis")
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 12)

                Button("Remove", role: .destructive, action: onRemove)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
            }

            Text("Polls are compatible with x21's Nostr format, but some clients still won't render them.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(Array(draft.options.indices), id: \.self) { index in
                    optionRow(index: index)
                }

                Button {
                    draft.options.append(ComposePollOption())
                } label: {
                    Label("Add Option", systemImage: "plus.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                }
                .buttonStyle(.plain)
            }

            Divider()

            Toggle("Allow multiple choices", isOn: $draft.allowsMultipleChoice)
                .font(.subheadline)
                .tint(.accentColor)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Ends")
                        .font(.subheadline)

                    Spacer(minLength: 0)

                    if let endsAt = draft.endsAt {
                        Text(endsAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    } else {
                        Text("No end date")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if draft.endsAt != nil {
                    DatePicker(
                        "Poll end date",
                        selection: endDateBinding,
                        in: minimumEndDate...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                }

                Button {
                    if draft.endsAt == nil {
                        draft.endsAt = ComposePollDraft.defaultEndDate()
                    } else {
                        draft.endsAt = nil
                    }
                } label: {
                    Label(
                        draft.endsAt == nil ? "Add End Date" : "Clear End Date",
                        systemImage: draft.endsAt == nil ? "calendar.badge.plus" : "xmark.circle"
                    )
                    .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(draft.endsAt == nil ? Color.accentColor : .secondary)
            }

            Text(
                draft.hasMinimumOptions
                    ? "\(draft.validOptionCount) options ready."
                    : "Add at least two option labels before posting."
            )
            .font(.footnote.weight(draft.hasMinimumOptions ? .regular : .semibold))
            .foregroundStyle(draft.hasMinimumOptions ? Color.secondary : Color.orange)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(.separator).opacity(0.28), lineWidth: 0.8)
        )
    }

    private var minimumEndDate: Date {
        ComposePollDraft.roundToMinute(Date().addingTimeInterval(60))
    }

    private var endDateBinding: Binding<Date> {
        Binding(
            get: { draft.endsAt ?? ComposePollDraft.defaultEndDate() },
            set: { newValue in
                draft.endsAt = ComposePollDraft.roundToMinute(newValue)
            }
        )
    }

    private func optionRow(index: Int) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(index + 1)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color(.quaternarySystemFill))
                )

            TextField(
                "Option \(index + 1)",
                text: optionTextBinding(index),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.body)
            .lineLimit(1...2)

            if draft.options.count > 2 {
                Button {
                    draft.options.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove option \(index + 1)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    private func optionTextBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard draft.options.indices.contains(index) else { return "" }
                return draft.options[index].text
            },
            set: { newValue in
                guard draft.options.indices.contains(index) else { return }
                draft.options[index].text = newValue
            }
        )
    }
}
