import SwiftUI

private enum RelayAddScope: String, CaseIterable, Identifiable {
    case both = "Read + Write"
    case read = "Read Only"
    case write = "Write Only"

    var id: String { rawValue }

    var relayScope: RelayScope {
        switch self {
        case .both:
            return .both
        case .read:
            return .read
        case .write:
            return .write
        }
    }
}

struct RelaySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var relaySettings: RelaySettingsStore

    @State private var relayInput = ""
    @State private var relayScope: RelayAddScope = .both
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                readRelaysSection
                writeRelaysSection
                addRelaySection

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if let publishError = relaySettings.lastPublishError {
                    Section {
                        Text(publishError)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Sync Status")
                    }
                }
            }
            .navigationTitle("Relays")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var readRelaysSection: some View {
        Section {
            ForEach(relaySettings.readRelays, id: \.self) { relay in
                HStack(spacing: 10) {
                    Label(relayLabel(for: relay), systemImage: "eye")
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button("Remove", role: .destructive) {
                        removeReadRelay(relay)
                    }
                    .font(.footnote.weight(.semibold))
                    .disabled(relaySettings.readRelays.count <= 1)
                }
            }
        } header: {
            Text("Read Relays")
        } footer: {
            Text("The app reads from all configured read relays. Keep at least one.")
        }
    }

    private var writeRelaysSection: some View {
        Section {
            ForEach(relaySettings.writeRelays, id: \.self) { relay in
                HStack(spacing: 10) {
                    Label(relayLabel(for: relay), systemImage: "paperplane")
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button("Remove", role: .destructive) {
                        removeWriteRelay(relay)
                    }
                    .font(.footnote.weight(.semibold))
                    .disabled(relaySettings.writeRelays.count <= 1)
                }
            }
        } header: {
            Text("Write Relays")
        } footer: {
            Text("Posts, reactions, and follows publish to these relays.")
        }
    }

    private var addRelaySection: some View {
        Section {
            TextField("wss://relay.example.com", text: $relayInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Picker("Scope", selection: $relayScope) {
                ForEach(RelayAddScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            Button("Add Relay") {
                addRelay()
            }
            .buttonStyle(.borderedProminent)
        } header: {
            Text("Add Relay")
        }
    }

    private func relayLabel(for relay: String) -> String {
        guard let host = URL(string: relay)?.host(), !host.isEmpty else { return relay }
        return host
    }

    private func addRelay() {
        validationMessage = nil

        do {
            try relaySettings.addRelay(relayInput, scope: relayScope.relayScope)
            relayInput = ""
        } catch {
            validationMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func removeReadRelay(_ relay: String) {
        validationMessage = nil
        do {
            try relaySettings.removeReadRelay(relay)
        } catch {
            validationMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func removeWriteRelay(_ relay: String) {
        validationMessage = nil
        do {
            try relaySettings.removeWriteRelay(relay)
        } catch {
            validationMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
