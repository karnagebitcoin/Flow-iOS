import SwiftUI
import UIKit

struct KeysView: View {
    @EnvironmentObject private var auth: AuthManager
    @State private var isPrivateKeyRevealed = false

    var body: some View {
        Form {
            publicKeySection
            privateKeySection
        }
        .navigationTitle("Keys")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: auth.currentAccount?.id) { _, _ in
            isPrivateKeyRevealed = false
        }
    }

    private var publicKeySection: some View {
        Section("Public Key") {
            if let account = auth.currentAccount {
                keyValueRow(
                    title: "npub",
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

    private var maskedPrivateKeyPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hidden")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Turn on reveal to view or copy the private key.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func keyValueRow(
        title: String,
        value: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

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
}
