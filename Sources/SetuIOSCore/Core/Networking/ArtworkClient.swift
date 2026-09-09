import Foundation

public struct ArtworkClient: Sendable {
    private let apiClient: APIClient
    private let online: (any PixivOnlineServing)?
    public init(apiClient: APIClient, online: (any PixivOnlineServing)? = nil) { self.apiClient = apiClient; self.online = online }

    public func binding() async throws -> PixivAccountBinding {
        guard let online else { return PixivAccountBinding(bound: false, accountId: nil, name: nil, version: nil) }
        return try await online.binding()
    }
    public func authorize() async throws -> PixivAuthorization { try await requireOnline().authorize() }
    public func complete(sessionID: String, code: String) async throws -> PixivAccountBinding { try await requireOnline().complete(sessionID: sessionID, code: code) }
    public func unlink() async throws { try await requireOnline().unlink() }
    public func works(source: ArtworkSource, params: [String: String] = [:]) async throws -> ArtworkListResponse {
        if source == .pixiv { return try await requireOnline().works(params: params) }
        var components = URLComponents()
        components.path = "/user/images/works"
        components.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return try await apiClient.get(components.string ?? components.path)
    }
    public func detail(source: ArtworkSource, id: String) async throws -> BrowserArtwork {
        if source == .pixiv { return try await requireOnline().detail(id: id) }
        return try await apiClient.get("/user/images/works/\(segment(id))")
    }
    public func artists() async throws -> [ArtworkArtist] { try await requireOnline().artists() }
    public func spotlights() async throws -> [ArtworkSpotlight] { try await requireOnline().spotlights() }
    public func bookmark(_ work: BrowserArtwork, enabled: Bool, page: ArtworkPage? = nil, visibility: String = "public") async throws {
        if work.source == .pixiv { try await requireOnline().bookmark(id: work.id, enabled: enabled, visibility: visibility); return }
        struct Request: Encodable, Sendable { let enabled: Bool; let visibility: String; let page: Int? }
        let suffix = page.map { "/pages/\(segment($0.pid))/\($0.index)" } ?? ""
        let _: EmptyResponse = try await apiClient.put("/user/images/works/\(segment(work.id))\(suffix)/bookmark", body: Request(enabled: enabled, visibility: visibility, page: page?.index))
    }
    public func follow(_ artist: ArtworkArtist, enabled: Bool) async throws { try await requireOnline().follow(id: artist.id, enabled: enabled) }
    public func animation(workID: String) async throws -> ArtworkAnimation { try await requireOnline().animation(workID: workID) }
    public func animationStatus(id: String) async throws -> ArtworkAnimation { try await requireOnline().animationStatus(id: id) }
    public func media(_ path: String) async throws -> Data {
        if path.hasPrefix("pixiv-local://") { return try await requireOnline().media(path) }
        guard path.hasPrefix("/user/images/media/"), !path.contains(".."), !path.contains("\\") else { throw APIError.invalidURL(path) }
        return try await apiClient.getData(path)
    }
    private func requireOnline() throws -> any PixivOnlineServing {
        guard let online else { throw PixivClientError("请登录亦可并重新打开图片页") }
        return online
    }
    private func segment(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "" }
}
