import Foundation

public struct UsageOverview: Decodable, Sendable {
    public let totalCalls: Int
    public let todayCalls: Int
    public let lastCalledAt: String?
}

public struct PointsBalance: Decodable, Sendable {
    public let points: Int
}

public struct StatusData: Decodable, Sendable {
    public let status: String
    public let availability: Double?
    public let avgLatencyMs: Double?
    public let callsToday: Int
}

public struct ServiceHealthData: Decodable, Sendable {
    public let status: String
    public let healthy: Bool
    public let code: String
    public let checkedAt: String
}

public struct StatusOverview: Decodable, Sendable {
    public let status: StatusData
    public let health: ServiceHealthData?
}

public struct UnreadNotificationCount: Decodable, Sendable {
    public let count: Int
}

public struct HomeDashboardSnapshot: Sendable {
    public let usage: UsageOverview?
    public let points: PointsBalance?
    public let status: StatusOverview?
    public let unreadNotifications: Int?

    public init(
        usage: UsageOverview?,
        points: PointsBalance?,
        status: StatusOverview?,
        unreadNotifications: Int?
    ) {
        self.usage = usage
        self.points = points
        self.status = status
        self.unreadNotifications = unreadNotifications
    }
}
