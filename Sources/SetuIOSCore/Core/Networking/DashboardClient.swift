import Foundation

public struct DashboardClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func fetchUsageOverview() async throws -> UsageOverview {
        try await apiClient.get("/usage/overview")
    }

    public func fetchPointsBalance() async throws -> PointsBalance {
        try await apiClient.get("/points/me")
    }

    public func fetchStatusOverview() async throws -> StatusOverview {
        try await apiClient.get("/status/overview", signed: false)
    }

    public func fetchUnreadNotificationCount() async throws -> Int {
        let count: UnreadNotificationCount = try await apiClient.get("/notifications/unread-count")
        return count.count
    }

    public func fetchHomeSnapshot() async -> HomeDashboardSnapshot {
        async let usage = optional { try await fetchUsageOverview() }
        async let points = optional { try await fetchPointsBalance() }
        async let status = optional { try await fetchStatusOverview() }
        async let unread = optional { try await fetchUnreadNotificationCount() }

        return await HomeDashboardSnapshot(
            usage: usage,
            points: points,
            status: status,
            unreadNotifications: unread
        )
    }

    private func optional<Value: Sendable>(_ operation: @Sendable () async throws -> Value) async -> Value? {
        do {
            return try await operation()
        } catch {
            return nil
        }
    }
}
