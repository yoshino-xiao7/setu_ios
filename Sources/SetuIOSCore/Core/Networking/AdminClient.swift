import Foundation

public struct AdminClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func blogStats() async throws -> AdminBlogStats {
        try await apiClient.get("/admin/blog/stats")
    }

    public func users(
        page: Int = 1,
        pageSize: Int = 20,
        email: String? = nil,
        nickname: String? = nil,
        status: Int? = nil,
        role: Int? = nil
    ) async throws -> AdminUserListResponse {
        try await apiClient.get(queryPath(
            "/admin/users",
            items: [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "pageSize", value: "\(pageSize)"),
                URLQueryItem(name: "email", value: email),
                URLQueryItem(name: "nickname", value: nickname),
                URLQueryItem(name: "status", value: status.map(String.init)),
                URLQueryItem(name: "role", value: role.map(String.init))
            ]
        ))
    }

    public func userDetail(id: Int) async throws -> AdminUserDetail {
        try await apiClient.get("/admin/users/\(id)")
    }

    public func banUser(id: Int) async throws {
        let _: String = try await apiClient.post("/admin/user/ban?userId=\(id)")
    }

    public func unbanUser(id: Int) async throws {
        let _: String = try await apiClient.post("/admin/user/unban?userId=\(id)")
    }

    public func grantPoints(userID: Int, amount: Int, reason: String?) async throws -> AdminPointsGrantResponse {
        try await apiClient.post(
            "/admin/users/\(userID)/points",
            body: AdminPointsGrantRequest(amount: amount, reason: reason)
        )
    }

    public func ipBlacklist() async throws -> [AdminBlacklistIpItem] {
        try await apiClient.get("/admin/blacklist/ip")
    }

    public func addIpBlacklist(ip: String, reason: String) async throws {
        let _: String = try await apiClient.post(
            "/admin/blacklist/ip/add",
            body: AdminIpBlacklistAddRequest(ip: ip, reason: reason)
        )
    }

    public func removeIpBlacklist(ip: String) async throws {
        let _: String = try await apiClient.post(
            "/admin/blacklist/ip/remove",
            body: AdminIpBlacklistRemoveRequest(ip: ip)
        )
    }

    public func tempBlocks() async throws -> [AdminTempBlockItem] {
        try await apiClient.get("/admin/tempblock/list")
    }

    public func clearTempBlock(ip: String) async throws {
        let _: String = try await apiClient.post(
            "/admin/tempblock/clear",
            body: AdminIpBlacklistRemoveRequest(ip: ip)
        )
    }

    public func clearAllTempBlocks() async throws {
        let _: String = try await apiClient.post("/admin/tempblock/clear-all")
    }

    public func imageCount() async throws -> Int {
        if let value: Int = try? await apiClient.get("/status/image-count?t=\(Int(Date().timeIntervalSince1970))", signed: false) {
            return value
        }
        let response: AdminImageCountResponse = try await apiClient.get("/status/image-count?t=\(Int(Date().timeIntervalSince1970))", signed: false)
        return response.normalizedCount
    }

    public func syncImageCount() async throws {
        let _: String = try await apiClient.post("/admin/sync/image-count")
    }

    public func overview() async throws -> AdminOverviewSnapshot {
        async let blogStats = blogStats()
        async let users = users()
        async let blacklist = ipBlacklist()
        async let imageCount = imageCount()
        return try await AdminOverviewSnapshot(
            blogStats: blogStats,
            userCount: users.total,
            blockedIpCount: blacklist.count,
            imageCount: imageCount
        )
    }

    private func queryPath(_ path: String, items: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.path = path
        components.queryItems = items.filter { item in
            guard let value = item.value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return components.string ?? path
    }
}
