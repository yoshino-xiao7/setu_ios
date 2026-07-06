import Foundation

public struct PointsLogItem: Decodable, Identifiable, Sendable {
    public let id: Int
    public let delta: Int
    public let bizType: String
    public let endpoint: String?
    public let createdAt: String?
}

public struct PointsLogPage: Decodable, Sendable {
    public let page: Int
    public let size: Int
    public let total: Int
    public let items: [PointsLogItem]
}
