import Foundation

public struct ApiKeyItem: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let status: Int
    public let dailyQuota: Int
    public let totalQuota: Int?
    public let callsToday: Int
    public let totalCalls: Int
    public let createdAt: String

    public var isEnabled: Bool {
        status == 1
    }
}

public struct ApiKeyCreateRequest: Encodable, Sendable {
    public let name: String
    public let dailyQuota: Int
    public let totalQuota: Int?

    public init(name: String, dailyQuota: Int, totalQuota: Int?) {
        self.name = name
        self.dailyQuota = dailyQuota
        self.totalQuota = totalQuota
    }
}

public struct ApiKeyRenameRequest: Encodable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}
