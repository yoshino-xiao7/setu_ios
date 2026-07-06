import Foundation

public struct PasskeyItem: Decodable, Identifiable, Sendable {
    public let id: Int
    public let nickname: String?
    public let transports: [String]?
    public let backupEligible: Bool?
    public let backupState: Bool?
    public let discoverable: Bool?
    public let lastUsedAt: String?
    public let createdAt: String?
    public let updatedAt: String?

    public var displayName: String {
        if let nickname, !nickname.isEmpty {
            return nickname
        }
        return "通行密钥 #\(id)"
    }
}

public struct PasskeyListResponse: Decodable, Sendable {
    public let list: [PasskeyItem]
}
