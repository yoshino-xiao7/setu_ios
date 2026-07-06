import Foundation

public struct UserNotification: Decodable, Identifiable, Sendable {
    public let id: Int
    public let type: String
    public let title: String
    public let content: String
    public let targetType: String?
    public let targetId: String?
    public let read: Bool
    public let readAt: String?
    public let createdAt: String
}

public struct UserNotificationPage: Decodable, Sendable {
    public let total: Int
    public let page: Int
    public let pageSize: Int
    public let list: [UserNotification]
}
