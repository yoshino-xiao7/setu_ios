import Foundation

public struct PublicBlogClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func dailySetu() async throws -> SetuImageItem? {
        let response: PublicBlogSetuResponse = try await apiClient.get(
            "/blog/setu",
            signed: false,
            headers: sourceHeaders()
        )
        return response.items.first
    }

    public func searchMusic(
        keywords: String,
        limit: Int = 30,
        offset: Int = 0,
        type: Int = 1
    ) async throws -> MusicSearchResult {
        let trimmedKeywords = String(keywords.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard !trimmedKeywords.isEmpty else {
            throw APIError.invalidURL("/blog/music/search")
        }

        let encodedKeywords = trimmedKeywords.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmedKeywords
        let clampedLimit = min(max(limit, 1), 50)
        let clampedOffset = min(max(offset, 0), 1000)
        let clampedType = min(max(type, 1), 1000)
        return try await apiClient.get(
            "/blog/music/search?keywords=\(encodedKeywords)&limit=\(clampedLimit)&offset=\(clampedOffset)&type=\(clampedType)",
            signed: false,
            headers: sourceHeaders()
        )
    }

    private func sourceHeaders() -> [String: String] {
        [
            "Origin": siteOrigin(),
            "Referer": apiClient.config.siteBaseURL.appendingPathComponent("docs").absoluteString,
            "User-Agent": "SetuIOSApp/1.0 iOS"
        ]
    }

    private func siteOrigin() -> String {
        guard let scheme = apiClient.config.siteBaseURL.scheme,
              let host = apiClient.config.siteBaseURL.host
        else {
            return apiClient.config.siteBaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        var origin = "\(scheme)://\(host)"
        if let port = apiClient.config.siteBaseURL.port {
            origin += ":\(port)"
        }
        return origin
    }
}

private struct PublicBlogSetuResponse: Decodable, Sendable {
    let items: [SetuImageItem]

    init(from decoder: Decoder) throws {
        if let item = try? SetuImageItem(from: decoder) {
            items = [item]
            return
        }
        if let array = try? [SetuImageItem](from: decoder) {
            items = array
            return
        }
        let envelope = try APIEnvelope<FlexibleSetuPayload>(from: decoder)
        items = envelope.data?.items ?? []
    }
}

private struct FlexibleSetuPayload: Decodable, Sendable {
    let items: [SetuImageItem]

    init(from decoder: Decoder) throws {
        if let item = try? SetuImageItem(from: decoder) {
            items = [item]
            return
        }
        if let array = try? [SetuImageItem](from: decoder) {
            items = array
            return
        }
        items = []
    }
}
