import Foundation

public struct AdminBlogStats: Decodable, Sendable {
    public let id: Int?
    public let totalCalls: Int?
    public let updatedAt: String?
    public let aiGenerationTotal: Int?
    public let aiGenerationToday: Int?
}

public struct AdminUserListResponse: Decodable, Sendable {
    public let total: Int
    public let page: Int?
    public let pageSize: Int?
    public let list: [AdminUserItem]?
}

public struct AdminUserItem: Decodable, Identifiable, Sendable {
    public let id: Int
    public let email: String
    public let nickname: String?
    public let status: Int?
    public let role: Int?
    public let emailVerified: Bool?
    public let registerIp: String?
    public let lastLoginIp: String?
    public let createdAt: String?

    public var statusTitle: String {
        status == 0 ? "已封禁" : "正常"
    }

    public var roleTitle: String {
        role == 1 ? "管理员" : "用户"
    }
}

public struct AdminUserDetail: Decodable, Identifiable, Sendable {
    public let id: Int
    public let email: String
    public let nickname: String?
    public let status: Int?
    public let role: Int?
    public let emailVerified: Bool?
    public let registerIp: String?
    public let lastLoginIp: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let apiKeys: [AdminUserApiKey]?

    public var statusTitle: String {
        status == 0 ? "已封禁" : "正常"
    }

    public var roleTitle: String {
        role == 1 ? "管理员" : "用户"
    }
}

public struct AdminUserApiKey: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let status: Int?
    public let createdAt: String?
    public let lastUsedAt: String?
    public let totalCalls: Int?
    public let callsToday: Int?
    public let dailyQuota: Int?
    public let totalQuota: Int?

    public var statusTitle: String {
        status == 1 ? "启用" : "禁用"
    }
}

public struct AdminPointsGrantRequest: Encodable, Sendable {
    public let amount: Int
    public let reason: String?

    public init(amount: Int, reason: String?) {
        self.amount = amount
        self.reason = reason
    }
}

public struct AdminPointsGrantResponse: Decodable, Sendable {
    public let userId: Int
    public let grantedPoints: Int
    public let balance: Int
}

public struct AdminBlacklistIpItem: Decodable, Identifiable, Sendable {
    public let id: Int?
    public let ip: String
    public let reason: String?
    public let createdAt: String?

    public var stableID: String { "\(id ?? 0)-\(ip)" }
}

public struct AdminTempBlockItem: Decodable, Identifiable, Sendable {
    public let ip: String
    public let blockedAt: String?
    public let expiresAt: String?
    public let reason: String?

    public var id: String { ip }
}

public struct AdminIpBlacklistAddRequest: Encodable, Sendable {
    public let ip: String
    public let reason: String

    public init(ip: String, reason: String) {
        self.ip = ip
        self.reason = reason
    }
}

public struct AdminIpBlacklistRemoveRequest: Encodable, Sendable {
    public let ip: String

    public init(ip: String) {
        self.ip = ip
    }
}

public struct AdminImageCountResponse: Decodable, Sendable {
    public let count: Int?
    public let data: Int?

    public var normalizedCount: Int {
        count ?? data ?? 0
    }
}

public struct AdminOverviewSnapshot: Sendable {
    public let blogStats: AdminBlogStats
    public let userCount: Int
    public let blockedIpCount: Int
    public let imageCount: Int

    public init(blogStats: AdminBlogStats, userCount: Int, blockedIpCount: Int, imageCount: Int) {
        self.blogStats = blogStats
        self.userCount = userCount
        self.blockedIpCount = blockedIpCount
        self.imageCount = imageCount
    }
}

public struct AdminOperationLogItem: Decodable, Identifiable, Sendable {
    public let id: Int
    public let traceId: String?
    public let requestId: String?
    public let userId: Int?
    public let userEmail: String?
    public let eventType: String
    public let status: String
    public let code: String?
    public let message: String?
    public let targetType: String?
    public let targetId: String?
    public let method: String?
    public let path: String?
    public let ip: String?
    public let userAgent: String?
    public let createdAt: String
    public let durationMs: Int?

