import XCTest
import NostrSDK
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
}
