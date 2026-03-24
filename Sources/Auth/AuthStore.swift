import Foundation

final class AuthStore: @unchecked Sendable {
    static let shared = AuthStore()

    private let defaults: UserDefaults
    private let accountsKey = "flow.auth.accounts"
    private let currentAccountIDKey = "flow.auth.currentAccountID"
    private let legacyAccountsKey = "x21.auth.accounts"
    private let legacyCurrentAccountIDKey = "x21.auth.currentAccountID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> (accounts: [StoredAuthAccount], currentAccountID: String?) {
        let accountsData = defaults.data(forKey: accountsKey) ?? defaults.data(forKey: legacyAccountsKey)
        let accounts: [StoredAuthAccount]
        if let accountsData,
           let decoded = try? JSONDecoder().decode([StoredAuthAccount].self, from: accountsData) {
            accounts = decoded
            if defaults.data(forKey: accountsKey) == nil {
                defaults.set(accountsData, forKey: accountsKey)
            }
        } else {
            accounts = []
        }

        let currentAccountID = defaults.string(forKey: currentAccountIDKey) ?? defaults.string(forKey: legacyCurrentAccountIDKey)
        if defaults.string(forKey: currentAccountIDKey) == nil, let currentAccountID {
            defaults.set(currentAccountID, forKey: currentAccountIDKey)
        }
        return (accounts, currentAccountID)
    }

    func save(accounts: [StoredAuthAccount], currentAccountID: String?) {
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: accountsKey)
        }

        if let currentAccountID {
            defaults.set(currentAccountID, forKey: currentAccountIDKey)
        } else {
            defaults.removeObject(forKey: currentAccountIDKey)
        }
    }
}
