import Foundation

enum KlipyGIFServiceError: LocalizedError {
    case missingAppKey
    case invalidResponse
    case requestFailed(statusCode: Int)
    case missingAnimatedAsset
    case downloadFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .missingAppKey:
            return "GIF search isn't configured yet."
        case .invalidResponse:
            return "Klipy returned an invalid response."
        case .requestFailed(let statusCode):
            return "Klipy request failed (\(statusCode))."
        case .missingAnimatedAsset:
            return "That GIF is missing an animated file."
        case .downloadFailed(let statusCode):
            return "Couldn't download that GIF (\(statusCode))."
        }
    }
}

public struct KlipyGIFAsset: Decodable, Hashable, Sendable {
    public let url: URL
    public let width: Double?
    public let height: Double?
    public let size: Int?
}

public struct KlipyGIFAttachmentCandidate: Identifiable, Hashable, Sendable {
    public let slug: String
    public let title: String
    public let customerID: String
    public let searchQuery: String?
    public let previewURL: URL?
    public let previewWidth: Double?
    public let previewHeight: Double?
    public let downloadURL: URL

    public var id: String { slug }
    public var mimeType: String { "image/gif" }
    public var fileExtension: String { "gif" }
}

public struct KlipyGIFItem: Decodable, Hashable, Identifiable, Sendable {
    public let apiID: String
    public let slug: String
    public let title: String
    private let filesBySize: [String: [String: KlipyGIFAsset]]

    public var id: String {
        slug.isEmpty ? apiID : slug
    }

    public init(from decoder: Decoder) throws {
        enum CodingKeys: String, CodingKey {
            case id
            case slug
            case title
            case file
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let numericID = try? container.decode(Int64.self, forKey: .id) {
            apiID = String(numericID)
        } else {
            apiID = try container.decode(String.self, forKey: .id)
        }
        slug = (try? container.decode(String.self, forKey: .slug)) ?? apiID
        title = (try? container.decode(String.self, forKey: .title)) ?? ""

        let fileContainer = try container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .file)
        var decodedFiles: [String: [String: KlipyGIFAsset]] = [:]
        for sizeKey in fileContainer.allKeys {
            let formatContainer = try fileContainer.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: sizeKey)
            var formats: [String: KlipyGIFAsset] = [:]
            for formatKey in formatContainer.allKeys {
                if let asset = try? formatContainer.decode(KlipyGIFAsset.self, forKey: formatKey) {
                    formats[formatKey.stringValue.lowercased()] = asset
                }
            }
            decodedFiles[sizeKey.stringValue.lowercased()] = formats
        }
        filesBySize = decodedFiles
    }

    public func makeAttachmentCandidate(
        customerID: String,
        searchQuery: String?
    ) -> KlipyGIFAttachmentCandidate? {
        guard let animatedAsset = preferredAnimatedAsset else { return nil }
        let previewAsset = preferredPreviewAsset

        return KlipyGIFAttachmentCandidate(
            slug: slug,
            title: title,
            customerID: customerID,
            searchQuery: searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            previewURL: previewAsset?.url,
            previewWidth: previewAsset?.width,
            previewHeight: previewAsset?.height,
            downloadURL: animatedAsset.url
        )
    }

    public var preferredPreviewAsset: KlipyGIFAsset? {
        asset(format: "jpg", preferredSizes: ["sm", "md", "hd", "xs", "tiny"])
            ?? asset(format: "webp", preferredSizes: ["sm", "md", "hd", "xs", "tiny"])
            ?? preferredAnimatedAsset
    }

    var preferredAnimatedPreviewAsset: KlipyGIFAsset? {
        preferredAnimatedAsset
    }

    private var preferredAnimatedAsset: KlipyGIFAsset? {
        asset(format: "gif", preferredSizes: ["md", "sm", "xs", "tiny", "hd"])
    }

    private func asset(format: String, preferredSizes: [String]) -> KlipyGIFAsset? {
        for size in preferredSizes {
            if let asset = filesBySize[size]?[format] {
                return asset
            }
        }

        for formats in filesBySize.values {
            if let asset = formats[format] {
                return asset
            }
        }

        return nil
    }
}

