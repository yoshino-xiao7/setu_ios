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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        targetType = try container.decodeIfPresent(String.self, forKey: .targetType)
        if let stringValue = try? container.decodeIfPresent(String.self, forKey: .targetId) {
            targetId = stringValue
        } else if let intValue = try? container.decodeIfPresent(Int.self, forKey: .targetId) {
            targetId = String(intValue)
        } else {
            targetId = nil
        }
        read = try container.decode(Bool.self, forKey: .read)
        readAt = try container.decodeIfPresent(String.self, forKey: .readAt)
        createdAt = try container.decode(String.self, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case content
        case targetType
        case targetId
        case read
        case readAt
        case createdAt
    }
}

public struct UserNotificationPage: Decodable, Sendable {
    public let total: Int
    public let page: Int
    public let pageSize: Int
    public let list: [UserNotification]
}
