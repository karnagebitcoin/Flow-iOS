import CryptoKit
import Foundation

struct NoteReaction: Codable, Hashable, Sendable {
    let id: String
    let pubkey: String
    let createdAt: Int
    let emoji: String
}

struct NoteReactionStats: Codable, Hashable, Sendable {
    var reactionIDs: Set<String> = []
    var reactions: [NoteReaction] = []
    var updatedAt: Int?
}

actor NoteReactionStatsStore {
    static let shared = NoteReactionStatsStore()

    private struct Payload: Codable {
        let storedAt: Date
        let stats: NoteReactionStats
    }

    private let fileManager: FileManager
    private let directoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let maxSnapshots = 3_000
    private let maxAge: TimeInterval = 60 * 60 * 24 * 7

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let root = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directoryURL = root.appendingPathComponent("x21-note-reaction-stats", isDirectory: true)
    }

    func getMany(noteIDs: [String]) async -> [String: NoteReactionStats] {
        guard !noteIDs.isEmpty else { return [:] }
        ensureDirectory()

        var result: [String: NoteReactionStats] = [:]
        let uniqueIDs = Set(noteIDs)

        for noteID in uniqueIDs {
            guard let payload = readPayload(noteID: noteID) else { continue }
            result[noteID] = payload.stats
        }

        return result
    }

    func putMany(entries: [String: NoteReactionStats]) async {
        guard !entries.isEmpty else { return }
        ensureDirectory()

        for (noteID, stats) in entries {
            let payload = Payload(storedAt: Date(), stats: stats)
            guard let data = try? encoder.encode(payload) else { continue }
            let url = fileURL(for: noteID)
            try? data.write(to: url, options: .atomic)
        }

        pruneIfNeeded()
    }

    private func readPayload(noteID: String) -> Payload? {
        let url = fileURL(for: noteID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url),
              let payload = try? decoder.decode(Payload.self, from: data) else {
            return nil
        }

        if Date().timeIntervalSince(payload.storedAt) > maxAge {
            try? fileManager.removeItem(at: url)
            return nil
        }

        return payload
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
