import Foundation

public struct MusicV2ServerError: Error, Hashable, Sendable {
    public let status: Int
    public let error: MusicV2Error
    public let requestID: String?

    public init(status: Int, error: MusicV2Error, requestID: String?) {
        self.status = status
        self.error = error
        self.requestID = requestID
    }
}

public struct MusicV2Client: Sendable {
    private static let base = "/user/music/v2"
    private let apiClient: APIClient

    public init(apiClient: APIClient) { self.apiClient = apiClient }

    public func home() async throws -> MusicV2HomeFeed {
        try await get("/home")
    }

    public func search(keywords: String, scope: MusicV2SearchScope = .tracks, limit: Int? = nil, offset: Int = 0) async throws -> MusicV2SearchResult {
        var values = [("keywords", keywords), ("scope", scope.rawValue)]
        if let limit { values.append(("limit", String(limit))) }
        if scope != .all || offset != 0 { values.append(("offset", String(offset))) }
        return try await get("/search" + query(values))
    }

    public func searchSuggestions(keywords: String) async throws -> MusicV2SearchSuggestions {
        try await get("/search/suggest" + query([("keywords", keywords)]))
    }

    public func hotSearch() async throws -> MusicV2HotSearch { try await get("/search/hot") }

    public func track(_ id: MusicV2TrackID) async throws -> MusicV2Track { try await get("/tracks/" + component(id.rawValue)) }
    public func tracks(_ ids: [MusicV2TrackID]) async throws -> MusicV2TrackBatch { try await get("/tracks?ids=" + idList(ids.map(\.rawValue))) }

    public func playback(
        trackID: MusicV2TrackID,
        level: MusicV2PlaybackQuality = .standard,
        allowFallback: Bool = true
    ) async throws -> MusicV2PlaybackResolution {
        try await get("/tracks/\(component(trackID.rawValue))/playback" + query([
            ("level", level.rawValue), ("allowFallback", String(allowFallback))
        ]))
    }

    public func playback(
        trackIDs: [MusicV2TrackID],
        level: MusicV2PlaybackQuality = .standard,
        allowFallback: Bool = true
    ) async throws -> MusicV2PlaybackBatch {
        try await get("/tracks/playback?ids=\(idList(trackIDs.map(\.rawValue)))&level=\(component(level.rawValue))&allowFallback=\(allowFallback)")
    }

    public func lyrics(trackID: MusicV2TrackID) async throws -> MusicV2Lyric { try await get("/tracks/\(component(trackID.rawValue))/lyrics") }
    public func similar(trackID: MusicV2TrackID) async throws -> MusicV2SimilarTracks { try await get("/tracks/\(component(trackID.rawValue))/similar") }
    public func artist(_ id: MusicV2ArtistID) async throws -> MusicV2ArtistDetail { try await get("/artists/" + component(id.rawValue)) }
    public func artistTracks(_ id: MusicV2ArtistID, limit: Int = 20, offset: Int = 0) async throws -> MusicV2TrackPage { try await get("/artists/\(component(id.rawValue))/tracks" + paging(limit, offset)) }
    public func artistAlbums(_ id: MusicV2ArtistID, limit: Int = 20, offset: Int = 0) async throws -> MusicV2AlbumPage { try await get("/artists/\(component(id.rawValue))/albums" + paging(limit, offset)) }
    public func artistMVs(_ id: MusicV2ArtistID, limit: Int = 20, offset: Int = 0) async throws -> MusicV2MvPage { try await get("/artists/\(component(id.rawValue))/mvs" + paging(limit, offset)) }
    public func album(_ id: MusicV2AlbumID) async throws -> MusicV2AlbumDetail { try await get("/albums/" + component(id.rawValue)) }
    public func playlist(_ id: MusicV2PlaylistID, limit: Int = 50, offset: Int = 0) async throws -> MusicV2PlaylistDetail { try await get("/playlists/\(component(id.rawValue))" + paging(limit, offset)) }
    public func playlistTracks(_ id: MusicV2PlaylistID, limit: Int = 50, offset: Int = 0) async throws -> MusicV2MembershipPage { try await get("/playlists/\(component(id.rawValue))/tracks" + paging(limit, offset)) }

    public func rankings() async throws -> MusicV2Rankings { try await get("/rankings") }
    public func recommendedTracks() async throws -> MusicV2RecommendedTracks { try await get("/recommend/tracks") }
    public func recommendedPlaylists(limit: Int = 20) async throws -> MusicV2RecommendedPlaylists { try await get("/recommend/playlists" + query([("limit", String(limit))])) }
    public func newReleaseTracks(area: MusicV2Area = .all, limit: Int = 30, offset: Int = 0) async throws -> MusicV2NewTracks { try await get("/new-releases/tracks" + query([("area", area.rawValue), ("limit", String(limit)), ("offset", String(offset))])) }
    public func newReleaseAlbums(area: MusicV2Area = .all, limit: Int = 30, offset: Int = 0) async throws -> MusicV2NewAlbums { try await get("/new-releases/albums" + query([("area", area.rawValue), ("limit", String(limit)), ("offset", String(offset))])) }

