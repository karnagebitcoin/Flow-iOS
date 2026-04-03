import SwiftUI

private enum RelayAddScope: String, CaseIterable, Identifiable {
    case both = "Receive + Publish"
    case read = "Receive Only"
    case write = "Publish Only"

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
    @EnvironmentObject private var relaySettings: RelaySettingsStore

    @State private var relayInput = ""
    @State private var relayScope: RelayAddScope = .both
    @State private var validationMessage: String?
    @State private var isShowingAdvancedSources = false
    @State private var isShowingSourcesInfo = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.18))
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        .frame(width: 38, height: 38)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(connectionSummaryText)
                                .font(.headline)
                            Text(connectionDetailText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        Button {
                            isShowingSourcesInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .background(Color(.systemBackground).opacity(0.8), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("What are sources?")
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color(.separator).opacity(0.14), lineWidth: 1)
                )
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section {
                VStack(alignment: .leading, spacing: 0) {
                    DisclosureGroup(isExpanded: $isShowingAdvancedSources) {
                        VStack(alignment: .leading, spacing: 18) {
                            sourceList
                            addSourceControls

                            if let validationMessage {
                                messageBanner(
                                    validationMessage,
                                    systemImage: "exclamationmark.circle.fill",
                                    tint: .red
                                )
                            }

                            if let publishError = relaySettings.lastPublishError {
                                messageBanner(
                                    userFacingMessage(for: publishError),
                                    systemImage: "info.circle.fill",
                                    tint: .secondary
                                )
                            }
                        }
                        .padding(.top, 14)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Data Sources")
                                .font(.headline)
                            Text("Advanced controls for where Halo receives from and publishes to.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color(.separator).opacity(0.14), lineWidth: 1)
                )
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $isShowingSourcesInfo) {
            sourcesInfoSheet
        }
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dataSources.isEmpty {
                Text("No sources configured yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(dataSources.enumerated()), id: \.element.id) { index, source in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Source \(index + 1)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Text(source.label)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text(source.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer(minLength: 8)

                            Menu {
                                if source.receives {
                                    Button("Stop Receiving from Source", role: .destructive) {
                                        removeReceiveSource(source.url)
                                    }
                                }
                                if source.publishes {
                                    Button("Stop Publishing to Source", role: .destructive) {
                                        removePublishSource(source.url)
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        HStack(spacing: 8) {
                            if source.receives {
                                sourceCapabilityPill("Receive", systemImage: "arrow.down.circle")
                            }
                            if source.publishes {
                                sourceCapabilityPill("Publish", systemImage: "arrow.up.circle")
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.tertiarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(.separator).opacity(0.12), lineWidth: 1)
                    )
                }
            }
        }
    }

    private func sourceCapabilityPill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemBackground), in: Capsule(style: .continuous))
    }

    private var addSourceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Source")
                .font(.headline)

            TextField("wss://source.example.com", text: $relayInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(.separator).opacity(0.2), lineWidth: 1)
                )

            FlowCapsuleTabBar(
                selection: $relayScope,
                items: RelayAddScope.allCases,
                title: { $0.rawValue }
            )

            Button("Add Source") {
                addSource()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 1)
        )
    }

    private var connectionSummaryText: String {
        let count = dataSources.count
        return "Connected to \(count) \(count == 1 ? "source" : "sources")"
    }

    private var connectionDetailText: String {
        if dataSources.isEmpty {
            return "Add a source to start receiving and publishing data."
        }
        return "Halo is currently using your configured data sources."
    }

    private var dataSources: [DataSourceItem] {
        let readSet = Set(relaySettings.readRelays)
        let writeSet = Set(relaySettings.writeRelays)
        let ordered = orderedUniqueSources(from: relaySettings.readRelays + relaySettings.writeRelays)

        return ordered.enumerated().map { index, url in
            DataSourceItem(
                id: "\(index)-\(url)",
                url: url,
                label: sourceLabel(for: url),
                receives: readSet.contains(url),
                publishes: writeSet.contains(url)
            )
        }
    }

    private func orderedUniqueSources(from values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            guard seen.insert(value).inserted else { continue }
            ordered.append(value)
        }
        return ordered
    }

    private func sourceLabel(for source: String) -> String {
        guard let host = URL(string: source)?.host(), !host.isEmpty else { return source }
        return host
    }

    private func addSource() {
        validationMessage = nil

        do {
            try relaySettings.addRelay(relayInput, scope: relayScope.relayScope)
            relayInput = ""
        } catch {
            validationMessage = userFacingMessage(for: error)
        }
    }

    private func removeReceiveSource(_ source: String) {
        validationMessage = nil
        do {
            try relaySettings.removeReadRelay(source)
        } catch {
            validationMessage = userFacingMessage(for: error)
        }
    }

    private func removePublishSource(_ source: String) {
        validationMessage = nil
        do {
            try relaySettings.removeWriteRelay(source)
        } catch {
            validationMessage = userFacingMessage(for: error)
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        let base = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return userFacingMessage(for: base)
    }

    private func userFacingMessage(for message: String) -> String {
        let base = message
        return base
            .replacingOccurrences(of: "relay settings", with: "connection settings")
            .replacingOccurrences(of: "Relays", with: "Sources")
            .replacingOccurrences(of: "Relay", with: "Source")
            .replacingOccurrences(of: "read relays", with: "receive sources")
            .replacingOccurrences(of: "write relays", with: "publish sources")
            .replacingOccurrences(of: "relays", with: "sources")
            .replacingOccurrences(of: "relay", with: "source")
    }

    private func messageBanner(_ text: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 1)
        )
    }

    private var sourcesInfoSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("What are sources?")
                    .font(.custom("SF Pro Display", size: 28).weight(.semibold))

                Text("Halo does not operate any servers and collects no data. All information is fetched in real time from public servers operated by other people.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Your connection settings decide which public sources Halo reads from and where your posts, follows, and reactions get published.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("About Sources")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(270), .medium])
        .presentationDragIndicator(.visible)
    }
}

private extension RelaySettingsView {
    struct DataSourceItem: Identifiable {
        let id: String
        let url: String
        let label: String
        let receives: Bool
        let publishes: Bool
    }
}
