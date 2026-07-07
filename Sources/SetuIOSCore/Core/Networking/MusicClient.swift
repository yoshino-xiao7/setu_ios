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

    public func url(songID: Int, level: String = "standard") async throws -> MusicUrlResponse {
        try await apiClient.get("/user/music/url?id=\(songID)&level=\(level)")
    }

    public func lyric(songID: Int) async throws -> MusicLyricResponse {
        try await apiClient.get("/user/music/lyric?id=\(songID)")
    }

    public func mvDetail(id: Int) async throws -> MusicMvDetailResponse {
        try await apiClient.get("/user/music/mv/detail?mvid=\(id)")
    }

    public func mvUrl(id: Int, resolution: Int? = nil) async throws -> MusicMvUrlResponse {
        if let resolution {
            return try await apiClient.get("/user/music/mv/url?id=\(id)&r=\(resolution)")
        }
        return try await apiClient.get("/user/music/mv/url?id=\(id)")
    }

    public func playlists() async throws -> [UserMusicPlaylist] {
        try await apiClient.get("/user/playlists")
    }

    public func playlist(id: Int) async throws -> UserMusicPlaylistDetail {
        try await apiClient.get("/user/playlists/\(id)")
    }

    public func createPlaylist(name: String, description: String? = nil, isPublic: Int = 0) async throws -> UserMusicPlaylist {
        try await apiClient.post(
            "/user/playlists",
            body: CreateMusicPlaylistRequest(name: name, description: description, isPublic: isPublic)
        )
    }

    public func updatePlaylist(id: Int, name: String, description: String? = nil, coverUrl: String? = nil, isPublic: Int = 0) async throws -> UserMusicPlaylist {
        try await apiClient.put(
            "/user/playlists/\(id)",
            body: CreateMusicPlaylistRequest(name: name, description: description, coverUrl: coverUrl, isPublic: isPublic)
        )
    }

    public func deletePlaylist(id: Int) async throws {
        let _: String = try await apiClient.requestWithoutBody("/user/playlists/\(id)", method: "DELETE")
    }

    public func recordPlaylistPlay(id: Int) async throws {
        let _: String = try await apiClient.post("/user/playlists/\(id)/play")
    }

    public func setPlayMode(playlistID: Int, playMode: String) async throws {
        let _: String = try await apiClient.put(
            "/user/playlists/\(playlistID)/play-mode",
            body: UpdateMusicPlayModeRequest(playMode: playMode)
        )
    }

    public func add(song: MusicSong, toPlaylist playlistID: Int) async throws {
        let _: String = try await apiClient.post(
            "/user/playlists/\(playlistID)/songs",
            body: AddSongToPlaylistRequest(song: song)
        )
    }

    public func removeSong(playlistID: Int, songID: Int) async throws {
        let _: String = try await apiClient.requestWithoutBody("/user/playlists/\(playlistID)/songs/\(songID)", method: "DELETE")
    }

    public func history(limit: Int = 20, offset: Int = 0) async throws -> [MusicHistoryRecord] {
        try await apiClient.get("/user/music/history?limit=\(limit)&offset=\(offset)")
    }

    public func historyCount() async throws -> Int {
        try await apiClient.get("/user/music/history/count")
    }

    public func addHistory(song: MusicSong) async throws {
        let _: String = try await apiClient.post("/user/music/history", body: AddMusicHistoryRequest(song: song))
    }

    public func clearHistory() async throws {
        let _: String = try await apiClient.requestWithoutBody("/user/music/history", method: "DELETE")
    }
}
