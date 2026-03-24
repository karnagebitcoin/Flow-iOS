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

    var id: String {
        "\(signerType.rawValue):\(pubkey)"
    }
}

struct AuthAccount: Identifiable, Hashable, Sendable {
    let pubkey: String
    let npub: String
    let signerType: AuthSignerType

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
