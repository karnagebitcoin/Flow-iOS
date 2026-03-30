import SwiftUI

struct ICloudKeyRestoreView: View {
    @EnvironmentObject private var auth: AuthManager

    let onRestore: () -> Void

    @State private var candidates: [AuthICloudRestoreCandidate] = []
    @State private var restoreError: String?
    @State private var restoringAccountID: String?

    var body: some View {
        Form {
            Section {
                Text("Restore a private-key account that was previously backed up to iCloud Keychain.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Make sure you’re signed into the same Apple Account and iCloud Keychain is enabled on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Available Accounts") {
                if candidates.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No iCloud-backed private keys are available yet.")
                            .font(.footnote.weight(.semibold))
                        Text("If you backed up a key on another device, give iCloud Keychain a moment to sync, then refresh.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button("Refresh") {
                            refreshCandidates(clearError: false)
                        }
                        .font(.footnote.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(candidates) { candidate in
                        Button {
                            restore(candidate)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(shortNostrIdentifier(candidate.pubkey))
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)

                                    Text(candidate.npub)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)

                                    Text(backupStatusText(for: candidate))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 12)

                                if restoringAccountID == candidate.id {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text(candidate.isAlreadyOnDevice ? "Use" : "Restore")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(restoringAccountID != nil)
                    }
                }
            }

            if let restoreError {
                Section {
                    Text(restoreError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Restore from iCloud")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh") {
                    refreshCandidates(clearError: false)
                }
                .disabled(restoringAccountID != nil)
            }
        }
        .onAppear {
            refreshCandidates()
        }
    }

    private func refreshCandidates(clearError: Bool = true) {
        candidates = auth.iCloudRestoreCandidates()
        if clearError {
            restoreError = nil
        }
    }

    private func restore(_ candidate: AuthICloudRestoreCandidate) {
        restoringAccountID = candidate.id
        restoreError = nil

        do {
            _ = try auth.restoreFromICloud(candidate)
            restoringAccountID = nil
            onRestore()
        } catch {
            restoringAccountID = nil
            refreshCandidates(clearError: false)
            restoreError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func backupStatusText(for candidate: AuthICloudRestoreCandidate) -> String {
        let date = candidate.modifiedAt ?? candidate.createdAt
        let prefix = candidate.isAlreadyOnDevice ? "Already on this device" : "Stored in iCloud Keychain"

        guard let date else { return prefix }
        return "\(prefix) • \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}
