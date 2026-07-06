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

public struct AvatarUploadResponse: Decodable, Sendable {
    public let avatarUrl: String
}

public struct QqBinding: Decodable, Sendable {
    public let qqNumber: String?
    public let enabled: Bool?
    public let updatedAt: String?

    public var isEnabled: Bool {
        enabled == true
    }
}

public struct QqBindingVerificationRequest: Encodable, Sendable {
    public let qqNumber: String

    public init(qqNumber: String) {
        self.qqNumber = qqNumber
    }
}

public struct QqBindingVerificationResponse: Decodable, Sendable {
    public let qqEmail: String?
    public let expiresInSeconds: Int?
}

public struct SaveQqBindingRequest: Encodable, Sendable {
    public let qqNumber: String
    public let verificationCode: String

    public init(qqNumber: String, verificationCode: String) {
        self.qqNumber = qqNumber
        self.verificationCode = verificationCode
    }
}

public struct ChangePasswordRequest: Encodable, Sendable {
    public let oldPassword: String
    public let newPassword: String

    public init(oldPassword: String, newPassword: String) {
        self.oldPassword = oldPassword
        self.newPassword = newPassword
    }
}
