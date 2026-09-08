#if DEBUG
import Foundation
import SetuIOSCore

/// In-process screenshot fixtures only; live AppEnvironment always uses PixivLocalClient.
struct PreviewPixivOnlineClient: PixivOnlineServing {
    let api: APIClient
    func binding() async throws -> PixivAccountBinding { try await api.get("/user/pixiv/account") }
    func authorize() async throws -> PixivAuthorization { throw PixivClientError("预览不连接真实 Pixiv 账号") }
    func complete(sessionID: String, code: String) async throws -> PixivAccountBinding { throw PixivClientError("预览不连接真实 Pixiv 账号") }
    func unlink() async throws { }
    func works(params: [String: String]) async throws -> ArtworkListResponse {
        var url = URLComponents(); url.path = "/user/pixiv/works"
        url.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return try await api.get(url.string!)
    }
    func detail(id: String) async throws -> BrowserArtwork { try await api.get("/user/pixiv/works/" + id) }
    func artists() async throws -> [ArtworkArtist] { try await api.get("/user/pixiv/artists") }
    func spotlights() async throws -> [ArtworkSpotlight] { try await api.get("/user/pixiv/spotlights") }
    func bookmark(id: String, enabled: Bool, visibility: String) async throws { }
    func follow(id: String, enabled: Bool) async throws { }
    func animation(workID: String) async throws -> ArtworkAnimation { throw PixivClientError("预览未提供动图") }
    func animationStatus(id: String) async throws -> ArtworkAnimation { throw PixivClientError("预览未提供动图") }
    func media(_ path: String) async throws -> Data { try await api.getData(path) }
}
#endif
