import CryptoKit
import Foundation

actor RecentFeedStore {
    static let shared = RecentFeedStore()

    private struct Payload: Codable {
        let storedAt: Date
        let events: [NostrEvent]
    }

    private let fileManager: FileManager
    private let directoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maxSnapshots = 40

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let root = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directoryURL = root.appendingPathComponent("x21-recent-feeds", isDirectory: true)
    }

    func getRecentFeed(key: String) async -> [NostrEvent]? {
        ensureDirectory()
        let url = fileURL(for: key)

        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: url),
              let payload = try? decoder.decode(Payload.self, from: data) else {
            return nil
        }

        return payload.events
    }

    func putRecentFeed(key: String, events: [NostrEvent]) async {
        guard !events.isEmpty else { return }
        ensureDirectory()

        let payload = Payload(storedAt: Date(), events: events)
        guard let data = try? encoder.encode(payload) else {
            return
        }

        let url = fileURL(for: key)
        try? data.write(to: url, options: .atomic)
        pruneIfNeeded()
    }

    private func ensureDirectory() {
        if fileManager.fileExists(atPath: directoryURL.path) {
            return
        }

        try? fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hashed = digest.map { String(format: "%02x", $0) }.joined()
        return directoryURL.appendingPathComponent("\(hashed).json", isDirectory: false)
    }

    private func pruneIfNeeded() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        if files.count <= maxSnapshots {
            return
        }

        let sorted = files.sorted { lhs, rhs in
            let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lDate > rDate
        }

        for url in sorted.dropFirst(maxSnapshots) {
            try? fileManager.removeItem(at: url)
        }
    }
}
