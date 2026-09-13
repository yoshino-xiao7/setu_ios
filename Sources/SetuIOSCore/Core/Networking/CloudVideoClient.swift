import Foundation

public struct CloudVideoClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func list(offset: Int = 0, limit: Int = 24) async throws -> CloudVideoPage {
        try await apiClient.get("/user/cloud-video?offset=\(offset)&limit=\(limit)")
    }

    public func search(keywords: String, offset: Int = 0, limit: Int = 24) async throws -> CloudVideoPage {
        let encoded = keywords.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keywords
        return try await apiClient.get("/user/cloud-video/search?keywords=\(encoded)&offset=\(offset)&limit=\(limit)")
    }

    public func catalog(keywords: String, offset: Int, limit: Int) async throws -> CloudVideoPage {
        let trimmed = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return try await list(offset: offset, limit: limit)
        }
        return try await search(keywords: trimmed, offset: offset, limit: limit)
    }

    public func detail(id: Int) async throws -> CloudVideoItem {
        try await apiClient.get("/user/cloud-video/\(id)")
    }

    public func playback(id: Int) async throws -> CloudVideoPlayback {
        try await apiClient.get("/user/cloud-video/\(id)/playback")
    }
}
