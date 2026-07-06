import Foundation

public struct UsageOverview: Decodable, Sendable {
    public let totalCalls: Int
    public let todayCalls: Int
    public let lastCalledAt: String?
}

public struct UsageLogItem: Decodable, Identifiable, Sendable {
    public let id: Int
    public let timestamp: String
    public let endpoint: String
    public let status: Int
    public let ip: String
}

public struct UsageLogPage: Decodable, Sendable {
    public let total: Int
    public let list: [UsageLogItem]

    public init(from decoder: Decoder) throws {
        if let array = try? [UsageLogItem](from: decoder) {
            total = array.count
            list = array
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let data = try container.decodeIfPresent([UsageLogItem].self, forKey: .data) {
            list = data
            total = try container.decodeIfPresent(Int.self, forKey: .total)
                ?? container.decodeIfPresent(Int.self, forKey: .count)
                ?? data.count
            return
        }
        if let items = try container.decodeIfPresent([UsageLogItem].self, forKey: .items) {
            list = items
            total = try container.decodeIfPresent(Int.self, forKey: .total)
                ?? container.decodeIfPresent(Int.self, forKey: .count)
                ?? items.count
            return
        }
        let values = try container.decodeIfPresent([UsageLogItem].self, forKey: .list) ?? []
        list = values
        total = try container.decodeIfPresent(Int.self, forKey: .total)
            ?? container.decodeIfPresent(Int.self, forKey: .count)
            ?? values.count
    }

    private enum CodingKeys: String, CodingKey {
        case count
        case data
        case items
        case list
        case total
    }
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

public struct ImageCountResponse: Decodable, Sendable {
    public let count: Int?
    public let data: Int?

    public var normalizedCount: Int {
        count ?? data ?? 0
    }
}

public struct UnreadNotificationCount: Decodable, Sendable {
    public let count: Int
}

public struct HomeDashboardSnapshot: Sendable {
    public let usage: UsageOverview?
    public let usageLogs: UsageLogPage?
    public let points: PointsBalance?
    public let status: StatusOverview?
    public let unreadNotifications: Int?

    public init(
        usage: UsageOverview?,
        usageLogs: UsageLogPage?,
        points: PointsBalance?,
        status: StatusOverview?,
        unreadNotifications: Int?
    ) {
        self.usage = usage
        self.usageLogs = usageLogs
        self.points = points
        self.status = status
        self.unreadNotifications = unreadNotifications
    }
}
