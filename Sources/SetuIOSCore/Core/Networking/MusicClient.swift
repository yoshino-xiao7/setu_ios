import Foundation

public struct MusicClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func search(keywords: String, limit: Int = 20, offset: Int = 0) async throws -> MusicSearchResult {
        let encodedKeywords = keywords.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keywords
        return try await apiClient.get("/user/music/search?keywords=\(encodedKeywords)&limit=\(limit)&offset=\(offset)")
    }

    public func hotSearch() async throws -> MusicHotSearchResponse {
        try await apiClient.get("/user/music/search/hot")
    }

    public func playlists() async throws -> [UserMusicPlaylist] {
        try await apiClient.get("/user/playlists")
    }

    public func history(limit: Int = 20, offset: Int = 0) async throws -> [MusicHistoryRecord] {
        try await apiClient.get("/user/music/history?limit=\(limit)&offset=\(offset)")
    }

    public func historyCount() async throws -> Int {
        try await apiClient.get("/user/music/history/count")
    }

    public func clearHistory() async throws {
        let _: String = try await apiClient.requestWithoutBody("/user/music/history", method: "DELETE")
    }
}
