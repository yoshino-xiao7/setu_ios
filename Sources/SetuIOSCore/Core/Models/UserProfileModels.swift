import Foundation

public struct UserProfile: Decodable, Identifiable, Sendable {
    public let id: Int
    public let email: String
    public let nickname: String?
    public let avatarUrl: String?
    public let role: UserRole
    public let createdAt: String
    public let lastLoginIp: String?

    public var displayName: String {
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed! : email
    }
}

public struct UpdateNicknameRequest: Encodable, Sendable {
    public let nickname: String

    public init(nickname: String) {
        self.nickname = nickname
    }
}
