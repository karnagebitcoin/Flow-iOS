import Foundation
import NostrSDK

enum AuthManagerError: LocalizedError {
    case invalidNsecOrHex
    case invalidNpub
    case keyGenerationFailed

    var errorDescription: String? {
        switch self {
        case .invalidNsecOrHex:
            return "Invalid nsec or hex private key."
        case .invalidNpub:
            return "Invalid npub public key."
        case .keyGenerationFailed:
            return "Could not generate a new keypair right now."
        }
    }
}

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var accounts: [AuthAccount] = []
    @Published private(set) var currentAccount: AuthAccount?

    private let store: AuthStore
    private var storedAccounts: [StoredAuthAccount] = []
    private var currentAccountID: String?

    init(store: AuthStore = .shared) {
        self.store = store
        let loaded = store.load()
        storedAccounts = loaded.accounts
        currentAccountID = loaded.currentAccountID
        syncPublishedState()
    }

    var isLoggedIn: Bool {
        currentAccount != nil
    }

    var currentNsec: String? {
        guard let currentAccountID else { return nil }
        return storedAccounts.first(where: { $0.id == currentAccountID })?.nsec
    }

    @discardableResult
    func signUp() throws -> GeneratedNostrAccount {
        guard let keypair = Keypair() else {
            throw AuthManagerError.keyGenerationFailed
        }

        let stored = StoredAuthAccount(
            pubkey: keypair.publicKey.hex,
            npub: keypair.publicKey.npub,
            signerType: .nsec,
            nsec: keypair.privateKey.nsec
        )
        upsertAndActivate(stored)

        return GeneratedNostrAccount(
            pubkey: keypair.publicKey.hex,
            npub: keypair.publicKey.npub,
            nsec: keypair.privateKey.nsec
        )
    }

    @discardableResult
    func loginWithNsecOrHex(_ credential: String) throws -> AuthAccount {
        let normalized = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw AuthManagerError.invalidNsecOrHex
        }

        let keypair: Keypair?
        if normalized.lowercased().hasPrefix("nsec1") {
            keypair = Keypair(nsec: normalized.lowercased())
        } else if normalized.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil {
            keypair = Keypair(hex: normalized.lowercased())
        } else {
            keypair = nil
        }

        guard let keypair else {
            throw AuthManagerError.invalidNsecOrHex
        }

        let stored = StoredAuthAccount(
            pubkey: keypair.publicKey.hex,
            npub: keypair.publicKey.npub,
            signerType: .nsec,
            nsec: keypair.privateKey.nsec
        )
        return upsertAndActivate(stored)
    }

    @discardableResult
    func loginWithNpub(_ npub: String) throws -> AuthAccount {
        let normalized = npub.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let publicKey = PublicKey(npub: normalized) else {
            throw AuthManagerError.invalidNpub
        }

        let stored = StoredAuthAccount(
            pubkey: publicKey.hex,
            npub: publicKey.npub,
            signerType: .npub,
            nsec: nil
        )
        return upsertAndActivate(stored)
    }

    func switchAccount(to account: AuthAccount?) {
        guard let account else {
            currentAccountID = nil
            persistAndPublish()
            return
        }
        guard storedAccounts.contains(where: { $0.id == account.id }) else { return }

        currentAccountID = account.id
        persistAndPublish()
    }

    func logout() {
        currentAccountID = nil
        persistAndPublish()
    }

    func removeAccount(_ account: AuthAccount) {
        storedAccounts.removeAll { $0.id == account.id }

        if currentAccountID == account.id {
            currentAccountID = storedAccounts.first?.id
        }
        persistAndPublish()
    }

    @discardableResult
    private func upsertAndActivate(_ account: StoredAuthAccount) -> AuthAccount {
        if let existingIndex = storedAccounts.firstIndex(where: { $0.id == account.id }) {
            storedAccounts[existingIndex] = account
        } else {
            storedAccounts.append(account)
        }

        currentAccountID = account.id
        persistAndPublish()
        return AuthAccount(pubkey: account.pubkey, npub: account.npub, signerType: account.signerType)
    }

    private func persistAndPublish() {
        store.save(accounts: storedAccounts, currentAccountID: currentAccountID)
        syncPublishedState()
    }

    private func syncPublishedState() {
        accounts = storedAccounts.map {
            AuthAccount(pubkey: $0.pubkey, npub: $0.npub, signerType: $0.signerType)
        }
        currentAccount = accounts.first(where: { $0.id == currentAccountID })
    }
}
