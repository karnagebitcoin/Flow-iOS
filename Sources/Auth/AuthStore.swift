import Foundation

final class AuthStore: @unchecked Sendable {
    static let shared = AuthStore()

    private let defaults: UserDefaults
    private let privateKeyStore: AuthPrivateKeyStore
    private let accountsKey = "flow.auth.accounts"
    private let currentAccountIDKey = "flow.auth.currentAccountID"
    private let legacyAccountsKey = "x21.auth.accounts"
    private let legacyCurrentAccountIDKey = "x21.auth.currentAccountID"

    init(
        defaults: UserDefaults = .standard,
        privateKeyStore: AuthPrivateKeyStore = .shared
    ) {
        self.defaults = defaults
        self.privateKeyStore = privateKeyStore
    }

    func load() -> (accounts: [StoredAuthAccount], currentAccountID: String?) {
        let accountsData = defaults.data(forKey: accountsKey) ?? defaults.data(forKey: legacyAccountsKey)
        let accounts: [StoredAuthAccount]
        let usedLegacyAccountsData = defaults.data(forKey: accountsKey) == nil && accountsData != nil
        if let accountsData,
           let decoded = try? JSONDecoder().decode([StoredAuthAccount].self, from: accountsData) {
            accounts = decoded
        } else {
            accounts = []
        }

        let currentAccountID = defaults.string(forKey: currentAccountIDKey) ?? defaults.string(forKey: legacyCurrentAccountIDKey)
        var migratedAccounts: [StoredAuthAccount] = []
        var didMigrateLegacySecrets = false
        var hasUnmigratedLegacySecrets = false

        for account in accounts {
            guard let legacyNsec = account.nsec?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !legacyNsec.isEmpty else {
                migratedAccounts.append(account)
                continue
            }

            if privateKeyStore.privateKey(for: account.id) == nil {
                do {
                    try privateKeyStore.savePrivateKey(
                        legacyNsec,
                        for: account.id,
                        backupToICloud: account.privateKeyBackupEnabled
                    )
                } catch {
                    migratedAccounts.append(account)
                    hasUnmigratedLegacySecrets = true
                    continue
                }
            }

            migratedAccounts.append(
                StoredAuthAccount(
                    pubkey: account.pubkey,
                    npub: account.npub,
                    signerType: account.signerType,
                    nsec: nil,
                    privateKeyBackupEnabled: account.privateKeyBackupEnabled
                )
            )
            didMigrateLegacySecrets = true
        }

        if !hasUnmigratedLegacySecrets,
           (didMigrateLegacySecrets || usedLegacyAccountsData || defaults.string(forKey: currentAccountIDKey) == nil) {
            save(accounts: migratedAccounts, currentAccountID: currentAccountID)
        }

        return (migratedAccounts, currentAccountID)
    }

    func save(accounts: [StoredAuthAccount], currentAccountID: String?) {
        let persistedAccounts = accounts.map { account in
            guard account.signerType == .nsec,
                  account.nsec == nil,
                  privateKeyStore.privateKey(for: account.id) != nil else {
                return account
            }
            return StoredAuthAccount(
                pubkey: account.pubkey,
                npub: account.npub,
                signerType: account.signerType,
                nsec: nil,
                privateKeyBackupEnabled: account.privateKeyBackupEnabled
            )
        }

        if let data = try? JSONEncoder().encode(persistedAccounts) {
            defaults.set(data, forKey: accountsKey)
        }

        if let currentAccountID {
            defaults.set(currentAccountID, forKey: currentAccountIDKey)
        } else {
            defaults.removeObject(forKey: currentAccountIDKey)
        }
    }

    func privateKey(for accountID: String) -> String? {
        privateKeyStore.privateKey(for: accountID)
    }

    func privateKeyMetadata(for accountID: String) -> AuthPrivateKeyMetadata? {
        privateKeyStore.privateKeyMetadata(for: accountID)
    }

    func savePrivateKey(_ nsec: String, for accountID: String, backupToICloud: Bool) throws {
        try privateKeyStore.savePrivateKey(nsec, for: accountID, backupToICloud: backupToICloud)
    }

    func removePrivateKey(for accountID: String) {
        privateKeyStore.removePrivateKey(for: accountID)
    }
}