    /// FM is intentionally never routed through MusicRepository: each call must fetch a fresh batch.
    public func radioFM(limit: Int = 4) async throws -> MusicV2RadioBatch { try await get("/radio/fm" + query([("limit", String(limit))])) }
    public func blockRadioTrack(_ trackID: MusicV2TrackID) async throws { try await post204("/radio/fm/block", body: MusicV2FMBlockRequest(trackId: trackID)) }

    public func library() async throws -> MusicV2UserLibrary { try await get("/library") }
    public func likedTracks(limit: Int = 20, offset: Int = 0) async throws -> MusicV2LikedPage { try await get("/library/liked-tracks" + paging(limit, offset)) }
    public func like(_ trackID: MusicV2TrackID, snapshot: MusicV2TrackDisplaySnapshot? = nil) async throws { try await put204("/library/liked-tracks/" + component(trackID.rawValue), body: MusicV2LikeRequest(snapshot: snapshot)) }
    public func unlike(_ trackID: MusicV2TrackID) async throws { try await delete204("/library/liked-tracks/" + component(trackID.rawValue)) }
    public func favoritePlaylists(limit: Int = 20, offset: Int = 0) async throws -> MusicV2SavedPage { try await get("/library/favorite-playlists" + paging(limit, offset)) }
    public func savePlaylist(_ playlistID: MusicV2ProviderPlaylistID, snapshot: MusicV2PlaylistDisplaySnapshot? = nil) async throws { try await put204("/library/favorite-playlists/" + component(playlistID.rawValue), body: MusicV2SaveRequest(snapshot: snapshot)) }
    public func unsavePlaylist(_ playlistID: MusicV2ProviderPlaylistID) async throws { try await delete204("/library/favorite-playlists/" + component(playlistID.rawValue)) }
    public func history(limit: Int = 20, offset: Int = 0) async throws -> MusicV2HistoryPage { try await get("/library/history" + paging(limit, offset)) }
    public func recordHistory(trackID: MusicV2TrackID, snapshot: MusicV2TrackDisplaySnapshot? = nil) async throws { try await post204("/library/history", body: MusicV2HistoryRequest(trackId: trackID, snapshot: snapshot)) }
    public func clearHistory() async throws { try await delete204("/library/history") }

    private func get<Value: Decodable & Sendable>(_ path: String) async throws -> Value {
        try await translate { try await apiClient.get(Self.base + path, signed: false) }
    }

    private func post204<Body: Encodable & Sendable>(_ path: String, body: Body) async throws {
        let _: EmptyResponse = try await translate { try await apiClient.post(Self.base + path, body: body, signed: false) }
    }

    private func put204<Body: Encodable & Sendable>(_ path: String, body: Body) async throws {
        let _: EmptyResponse = try await translate { try await apiClient.put(Self.base + path, body: body, signed: false) }
    }

    private func delete204(_ path: String) async throws {
        let _: EmptyResponse = try await translate { try await apiClient.requestWithoutBody(Self.base + path, method: "DELETE", signed: false) }
    }

    private func translate<Value: Sendable>(_ operation: () async throws -> Value) async throws -> Value {
        do { return try await operation() }
        catch APIError.httpStatus(let status, let message, let requestID, let traceID, let rawCode) {
            if status == 401 {
                // V2 is SID-only (`signed: false`), so APIClient's HMAC-specific invalidation path
                // does not run. Preserve the same AuthSession invalidation behavior explicitly.
                await apiClient.sessionInvalidationNotifier?.notifyUnauthorized()
            }
            let code = MusicV2ErrorCode(rawValue: rawCode ?? "INTERNAL")
            let retryable: Bool = switch code {
            case .upstreamUnavailable, .upstreamAuthInvalid, .upstreamRateLimited, .rateLimited, .internalError: true
            default: false
            }
            throw MusicV2ServerError(
                status: status,
                error: MusicV2Error(code: code, message: message ?? "音乐请求失败", retryable: retryable, traceId: traceID),
                requestID: requestID
            )
        }
    }

    private func paging(_ limit: Int, _ offset: Int) -> String { query([("limit", String(limit)), ("offset", String(offset))]) }

    private func query(_ items: [(String, String)]) -> String {
        guard !items.isEmpty else { return "" }
        return "?" + items.map { "\(component($0.0))=\(component($0.1))" }.joined(separator: "&")
    }

    /// Encode the full opaque token as one URL component. Existing `%HH` inside a canonical
    /// identity is encoded again (`%` -> `%25`) and decoded exactly once by the HTTP framework.
    private func component(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? value
    }

    private func idList(_ ids: [String]) -> String { ids.map(component).joined(separator: ",") }
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
