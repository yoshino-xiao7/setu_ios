import Foundation

public struct AdminClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func blogStats() async throws -> AdminBlogStats {
        try await apiClient.get("/admin/blog/stats")
    }

    public func users(page: Int = 1, pageSize: Int = 1) async throws -> AdminUserListResponse {
        try await apiClient.get("/admin/users?page=\(page)&pageSize=\(pageSize)")
    }

    public func ipBlacklist() async throws -> [AdminBlacklistIpItem] {
        try await apiClient.get("/admin/blacklist/ip")
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
}
