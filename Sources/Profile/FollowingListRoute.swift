import Foundation

struct FollowingListRoute: Identifiable, Hashable {
    let pubkey: String

    var id: String {
        pubkey.lowercased()
    }
}
