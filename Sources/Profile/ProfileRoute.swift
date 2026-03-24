import Foundation

struct ProfileRoute: Identifiable, Hashable {
    let pubkey: String

    var id: String {
        pubkey.lowercased()
    }
}
