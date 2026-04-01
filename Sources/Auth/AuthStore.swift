import Foundation

struct AuthStoreLoadResult {
    let accounts: [StoredAuthAccount]
    let currentAccountID: String?
    let transientPrivateKeysByAccountID: [String: String]
    let accountsNeedingSecureStorageRepair: Set<String>
}

final class AuthStore: @unchecked Sendable {
    static let shared = AuthStore()

    private let defaults: UserDefaults
    private let privateKeyStore: any AuthPrivateKeyStoring
    private let accountsKey = "flow.auth.accounts"
    private let currentAccountIDKey = "flow.auth.currentAccountID"
    private let legacyAccountsKey = "x21.auth.accounts"
    private let legacyCurrentAccountIDKey = "x21.auth.currentAccountID"
    private let privateKeyRepairIDsKey = "flow.auth.privateKeyRepairIDs"

    init(
        defaults: UserDefaults = .standard,
        privateKeyStore: any AuthPrivateKeyStoring = AuthPrivateKeyStore.shared
    ) {
        self.defaults = defaults
        self.privateKeyStore = privateKeyStore
    }

    func load() -> AuthStoreLoadResult {
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
        var transientPrivateKeysByAccountID: [String: String] = [:]
        var accountsNeedingSecureStorageRepair = loadPrivateKeyRepairIDs()
        var didRewriteStoredAccounts = false

        for account in accounts {
            let strippedAccount = StoredAuthAccount(
                pubkey: account.pubkey,
                npub: account.npub,
                signerType: account.signerType,
                nsec: nil,
                privateKeyBackupEnabled: account.privateKeyBackupEnabled
            )

            guard let legacyNsec = account.nsec?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !legacyNsec.isEmpty else {
                migratedAccounts.append(strippedAccount)
                if privateKeyStore.privateKey(for: account.id) != nil {
                    accountsNeedingSecureStorageRepair.remove(account.id)
                }
                continue
            }

            didRewriteStoredAccounts = true
            if privateKeyStore.privateKey(for: account.id) == nil {
                do {
                    try privateKeyStore.savePrivateKey(
                        legacyNsec,
                        for: account.id,
                        backupToICloud: account.privateKeyBackupEnabled
                    )
                    accountsNeedingSecureStorageRepair.remove(account.id)
                } catch {
                    transientPrivateKeysByAccountID[account.id] = legacyNsec
                    accountsNeedingSecureStorageRepair.insert(account.id)
                }
            } else {
                accountsNeedingSecureStorageRepair.remove(account.id)
            }

            migratedAccounts.append(strippedAccount)
        }

        if didRewriteStoredAccounts ||
            usedLegacyAccountsData ||
            defaults.string(forKey: currentAccountIDKey) == nil ||
            accountsNeedingSecureStorageRepair != loadPrivateKeyRepairIDs() {
            save(
                accounts: migratedAccounts,
                currentAccountID: currentAccountID,
                accountsNeedingSecureStorageRepair: accountsNeedingSecureStorageRepair
            )
        }

        return AuthStoreLoadResult(
            accounts: migratedAccounts,
            currentAccountID: currentAccountID,
            transientPrivateKeysByAccountID: transientPrivateKeysByAccountID,
            accountsNeedingSecureStorageRepair: accountsNeedingSecureStorageRepair
        )
    }

    func save(
        accounts: [StoredAuthAccount],
        currentAccountID: String?,
        accountsNeedingSecureStorageRepair: Set<String>? = nil
    ) {
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
        defaults.removeObject(forKey: legacyAccountsKey)

        if let currentAccountID {
            defaults.set(currentAccountID, forKey: currentAccountIDKey)
        } else {
            defaults.removeObject(forKey: currentAccountIDKey)
        }
        defaults.removeObject(forKey: legacyCurrentAccountIDKey)

        let repairIDs = Array(
            (accountsNeedingSecureStorageRepair ?? loadPrivateKeyRepairIDs()).sorted()
        )
        defaults.set(repairIDs, forKey: privateKeyRepairIDsKey)
    }

    func privateKey(for accountID: String) -> String? {
        privateKeyStore.privateKey(for: accountID)
    }

    func privateKeyMetadata(for accountID: String) -> AuthPrivateKeyMetadata? {
        privateKeyStore.privateKeyMetadata(for: accountID)
    }

    func iCloudPrivateKeyBackups() -> [AuthICloudPrivateKeyBackup] {
        privateKeyStore.iCloudPrivateKeyBackups()
    }

    func savePrivateKey(_ nsec: String, for accountID: String, backupToICloud: Bool) throws {
        try privateKeyStore.savePrivateKey(nsec, for: accountID, backupToICloud: backupToICloud)
    }

    func removePrivateKey(for accountID: String) {
        privateKeyStore.removePrivateKey(for: accountID)
        setPrivateKeyNeedsSecureStorageRepair(false, for: accountID)
    }

    func setPrivateKeyNeedsSecureStorageRepair(_ needsRepair: Bool, for accountID: String) {
        var repairIDs = loadPrivateKeyRepairIDs()
        if needsRepair {
            repairIDs.insert(accountID)
        } else {
            repairIDs.remove(accountID)
        }
        defaults.set(Array(repairIDs.sorted()), forKey: privateKeyRepairIDsKey)
    }

    private func loadPrivateKeyRepairIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: privateKeyRepairIDsKey) ?? [])
    }
}
