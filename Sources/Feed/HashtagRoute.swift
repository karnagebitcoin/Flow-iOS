import Foundation

struct HashtagRoute: Identifiable, Hashable {
    let hashtag: String
    
    var normalizedHashtag: String {
        hashtag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .lowercased()
    }
    
    var id: String {
        normalizedHashtag
    }
}
