import SwiftUI
import UIKit

struct KeysView: View {
    @EnvironmentObject private var auth: AuthManager
    @State private var isPrivateKeyRevealed = false
    @State private var backupErrorMessage: String?

    var body: some View {
        Form {
            publicKeySection
            privateKeySection
            iCloudBackupSection
        }
        .navigationTitle("Keys")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: auth.currentAccount?.id) { _, _ in
            isPrivateKeyRevealed = false
            backupErrorMessage = nil
        }
    }

    private var publicKeySection: some View {
        Section("Public Key") {
            if let account = auth.currentAccount {
                keyValueRow(
                    title: nil,
                    value: account.npub,
                    actionTitle: "Copy Public Key",
                    action: {
                        UIPasteboard.general.string = account.npub
                    }
                )
            } else {
                Text("No signed-in account is available.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var privateKeySection: some View {
        Section("Private Key") {
            if let privateKey = auth.currentNsec {
                Toggle("Reveal Private Key", isOn: $isPrivateKeyRevealed)

                if isPrivateKeyRevealed {
                    keyValueRow(
                        title: "nsec",
                        value: privateKey,
                        actionTitle: "Copy Private Key",
                        action: {
                            UIPasteboard.general.string = privateKey
                        }
                    )
                } else {
                    maskedPrivateKeyPlaceholder
                }
            } else {
                Toggle("Reveal Private Key", isOn: .constant(false))
                    .disabled(true)

                Text("This account was created with a public key only, so there is no private key to reveal or copy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var iCloudBackupSection: some View {
        if let account = auth.currentAccount, account.signerType == .nsec {
            Section {
                Toggle("Back Up Private Key to iCloud", isOn: privateKeyBackupBinding(for: account))

                privateKeyBackupStatusCard(for: account)

                if let backupErrorMessage {
                    Text(backupErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("iCloud Backup")
            } footer: {
                Text(
                    account.privateKeyBackupEnabled
                        ? "This confirms the key was added to iCloud Keychain on this device. Apple does not expose the exact cross-device sync time."
                        : "This private key stays only on this device until you turn on iCloud backup. New Flow-created accounts back this up automatically."
                )
            }
        }
    }

    private var maskedPrivateKeyPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keep your private key to yourself. It protects your account and can't be reset if it's exposed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Turn on reveal only when you need to view or copy it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func privateKeyBackupStatusCard(for account: AuthAccount) -> some View {
        let metadata = auth.privateKeyMetadata(for: account)
        let status = backupStatusDescription(for: account, metadata: metadata)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: status.iconName)
                    .foregroundStyle(status.tint)
                Text(status.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Text(status.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func backupStatusDescription(
        for account: AuthAccount,
        metadata: AuthPrivateKeyMetadata?
    ) -> (title: String, message: String, iconName: String, tint: Color) {
        if account.privateKeyBackupEnabled {
            if metadata?.isSynchronizable == true {
                let savedDate = metadata?.modifiedAt ?? metadata?.createdAt
                if let savedDate {
                    return (
                        title: "Backed up on this device",
                        message: "Last added to iCloud Keychain: \(savedDate.formatted(date: .abbreviated, time: .shortened))",
                        iconName: "checkmark.circle.fill",
                        tint: .green
                    )
                }

                return (
                    title: "Backup enabled",
                    message: "This key is stored in iCloud Keychain on this device.",
                    iconName: "icloud.fill",
                    tint: .green
                )
            }

            return (
                title: "Backup enabled",
                message: "iCloud backup is turned on, but this key has not reported a local iCloud Keychain save yet.",
                iconName: "icloud.slash",
                tint: .orange
            )
        }

        return (
            title: "Device only",
            message: "This private key is stored only on this device right now.",
            iconName: "iphone",
            tint: Color.secondary
        )
    }

    private func keyValueRow(
        title: String?,
        value: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title, !title.isEmpty {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                action()
            } label: {
                Label(actionTitle, systemImage: "doc.on.doc")
            }
        }
        .padding(.vertical, 2)
    }

    private func privateKeyBackupBinding(for account: AuthAccount) -> Binding<Bool> {
        Binding(
            get: {
                auth.currentAccount?.id == account.id
                    ? (auth.currentAccount?.privateKeyBackupEnabled ?? false)
                    : account.privateKeyBackupEnabled
            },
            set: { newValue in
                do {
                    try auth.setPrivateKeyBackupEnabled(newValue, for: account)
                    backupErrorMessage = nil
                } catch {
                    backupErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        )
    }
}
