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