actor KlipyGIFService {
    static let shared = KlipyGIFService()
    static let defaultPageSize = 24

    private let session: URLSession
    private let defaults: UserDefaults
    private let baseURL: URL
    private let appKey: String?
    private let anonymousCustomerIDDefaultsKey = "flow.klipy.anonymousCustomerID"

    init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        baseURL: URL = URL(string: "https://api.klipy.com")!,
        appKey: String? = Bundle.main.object(forInfoDictionaryKey: "KLIPYAppKey") as? String
    ) {
        self.session = session
        self.defaults = defaults
        self.baseURL = baseURL
        self.appKey = appKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    func customerID(for accountPubkey: String?) -> String {
        if let normalizedPubkey = accountPubkey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nilIfEmpty {
            return normalizedPubkey
        }

        if let existingID = defaults.string(forKey: anonymousCustomerIDDefaultsKey)?.nilIfEmpty {
            return existingID
        }

        let createdID = "flow-\(UUID().uuidString.lowercased())"
        defaults.set(createdID, forKey: anonymousCustomerIDDefaultsKey)
        return createdID
    }

    func trendingGIFs(
        customerID: String,
        page: Int,
        perPage: Int = defaultPageSize
    ) async throws -> [KlipyGIFItem] {
        try await fetchGIFs(
            path: "gifs/trending",
            customerID: customerID,
            page: page,
            perPage: perPage,
            query: nil
        )
    }

    func searchGIFs(
        query: String,
        customerID: String,
        page: Int,
        perPage: Int = defaultPageSize
    ) async throws -> [KlipyGIFItem] {
        try await fetchGIFs(
            path: "gifs/search",
            customerID: customerID,
            page: page,
            perPage: perPage,
            query: query
        )
    }

    func downloadGIFData(for candidate: KlipyGIFAttachmentCandidate) async throws -> Data {
        let (data, response) = try await session.data(from: candidate.downloadURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw KlipyGIFServiceError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw KlipyGIFServiceError.downloadFailed(statusCode: httpResponse.statusCode)
        }
        return data
    }

    func registerShare(
        slug: String,
        customerID: String,
        query: String?
    ) async {
        guard let appKey else { return }
        guard !slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        do {
            var components = URLComponents(
                url: baseURL.appendingPathComponent("api/v1/\(appKey)/gifs/share/\(slug)"),
                resolvingAgainstBaseURL: false
            )
            components?.percentEncodedPath = "/api/v1/\(appKey)/gifs/share/\(slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug)"
            guard let url = components?.url else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let payload = KlipyShareTriggerRequest(
                customerID: customerID,
                q: query?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )
            request.httpBody = try JSONEncoder().encode(payload)

            _ = try await session.data(for: request)
        } catch {
            return
        }
    }

    private func fetchGIFs(
        path: String,
        customerID: String,
        page: Int,
        perPage: Int,
        query: String?
    ) async throws -> [KlipyGIFItem] {
        guard let appKey else {
            throw KlipyGIFServiceError.missingAppKey
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/v1/\(appKey)/\(path)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = buildQueryItems(
            customerID: customerID,
            page: page,
            perPage: perPage,
            query: query
        )

        guard let url = components?.url else {
            throw KlipyGIFServiceError.invalidResponse
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw KlipyGIFServiceError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw KlipyGIFServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let payload = try decoder.decode(KlipyGIFListResponse.self, from: data)
        guard payload.result else {
            throw KlipyGIFServiceError.invalidResponse
        }
        return payload.data.data
    }

    private func buildQueryItems(
        customerID: String,
        page: Int,
        perPage: Int,
        query: String?
    ) -> [URLQueryItem] {
        var queryItems = [
            URLQueryItem(name: "page", value: String(max(page, 1))),
            URLQueryItem(name: "per_page", value: String(min(max(perPage, 1), 50))),
            URLQueryItem(name: "customer_id", value: customerID),
            URLQueryItem(name: "format_filter", value: "gif,jpg")
        ]

        if let localeCode = Self.localeCode {
            queryItems.append(URLQueryItem(name: "locale", value: localeCode))
        }

        if let query = query?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
            queryItems.append(URLQueryItem(name: "content_filter", value: "low"))
        }

        return queryItems
    }

    private static var localeCode: String? {
        if let region = Locale.autoupdatingCurrent.region?.identifier.lowercased(), !region.isEmpty {
            return region
        }
        if let languageCode = Locale.autoupdatingCurrent.language.languageCode?.identifier.lowercased(), !languageCode.isEmpty {
            return languageCode
        }
        return nil
    }
}

private struct KlipyGIFListResponse: Decodable {
    let result: Bool
    let data: KlipyGIFPage
}

private struct KlipyGIFPage: Decodable {
    let data: [KlipyGIFItem]
}

private struct KlipyShareTriggerRequest: Encodable {
    let customerID: String
    let q: String?

    enum CodingKeys: String, CodingKey {
        case customerID = "customer_id"
        case q
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
