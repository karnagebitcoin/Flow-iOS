import XCTest
import NostrSDK
import Security
@testable import Flow

final class AuthManagerTests: XCTestCase {
    @MainActor
    func testLoggingInWithSecondPrivateKeyAppendsAccountList() throws {
        let suiteName = #function
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let privateKeyStore = AuthPrivateKeyStore()
        let store = AuthStore(defaults: defaults, privateKeyStore: privateKeyStore)
        let auth = AuthManager(store: store)

        let firstKeypair = try XCTUnwrap(Keypair())
        let secondKeypair = try XCTUnwrap(Keypair())

        _ = try auth.loginWithNsecOrHex(firstKeypair.privateKey.nsec)
        _ = try auth.loginWithNsecOrHex(secondKeypair.privateKey.nsec)

        XCTAssertEqual(auth.accounts.count, 2)
        XCTAssertEqual(
            Set(auth.accounts.map(\.pubkey)),
            Set([firstKeypair.publicKey.hex, secondKeypair.publicKey.hex])
        )
        XCTAssertEqual(auth.currentAccount?.pubkey, secondKeypair.publicKey.hex)

        for account in auth.accounts {
            auth.removeAccount(account)
        }
        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testLegacyPlaintextKeyIsScrubbedFromDefaultsWhenSecureMigrationFails() throws {
        let suiteName = #function
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let keypair = try XCTUnwrap(Keypair())
        let storedAccount = StoredAuthAccount(
            pubkey: keypair.publicKey.hex,
            npub: keypair.publicKey.npub,
            signerType: .nsec,
            nsec: keypair.privateKey.nsec,
            privateKeyBackupEnabled: false
        )

        let data = try JSONEncoder().encode([storedAccount])
        defaults.set(data, forKey: "flow.auth.accounts")
        defaults.set(storedAccount.id, forKey: "flow.auth.currentAccountID")

        let store = AuthStore(
            defaults: defaults,
            privateKeyStore: FailingPrivateKeyStore()
        )
        let auth = AuthManager(store: store)

        XCTAssertEqual(auth.currentNsec, keypair.privateKey.nsec)
        XCTAssertNotNil(auth.currentPrivateKeySecurityWarning)

        let persistedData = try XCTUnwrap(defaults.data(forKey: "flow.auth.accounts"))
        let persistedAccounts = try JSONDecoder().decode([StoredAuthAccount].self, from: persistedData)
        XCTAssertEqual(persistedAccounts.count, 1)
        XCTAssertNil(persistedAccounts[0].nsec)
    }

    @MainActor
    func testSecureStorageWarningPersistsAcrossRestartWhenLegacyMigrationFails() throws {
        let suiteName = #function
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let keypair = try XCTUnwrap(Keypair())
        let storedAccount = StoredAuthAccount(
            pubkey: keypair.publicKey.hex,
            npub: keypair.publicKey.npub,
            signerType: .nsec,
            nsec: keypair.privateKey.nsec,
            privateKeyBackupEnabled: false
        )

        let data = try JSONEncoder().encode([storedAccount])
        defaults.set(data, forKey: "flow.auth.accounts")
        defaults.set(storedAccount.id, forKey: "flow.auth.currentAccountID")

        let firstStore = AuthStore(
            defaults: defaults,
            privateKeyStore: FailingPrivateKeyStore()
        )
        _ = AuthManager(store: firstStore)

        let secondStore = AuthStore(
            defaults: defaults,
            privateKeyStore: FailingPrivateKeyStore()
        )
        let relaunchedAuth = AuthManager(store: secondStore)

        XCTAssertNil(relaunchedAuth.currentNsec)
        XCTAssertNotNil(relaunchedAuth.currentPrivateKeySecurityWarning)
    }
}

private struct FailingPrivateKeyStore: AuthPrivateKeyStoring {
    func privateKey(for accountID: String) -> String? { nil }
    func privateKeyMetadata(for accountID: String) -> AuthPrivateKeyMetadata? { nil }
    func savePrivateKey(_ nsec: String, for accountID: String, backupToICloud: Bool) throws {
        throw AuthPrivateKeyStoreError.keychainFailure(errSecInteractionNotAllowed)
    }
    func iCloudPrivateKeyBackups() -> [AuthICloudPrivateKeyBackup] { [] }
    func removePrivateKey(for accountID: String) {}
}
