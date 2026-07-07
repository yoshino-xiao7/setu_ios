import Foundation

public enum UserRole: Int, Codable, Sendable {
    case user = 0
    case admin = 1
}

public struct CurrentUser: Codable, Identifiable, Sendable {
    public let id: Int
    public let email: String
    public let role: UserRole
    public let avatarUrl: String?
    public let nickname: String?
    public let lastLoginIp: String?

    public init(id: Int, email: String, role: UserRole, avatarUrl: String?, nickname: String?, lastLoginIp: String?) {
        self.id = id
        self.email = email
        self.role = role
        self.avatarUrl = avatarUrl
        self.nickname = nickname
        self.lastLoginIp = lastLoginIp
    }
}

public struct LoginRequest: Encodable, Sendable {
    public let email: String
    public let password: String
    public let captchaCode: String
    public let captchaUuid: String

    public init(email: String, password: String, captchaCode: String, captchaUuid: String) {
        self.email = email
        self.password = password
        self.captchaCode = captchaCode
        self.captchaUuid = captchaUuid
    }
}

public struct RegisterRequest: Encodable, Sendable {
    public let email: String
    public let password: String
    public let captchaCode: String
    public let captchaUuid: String

    public init(email: String, password: String, captchaCode: String, captchaUuid: String) {
        self.email = email
        self.password = password
        self.captchaCode = captchaCode
        self.captchaUuid = captchaUuid
    }
}

public struct ForgotPasswordRequest: Encodable, Sendable {
    public let email: String
    public let captchaCode: String
    public let captchaUuid: String

    public init(email: String, captchaCode: String, captchaUuid: String) {
        self.email = email
        self.captchaCode = captchaCode
        self.captchaUuid = captchaUuid
    }
}

public struct ResetPasswordRequest: Encodable, Sendable {
    public let token: String
    public let newPassword: String

    public init(token: String, newPassword: String) {
        self.token = token
        self.newPassword = newPassword
    }
}

public struct CaptchaResponse: Decodable, Sendable {
    public let uuid: String
    public let img: String
}

public struct LoginResponse: Decodable, Sendable {
    public let token: String?
    public let role: UserRole
    public let email: String?
    public let userId: Int?
    public let avatarUrl: String?
    public let signSecret: String
    public let expireAt: Int64?
    public let lastLoginIp: String?
}

public struct RefreshSignatureResponse: Decodable, Sendable {
    public let signSecret: String
    public let expireAt: Int64?
}

public struct APIEnvelope<Value: Decodable>: Decodable {
    public let code: Int?
    public let message: String?
    public let msg: String?
    public let data: Value?
}
