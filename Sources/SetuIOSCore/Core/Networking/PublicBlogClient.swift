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
