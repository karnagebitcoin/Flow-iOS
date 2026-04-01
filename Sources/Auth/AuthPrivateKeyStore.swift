import Foundation
import Security

protocol AuthPrivateKeyStoring: Sendable {
    func privateKey(for accountID: String) -> String?
    func privateKeyMetadata(for accountID: String) -> AuthPrivateKeyMetadata?
    func savePrivateKey(_ nsec: String, for accountID: String, backupToICloud: Bool) throws
    func iCloudPrivateKeyBackups() -> [AuthICloudPrivateKeyBackup]
    func removePrivateKey(for accountID: String)
}

enum AuthPrivateKeyStoreError: LocalizedError {
    case encodingFailed
    case missingPrivateKey
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Couldn’t prepare the private key for secure storage."
        case .missingPrivateKey:
            return "This account does not have a private key available to back up."
        case .keychainFailure(let status):
            return "Secure storage failed with status \(status)."
        }
    }
}

struct AuthPrivateKeyMetadata: Hashable, Sendable {
    let isSynchronizable: Bool
    let createdAt: Date?
    let modifiedAt: Date?
}

struct AuthICloudPrivateKeyBackup: Identifiable, Hashable, Sendable {
    let accountID: String
    let createdAt: Date?
    let modifiedAt: Date?

    var id: String { accountID }

    var pubkey: String? {
        let prefix = "\(AuthSignerType.nsec.rawValue):"
        guard accountID.hasPrefix(prefix) else { return nil }
        let value = String(accountID.dropFirst(prefix.count)).lowercased()
        return value.isEmpty ? nil : value
    }
}

final class AuthPrivateKeyStore: @unchecked Sendable {
    static let shared = AuthPrivateKeyStore()

    private let service = "flow.auth.privateKey"
    private let legacyService = "x21.auth.privateKey"

    func privateKey(for accountID: String) -> String? {
        loadPrivateKey(for: accountID, service: service) ?? loadPrivateKey(for: accountID, service: legacyService)
    }

    func privateKeyMetadata(for accountID: String) -> AuthPrivateKeyMetadata? {
        loadPrivateKeyMetadata(for: accountID, service: service)
            ?? loadPrivateKeyMetadata(for: accountID, service: legacyService)
    }

    func savePrivateKey(_ nsec: String, for accountID: String, backupToICloud: Bool) throws {
        guard let data = nsec.data(using: .utf8) else {
            throw AuthPrivateKeyStoreError.encodingFailed
        }

        removePrivateKey(for: accountID)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
            kSecValueData as String: data
        ]

        if backupToICloud {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AuthPrivateKeyStoreError.keychainFailure(status)
        }
    }

    func iCloudPrivateKeyBackups() -> [AuthICloudPrivateKeyBackup] {
        let combined = loadSynchronizablePrivateKeyBackups(service: service)
            + loadSynchronizablePrivateKeyBackups(service: legacyService)

        var deduplicated: [String: AuthICloudPrivateKeyBackup] = [:]
        for backup in combined {
            if let existing = deduplicated[backup.accountID] {
                deduplicated[backup.accountID] = preferredBackup(between: existing, and: backup)
            } else {
                deduplicated[backup.accountID] = backup
            }
        }

        return deduplicated.values.sorted {
            let lhsDate = $0.modifiedAt ?? $0.createdAt ?? .distantPast
            let rhsDate = $1.modifiedAt ?? $1.createdAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return $0.accountID < $1.accountID
        }
    }

    func removePrivateKey(for accountID: String) {
        deletePrivateKey(for: accountID, service: service)
        deletePrivateKey(for: accountID, service: legacyService)
    }

    private func loadPrivateKey(for accountID: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else { return nil }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deletePrivateKey(for accountID: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func loadPrivateKeyMetadata(for accountID: String, service: String) -> AuthPrivateKeyMetadata? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else { return nil }
        guard let attributes = item as? [String: Any] else { return nil }

        let isSynchronizable: Bool
        if let number = attributes[kSecAttrSynchronizable as String] as? NSNumber {
            isSynchronizable = number.boolValue
        } else if let value = attributes[kSecAttrSynchronizable as String] as? Bool {
            isSynchronizable = value
        } else {
            isSynchronizable = false
        }

        let createdAt = attributes[kSecAttrCreationDate as String] as? Date
        let modifiedAt = attributes[kSecAttrModificationDate as String] as? Date

        return AuthPrivateKeyMetadata(
            isSynchronizable: isSynchronizable,
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )
    }

    private func loadSynchronizablePrivateKeyBackups(service: String) -> [AuthICloudPrivateKeyBackup] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { return [] }
        guard status == errSecSuccess else { return [] }

        let attributesList: [[String: Any]]
        if let list = item as? [[String: Any]] {
            attributesList = list
        } else if let attributes = item as? [String: Any] {
            attributesList = [attributes]
        } else {
            attributesList = []
        }

        return attributesList.compactMap { attributes in
            guard let accountID = attributes[kSecAttrAccount as String] as? String,
                  !accountID.isEmpty else {
                return nil
            }

            return AuthICloudPrivateKeyBackup(
                accountID: accountID,
                createdAt: attributes[kSecAttrCreationDate as String] as? Date,
                modifiedAt: attributes[kSecAttrModificationDate as String] as? Date
            )
        }
    }

    private func preferredBackup(
        between lhs: AuthICloudPrivateKeyBackup,
        and rhs: AuthICloudPrivateKeyBackup
    ) -> AuthICloudPrivateKeyBackup {
        let lhsDate = lhs.modifiedAt ?? lhs.createdAt ?? .distantPast
        let rhsDate = rhs.modifiedAt ?? rhs.createdAt ?? .distantPast
        if lhsDate == rhsDate {
            return lhs
        }
        return lhsDate > rhsDate ? lhs : rhs
    }
}

extension AuthPrivateKeyStore: AuthPrivateKeyStoring {}