    public var statusTitle: String {
        switch status {
        case "SUCCESS": "成功"
        case "FAILED": "失败"
        case "PARTIAL": "部分成功"
        default: status
        }
    }
}

public struct AdminOperationLogDetail: Decodable, Identifiable, Sendable {
    public let id: Int
    public let traceId: String?
    public let requestId: String?
    public let userId: Int?
    public let userEmail: String?
    public let eventType: String
    public let status: String
    public let code: String?
    public let message: String?
    public let targetType: String?
    public let targetId: String?
    public let method: String?
    public let path: String?
    public let ip: String?
    public let userAgent: String?
    public let createdAt: String
    public let durationMs: Int?
    public let requestPayload: String?
    public let responsePayload: String?
    public let extraPayload: String?
    public let requestBody: String?
    public let responseBody: String?
    public let extra: String?

    public var statusTitle: String {
        switch status {
        case "SUCCESS": "成功"
        case "FAILED": "失败"
        case "PARTIAL": "部分成功"
        default: status
        }
    }

    public var displayRequestPayload: String? {
        requestPayload ?? requestBody
    }

    public var displayResponsePayload: String? {
        responsePayload ?? responseBody
    }

    public var displayExtraPayload: String? {
        extraPayload ?? extra
    }
}

public struct PixivCrawlerHealth: Decodable, Sendable {
    public let status: String?
    public let environment: String?
    public let database: String?

    public var isOnline: Bool {
        status?.lowercased() == "ok" || status?.lowercased() == "healthy" || status?.lowercased() == "online"
    }
}

public struct PixivCrawlByIdsRequest: Encodable, Sendable {
    public let illustIds: [Int]
    public let skipExisting: Bool

    public init(illustIds: [Int], skipExisting: Bool) {
        self.illustIds = illustIds
        self.skipExisting = skipExisting
    }
}

public struct PixivCrawlByTagRequest: Encodable, Sendable {
    public let tag: String
    public let mode: String
    public let pageFrom: Int
    public let pageTo: Int
    public let skipExisting: Bool

    public init(tag: String, mode: String, pageFrom: Int, pageTo: Int, skipExisting: Bool) {
        self.tag = tag
        self.mode = mode
        self.pageFrom = pageFrom
        self.pageTo = pageTo
        self.skipExisting = skipExisting
    }
}

public struct PixivCrawlerActionResponse: Decodable, Sendable {
    public let taskID: String?
    public let status: String?
    public let message: String?

    public init(taskID: String?, status: String?, message: String?) {
        self.taskID = taskID
        self.status = status
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case status
        case message
    }
}

public struct PixivCrawlerTaskList: Decodable, Sendable {
    public let total: Int
    public let tasks: [PixivCrawlerTask]

    public init(total: Int, tasks: [PixivCrawlerTask]) {
        self.total = total
        self.tasks = tasks
    }
}

public struct PixivCrawlerTask: Decodable, Identifiable, Sendable {
    public let taskID: String
    public let status: String
    public let mode: String
    public let message: String?
    public let progress: PixivCrawlerTaskProgress?
    public let logs: [String]?
    public let serverTimestamp: String?
    public let startedAt: String?
    public let finishedAt: String?

    public var id: String { taskID }

    public var statusTitle: String {
        switch status {
        case "pending": "等待中"
        case "running": "进行中"
        case "completed": "已完成"
        case "failed": "失败"
        case "cancelled": "已取消"
        default: status
        }
    }

    public var modeTitle: String {
        switch mode {
        case "by_ids": "按 ID"
        case "by_user": "按画师"
        case "by_tag": "按标签"
        default: mode
        }
    }

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case status
        case mode
        case message
        case progress
        case logs
        case serverTimestamp = "server_timestamp"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }
}

public struct PixivCrawlerTaskProgress: Decodable, Sendable {
    public let total: Int
    public let done: Int
    public let new: Int
    public let skipped: Int
    public let failed: Int

    public var percent: Int {
        guard total > 0 else { return 0 }
        return min(100, max(0, Int((Double(done) / Double(total)) * 100)))
    }
}
