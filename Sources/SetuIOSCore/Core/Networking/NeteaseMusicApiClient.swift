import Foundation

public struct NeteaseMusicApiClient: Sendable {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = URL(string: "https://musici.yukiryou.icu")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: QR Login

    public func createQrKey() async throws -> String {
        let url = try makeURL(path: "/login/qr/key", query: ["timestamp": String(Int(Date().timeIntervalSince1970 * 1000))])
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(NeteaseQrKeyResponse.self, from: data)
        return resp.data.unikey
    }

    public func createQrImage(key: String) async throws -> (qrimg: String, qrurl: String) {
        let url = try makeURL(path: "/login/qr/create", query: [
            "key": key,
            "qrimg": "true",
            "timestamp": String(Int(Date().timeIntervalSince1970 * 1000))
        ])
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(NeteaseQrCreateResponse.self, from: data)
        return (qrimg: resp.data.qrimg, qrurl: resp.data.qrurl)
    }

    public func checkQrStatus(key: String) async throws -> NeteaseQrCheckResponse {
        let url = try makeURL(path: "/login/qr/check", query: [
            "key": key,
            "timestamp": String(Int(Date().timeIntervalSince1970 * 1000))
        ])
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(NeteaseQrCheckResponse.self, from: data)
    }

    // MARK: SMS Captcha Login

    public func sendCaptcha(phone: String) async throws -> Bool {
        let url = try makeURL(path: "/captcha/sent", query: [
            "phone": phone,
            "timestamp": String(Int(Date().timeIntervalSince1970 * 1000))
        ])
        let (data, _) = try await session.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? Int, code == 200 else {
            return false
        }
        return true
    }

    public func loginWithCellphone(phone: String, captcha: String) async throws -> (cookie: String, profile: NeteaseUserProfile?) {
        let url = try makeURL(path: "/login/cellphone", query: [
            "phone": phone,
            "captcha": captcha,
            "timestamp": String(Int(Date().timeIntervalSince1970 * 1000))
        ])
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(NeteaseCellphoneLoginResponse.self, from: data)
        guard let cookie = resp.cookie, resp.code == 200 else {
            throw UserFacingError(message: resp.message ?? "登录失败，请检查验证码")
        }
        return (cookie: cookie, profile: resp.profile)
    }

    // MARK: User Profile & Playlists

    public func fetchLoginStatus(cookie: String) async throws -> NeteaseUserProfile? {
        let url = try makeURL(path: "/login/status", query: [
            "cookie": cookie,
            "timestamp": String(Int(Date().timeIntervalSince1970 * 1000))
        ])
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(NeteaseLoginStatusResponse.self, from: data)
        return resp.data.profile
    }

    public func fetchUserPlaylists(uid: Int, cookie: String) async throws -> [NeteaseUserPlaylist] {
        let url = try makeURL(path: "/user/playlist", query: [
            "uid": String(uid),
            "cookie": cookie,
            "limit": "100",
            "timestamp": String(Int(Date().timeIntervalSince1970 * 1000))
        ])
        let (data, _) = try await session.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let playlistArray = json["playlist"] else {
            return []
        }
        let playlistData = try JSONSerialization.data(withJSONObject: playlistArray)
        return try JSONDecoder().decode([NeteaseUserPlaylist].self, from: playlistData)
    }

    // MARK: Song Playback Resolution

    public func fetchSongPlaybackUrl(id: Int, level: String = "standard", cookie: String?) async throws -> NeteaseSongUrlItem? {
        var queryParams: [String: String] = [
            "id": String(id),
            "level": level,
            "timestamp": String(Int(Date().timeIntervalSince1970 * 1000))
        ]
        if let cookie, !cookie.isEmpty {
            queryParams["cookie"] = cookie
        }
        let url = try makeURL(path: "/song/url/v1", query: queryParams)
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(NeteaseSongUrlResponse.self, from: data)
        return resp.data.first(where: { $0.id == id && $0.isPlayable }) ?? resp.data.first
    }

    // MARK: Playlist Write Operations

    public func addSongToPlaylist(pid: Int, trackID: Int, cookie: String) async throws -> Bool {
        let url = try makeURL(path: "/playlist/tracks", query: [
            "op": "add",
            "pid": String(pid),
            "tracks": String(trackID),
            "cookie": cookie,
            "timestamp": String(Int(Date().timeIntervalSince1970 * 1000))
        ])
        let (data, _) = try await session.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if let code = json["code"] as? Int, code == 200 { return true }
        if let body = json["body"] as? [String: Any], let code = body["code"] as? Int, code == 200 { return true }
        return false
    }

    public func createPlaylist(name: String, cookie: String) async throws -> Int? {
        let url = try makeURL(path: "/playlist/create", query: [
            "name": name,
            "cookie": cookie,
            "timestamp": String(Int(Date().timeIntervalSince1970 * 1000))
        ])
        let (data, _) = try await session.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let id = json["id"] as? Int { return id }
        if let playlist = json["playlist"] as? [String: Any], let id = playlist["id"] as? Int { return id }
        return nil
    }

    public func logout(cookie: String) async throws {
        let url = try makeURL(path: "/logout", query: [
            "cookie": cookie,
            "timestamp": String(Int(Date().timeIntervalSince1970 * 1000))
        ])
        _ = try? await session.data(from: url)
    }

    // MARK: Similar Recommendations

    public func fetchSimilarSongs(id: Int, cookie: String? = nil) async throws -> [NeteaseSimilarSongItem] {
        var query: [String: String] = [
            "id": String(id),
            "timestamp": String(Int(Date().timeIntervalSince1970 * 1000))
        ]
        if let cookie, !cookie.isEmpty { query["cookie"] = cookie }
        let url = try makeURL(path: "/simi/song", query: query)
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(NeteaseSimilarSongsResponse.self, from: data)
        return resp.songs ?? []
    }

    public func fetchSimilarPlaylists(id: Int, cookie: String? = nil) async throws -> [NeteaseSimilarPlaylistItem] {
        var query: [String: String] = [
            "id": String(id),
            "timestamp": String(Int(Date().timeIntervalSince1970 * 1000))
        ]
        if let cookie, !cookie.isEmpty { query["cookie"] = cookie }
        let url = try makeURL(path: "/simi/playlist", query: query)
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(NeteaseSimilarPlaylistsResponse.self, from: data)
        return resp.playlists ?? []
    }

    // MARK: Helper

    private func makeURL(path: String, query: [String: String]) throws -> URL {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true) else {
            throw UserFacingError(message: "无效的 URL 地址")
        }
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else {
            throw UserFacingError(message: "无法生成请求地址")
        }
        return url
    }
}
