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

    public func deleteUser(id: Int) async throws {
        let _: String = try await apiClient.requestWithoutBody("/admin/user/\(id)", method: "DELETE")
    }

    public func imageInfo(pid: Int, p: Int = 0) async throws -> AdminImageDetail {
        try await apiClient.get(queryPath(
            "/admin/image/info",
            items: [
                URLQueryItem(name: "pid", value: "\(pid)"),
                URLQueryItem(name: "p", value: "\(p)")
            ]
        ))
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

    public func neteaseTokens() async throws -> [NeteaseToken] {
        try await apiClient.get("/admin/netease/tokens")
    }

    public func addNeteaseToken(cookie: String, nickname: String) async throws -> Int {
        try await apiClient.post(
            "/admin/netease/tokens",
            body: NeteaseTokenCreateRequest(cookie: cookie, nickname: nickname)
        )
    }

    public func updateNeteaseToken(id: Int, cookie: String? = nil, nickname: String? = nil, status: Int? = nil) async throws {
        let _: String = try await apiClient.put(
            "/admin/netease/tokens/\(id)",
            body: NeteaseTokenUpdateRequest(cookie: cookie, nickname: nickname, status: status)
        )
    }

    public func deleteNeteaseToken(id: Int) async throws {
        let _: String = try await apiClient.requestWithoutBody("/admin/netease/tokens/\(id)", method: "DELETE")
    }

    public func checkNeteaseToken(id: Int, probeSongID: String = "32358362", level: String = "exhigh") async throws -> NeteaseTokenCheckResult {
        try await apiClient.get(queryPath(
            "/admin/netease/tokens/\(id)/check",
            items: [
                URLQueryItem(name: "probeSongId", value: probeSongID),
                URLQueryItem(name: "level", value: level)
            ]
        ))
    }

    public func operationLogs(
        page: Int = 1,
        pageSize: Int = 20,
        traceId: String? = nil,
        userEmail: String? = nil,
        eventType: String? = nil,
        status: String? = nil,
        code: String? = nil,
        targetType: String? = nil,
        targetId: String? = nil
    ) async throws -> PageResult<AdminOperationLogItem> {
        try await apiClient.get(queryPath(
            "/admin/operation-logs",
            items: [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "pageSize", value: "\(pageSize)"),
                URLQueryItem(name: "traceId", value: traceId),
                URLQueryItem(name: "userEmail", value: userEmail),
                URLQueryItem(name: "eventType", value: eventType),
                URLQueryItem(name: "status", value: status),
                URLQueryItem(name: "code", value: code),
                URLQueryItem(name: "targetType", value: targetType),
                URLQueryItem(name: "targetId", value: targetId)
            ]
        ))
    }

    public func operationLogDetail(id: Int) async throws -> AdminOperationLogDetail {
        try await apiClient.get("/admin/operation-logs/\(id)")
    }

    public func imageAuditList(
        page: Int = 1,
        pageSize: Int = 20,
        scope: String? = nil,
        pid: Int? = nil,
        p: Int? = nil,
        staleDays: Int? = nil,
        availabilityStatus: String? = nil,
        onlyBroken: Bool? = nil
    ) async throws -> ImageAuditPageResult {
        try await apiClient.get(queryPath(
            "/admin/image-audit/list",
            items: [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "pageSize", value: "\(pageSize)"),
                URLQueryItem(name: "scope", value: scope),
                URLQueryItem(name: "pid", value: pid.map(String.init)),
                URLQueryItem(name: "p", value: p.map(String.init)),
                URLQueryItem(name: "staleDays", value: staleDays.map(String.init)),
                URLQueryItem(name: "availabilityStatus", value: availabilityStatus),
                URLQueryItem(name: "onlyBroken", value: onlyBroken.map { $0 ? "true" : "false" })
            ]
        ))
    }

    public func submitImageAudit(imageID: Int, status: Int, remark: String? = nil) async throws {
        let _: String = try await apiClient.post(
            "/admin/image-audit/submit",
            body: ImageAuditSubmitRequest(imageId: imageID, status: status, remark: remark)
        )
    }

    public func submitImageAuditBatch(imageIDs: [Int], status: Int, remark: String? = nil) async throws -> ImageAuditBatchSubmitResponse {
        try await apiClient.post(
            "/admin/image-audit/batch-submit",
            body: ImageAuditBatchSubmitRequest(imageIds: imageIDs, status: status, remark: remark)
        )
    }

    public func checkImageAvailability(imageIDs: [Int]) async throws -> ImageAvailabilityCheckResponse {
        try await apiClient.post(
            "/admin/image-audit/availability-check",
            body: ImageAvailabilityCheckRequest(imageIds: imageIDs)
        )
    }

    public func pixivHealth() async throws -> PixivCrawlerHealth {
        try await apiClient.get("/admin/pixiv/health")
    }

    public func crawlPixivByIDs(_ ids: [Int], skipExisting: Bool = true) async throws -> PixivCrawlerActionResponse {
        try await apiClient.post(
            "/admin/pixiv/crawl/illust",
            body: PixivCrawlByIdsRequest(illustIds: ids, skipExisting: skipExisting)
        )
    }

    public func crawlPixivByUser(userID: String, skipExisting: Bool = true) async throws -> PixivCrawlerActionResponse {
        try await apiClient.post("/admin/pixiv/crawl/user/\(userID)?skipExisting=\(skipExisting)")
    }

    public func crawlPixivByTag(tag: String, mode: String, pageFrom: Int, pageTo: Int, skipExisting: Bool = true) async throws -> PixivCrawlerActionResponse {
        try await apiClient.post(
            "/admin/pixiv/crawl/tag",
            body: PixivCrawlByTagRequest(tag: tag, mode: mode, pageFrom: pageFrom, pageTo: pageTo, skipExisting: skipExisting)
        )
    }

    public func pixivTasks(limit: Int = 100, offset: Int = 0) async throws -> PixivCrawlerTaskList {
        try await apiClient.get("/admin/pixiv/tasks?limit=\(limit)&offset=\(offset)")
    }

    public func pixivTask(taskID: String) async throws -> PixivCrawlerTask {
        try await apiClient.get("/admin/pixiv/tasks/\(taskID)")
    }

    public func cancelPixivTask(taskID: String) async throws -> PixivCrawlerActionResponse {
        try await apiClient.requestWithoutBody("/admin/pixiv/tasks/\(taskID)", method: "DELETE")
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
