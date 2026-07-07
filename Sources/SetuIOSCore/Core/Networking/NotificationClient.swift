import Foundation

public struct NotificationClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func list(page: Int = 1, pageSize: Int = 20, unreadOnly: Bool = false) async throws -> UserNotificationPage {
        try await apiClient.get("/notifications?page=\(page)&pageSize=\(pageSize)&unreadOnly=\(unreadOnly)")
    }

    public func unreadCount() async throws -> Int {
        let count: UnreadNotificationCount = try await apiClient.get("/notifications/unread-count")
        return count.count
    }

    public func markRead(id: Int) async throws {
        let _: String = try await apiClient.post("/notifications/\(id)/read")
    }

    public func markAllRead() async throws {
        let _: String = try await apiClient.post("/notifications/read-all")
    }
}
