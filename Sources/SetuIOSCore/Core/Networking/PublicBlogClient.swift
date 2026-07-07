import Foundation

public struct PublicBlogClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func dailySetu() async throws -> SetuImageItem? {
        let response: PublicBlogSetuResponse = try await apiClient.get("/blog/setu", signed: false)
        return response.items.first
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
