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
        return store.privateKey(for: currentAccountID)
            ?? storedAccounts.first(where: { $0.id == currentAccountID })?.nsec
    }

    var currentPrivateKeyMetadata: AuthPrivateKeyMetadata? {
        guard let currentAccountID else { return nil }
        return store.privateKeyMetadata(for: currentAccountID)
    }

    func privateKeyMetadata(for account: AuthAccount) -> AuthPrivateKeyMetadata? {
        store.privateKeyMetadata(for: account.id)
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
            privateKeyBackupEnabled: true
        )
        try upsertAndActivate(
            stored,
            privateKey: keypair.privateKey.nsec,
            backupPrivateKeyToICloud: true
        )

        return GeneratedNostrAccount(
            pubkey: keypair.publicKey.hex,
            npub: keypair.publicKey.npub,
            nsec: keypair.privateKey.nsec
        )
    }

    @discardableResult
    func loginWithNsecOrHex(
        _ credential: String,
        backupPrivateKeyToICloud: Bool? = nil
    ) throws -> AuthAccount {
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
            privateKeyBackupEnabled: backupPrivateKeyToICloud ?? false
        )
        return try upsertAndActivate(
            stored,
            privateKey: keypair.privateKey.nsec,
            backupPrivateKeyToICloud: backupPrivateKeyToICloud
        )
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
            privateKeyBackupEnabled: false
        )
        return try upsertAndActivate(stored)
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
        store.removePrivateKey(for: account.id)

        if currentAccountID == account.id {
            currentAccountID = storedAccounts.first?.id
        }
        persistAndPublish()
    }

    func setPrivateKeyBackupEnabled(_ enabled: Bool, for account: AuthAccount) throws {
        guard account.signerType == .nsec else { return }
        guard let index = storedAccounts.firstIndex(where: { $0.id == account.id }) else { return }

        let privateKey = store.privateKey(for: account.id) ?? storedAccounts[index].nsec
        guard let privateKey else {
            throw AuthPrivateKeyStoreError.missingPrivateKey
        }

        try store.savePrivateKey(privateKey, for: account.id, backupToICloud: enabled)
        storedAccounts[index] = StoredAuthAccount(
            pubkey: storedAccounts[index].pubkey,
            npub: storedAccounts[index].npub,
            signerType: storedAccounts[index].signerType,
            nsec: nil,
            privateKeyBackupEnabled: enabled
        )
        persistAndPublish()
    }

    @discardableResult
    private func upsertAndActivate(
        _ account: StoredAuthAccount,
        privateKey: String? = nil,
        backupPrivateKeyToICloud: Bool? = nil
    ) throws -> AuthAccount {
        let existingIndex = storedAccounts.firstIndex(where: { $0.id == account.id })
        let resolvedBackupSetting: Bool
        if account.signerType == .nsec {
            if let backupPrivateKeyToICloud {
                resolvedBackupSetting = backupPrivateKeyToICloud
            } else if let existingIndex {
                resolvedBackupSetting = storedAccounts[existingIndex].privateKeyBackupEnabled
            } else {
                resolvedBackupSetting = false
            }
        } else {
            resolvedBackupSetting = false
        }

        if account.signerType == .nsec, let privateKey {
            try store.savePrivateKey(
                privateKey,
                for: account.id,
                backupToICloud: resolvedBackupSetting
            )
        }

        let persistedAccount = StoredAuthAccount(
            pubkey: account.pubkey,
            npub: account.npub,
            signerType: account.signerType,
            privateKeyBackupEnabled: resolvedBackupSetting
        )

        if let existingIndex {
            storedAccounts[existingIndex] = persistedAccount
        } else {
            storedAccounts.append(persistedAccount)
        }

        currentAccountID = persistedAccount.id
        persistAndPublish()
        return AuthAccount(
            pubkey: persistedAccount.pubkey,
            npub: persistedAccount.npub,
            signerType: persistedAccount.signerType,
            privateKeyBackupEnabled: persistedAccount.privateKeyBackupEnabled
        )
    }

    private func persistAndPublish() {
        store.save(accounts: storedAccounts, currentAccountID: currentAccountID)
        syncPublishedState()
    }

    private func syncPublishedState() {
        accounts = storedAccounts.map {
            AuthAccount(
                pubkey: $0.pubkey,
                npub: $0.npub,
                signerType: $0.signerType,
                privateKeyBackupEnabled: $0.privateKeyBackupEnabled
            )
        }
        currentAccount = accounts.first(where: { $0.id == currentAccountID })
    }
}
