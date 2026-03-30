import Foundation
import UniformTypeIdentifiers

struct SharedComposeAttachment: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let relativePath: String
    let mimeType: String
    let fileExtension: String
    let originalFilename: String?
    let fileSizeBytes: Int?

    init(
        id: UUID = UUID(),
        relativePath: String,
        mimeType: String,
        fileExtension: String,
        originalFilename: String? = nil,
        fileSizeBytes: Int? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.mimeType = mimeType
        self.fileExtension = fileExtension
        self.originalFilename = originalFilename
        self.fileSizeBytes = fileSizeBytes
    }

    var resolvedFileURL: URL? {
        try? FlowSharedComposeDraftStore.fileURL(forRelativePath: relativePath)
    }
}

struct SharedComposeDraft: Codable, Sendable {
    let id: UUID
    let createdAt: Date
    let attachments: [SharedComposeAttachment]
}

struct SharedComposePendingItem: Sendable {
    let fileURL: URL?
    let data: Data?
    let mimeType: String
    let fileExtension: String
    let originalFilename: String?

    init(
        fileURL: URL,
        mimeType: String,
        fileExtension: String,
        originalFilename: String? = nil
    ) {
        self.fileURL = fileURL
        self.data = nil
        self.mimeType = mimeType
        self.fileExtension = fileExtension
        self.originalFilename = originalFilename
    }

    init(
        data: Data,
        mimeType: String,
        fileExtension: String,
        originalFilename: String? = nil
    ) {
        self.fileURL = nil
        self.data = data
        self.mimeType = mimeType
        self.fileExtension = fileExtension
        self.originalFilename = originalFilename
    }
}

enum FlowSharedComposeDraftStoreError: LocalizedError {
    case unavailableAppGroupContainer
    case missingSourceFileData

    var errorDescription: String? {
        switch self {
        case .unavailableAppGroupContainer:
            return "Flow couldn't access its shared container."
        case .missingSourceFileData:
            return "The selected media couldn't be prepared for sharing."
        }
    }
}

enum FlowSharedComposeDraftStore {
    static let appGroupIdentifier = "group.com.21media.flow"
    private static let urlScheme = "flow"
    private static let shareHost = "share"
    private static let newNotePath = "/new-note"
    private static let draftsDirectoryName = "SharedComposeDrafts"
    private static let pendingDraftFilename = "pending-compose-draft.json"

    static var shareComposeURL: URL {
        URL(string: "\(urlScheme)://\(shareHost)\(newNotePath)")!
    }

    static func canHandleIncomingURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased() else {
            return false
        }

        return scheme == urlScheme &&
            host == shareHost &&
            url.path.lowercased() == newNotePath
    }

    static func loadPendingDraft() -> SharedComposeDraft? {
        guard let pendingDraftURL = try? pendingDraftURL(),
              FileManager.default.fileExists(atPath: pendingDraftURL.path),
              let data = try? Data(contentsOf: pendingDraftURL) else {
            return nil
        }

        return try? JSONDecoder().decode(SharedComposeDraft.self, from: data)
    }

    static func takePendingDraft() -> SharedComposeDraft? {
        guard let draft = loadPendingDraft() else { return nil }
        if let pendingDraftURL = try? pendingDraftURL() {
            try? FileManager.default.removeItem(at: pendingDraftURL)
        }
        return draft
    }

    static func savePendingDraft(items: [SharedComposePendingItem]) throws -> SharedComposeDraft {
        guard !items.isEmpty else {
            throw FlowSharedComposeDraftStoreError.missingSourceFileData
        }

        if let existingDraft = loadPendingDraft() {
            cleanupDraft(existingDraft)
        }

        let draftID = UUID()
        var attachments: [SharedComposeAttachment] = []

        for item in items {
            let normalizedExtension = normalizedFileExtension(
                item.fileExtension,
                mimeType: item.mimeType
            )
            let relativePath = stagedRelativePath(
                draftID: draftID,
                fileExtension: normalizedExtension
            )
            let destinationURL = try fileURL(forRelativePath: relativePath)

            try createDirectoryIfNeeded(at: destinationURL.deletingLastPathComponent())

            if let fileURL = item.fileURL {
                try replaceItem(at: destinationURL, withItemAt: fileURL)
            } else if let data = item.data {
                try data.write(to: destinationURL, options: .atomic)
            } else {
                throw FlowSharedComposeDraftStoreError.missingSourceFileData
            }

            let fileSizeBytes = (try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                ?? item.data?.count

            attachments.append(
                SharedComposeAttachment(
                    relativePath: relativePath,
                    mimeType: item.mimeType,
                    fileExtension: normalizedExtension,
                    originalFilename: item.originalFilename,
                    fileSizeBytes: fileSizeBytes
                )
            )
        }

        let draft = SharedComposeDraft(
            id: draftID,
            createdAt: Date(),
            attachments: attachments
        )
        let data = try JSONEncoder().encode(draft)
        try createDirectoryIfNeeded(at: try baseDirectoryURL())
        try data.write(to: try pendingDraftURL(), options: .atomic)
        return draft
    }

    static func cleanupDraft(_ draft: SharedComposeDraft) {
        cleanupAttachmentFiles(draft.attachments)
    }

    static func cleanupAttachmentFiles(_ attachments: [SharedComposeAttachment]) {
        let fileManager = FileManager.default
        var parentDirectories = Set<URL>()

        for attachment in attachments {
            guard let fileURL = attachment.resolvedFileURL else { continue }
            try? fileManager.removeItem(at: fileURL)
            parentDirectories.insert(fileURL.deletingLastPathComponent())
        }

        for directoryURL in parentDirectories.sorted(by: { $0.path.count > $1.path.count }) {
            let contents = (try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )) ?? []
            guard contents.isEmpty else { continue }
            try? fileManager.removeItem(at: directoryURL)
        }
    }

    static func fileURL(forRelativePath relativePath: String) throws -> URL {
        try baseDirectoryURL().appendingPathComponent(relativePath, isDirectory: false)
    }

    private static func baseDirectoryURL() throws -> URL {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw FlowSharedComposeDraftStoreError.unavailableAppGroupContainer
        }

        let directoryURL = containerURL.appendingPathComponent(
            draftsDirectoryName,
            isDirectory: true
        )
        try createDirectoryIfNeeded(at: directoryURL)
        return directoryURL
    }

    private static func pendingDraftURL() throws -> URL {
        try baseDirectoryURL().appendingPathComponent(
            pendingDraftFilename,
            isDirectory: false
        )
    }

    private static func stagedRelativePath(draftID: UUID, fileExtension: String) -> String {
        let normalizedDraftID = draftID.uuidString.lowercased()
        let normalizedFileExtension = normalizedFileExtension(fileExtension, mimeType: nil)
        return "draft-\(normalizedDraftID)/\(UUID().uuidString.lowercased()).\(normalizedFileExtension)"
    }

    private static func createDirectoryIfNeeded(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            return
        }
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    private static func replaceItem(at destinationURL: URL, withItemAt sourceURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    private static func normalizedFileExtension(_ fileExtension: String, mimeType: String?) -> String {
        let trimmed = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        if !trimmed.isEmpty {
            return trimmed
        }

        if let mimeType,
           let inferredType = UTType(mimeType: mimeType),
           let inferredExtension = inferredType.preferredFilenameExtension,
           !inferredExtension.isEmpty {
            return inferredExtension.lowercased()
        }

        return "bin"
    }
}
