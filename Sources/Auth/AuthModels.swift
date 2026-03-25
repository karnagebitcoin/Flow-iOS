import Foundation

enum AuthSignerType: String, Codable, Hashable, Sendable {
    case nsec
    case npub
}

struct StoredAuthAccount: Codable, Hashable, Sendable {
    let pubkey: String
    let npub: String
    let signerType: AuthSignerType
    let nsec: String?
    let privateKeyBackupEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case pubkey
        case npub
        case signerType
        case nsec
        case privateKeyBackupEnabled
    }

    init(
        pubkey: String,
        npub: String,
        signerType: AuthSignerType,
        nsec: String? = nil,
        privateKeyBackupEnabled: Bool = false
    ) {
        self.pubkey = pubkey
        self.npub = npub
        self.signerType = signerType
        self.nsec = nsec
        self.privateKeyBackupEnabled = privateKeyBackupEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pubkey = try container.decode(String.self, forKey: .pubkey)
        npub = try container.decode(String.self, forKey: .npub)
        signerType = try container.decode(AuthSignerType.self, forKey: .signerType)
        nsec = try container.decodeIfPresent(String.self, forKey: .nsec)
        privateKeyBackupEnabled = try container.decodeIfPresent(Bool.self, forKey: .privateKeyBackupEnabled) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pubkey, forKey: .pubkey)
        try container.encode(npub, forKey: .npub)
        try container.encode(signerType, forKey: .signerType)
        try container.encodeIfPresent(nsec, forKey: .nsec)
        try container.encode(privateKeyBackupEnabled, forKey: .privateKeyBackupEnabled)
    }

    var id: String {
        "\(signerType.rawValue):\(pubkey)"
    }
}

struct AuthAccount: Identifiable, Hashable, Sendable {
    let pubkey: String
    let npub: String
    let signerType: AuthSignerType
    let privateKeyBackupEnabled: Bool

    var id: String {
        "\(signerType.rawValue):\(pubkey)"
    }

    var shortLabel: String {
        let prefix = String(npub.prefix(10))
        let suffix = String(npub.suffix(6))
        return "\(prefix)...\(suffix)"
    }
}

struct GeneratedNostrAccount: Hashable, Sendable {
    let pubkey: String
    let npub: String
    let nsec: String
}
