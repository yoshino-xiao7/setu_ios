import Foundation

@MainActor
@Observable
public final class AuthSession {
    private let apiClient: APIClient
    private let keychain: KeychainStoring
    private let expireAtKey = "authExpireAt"
    private let currentUserKey = "currentUser"

    public var currentUser: CurrentUser?
    public var expireAt: Date?
    public var isRefreshing = false
    public var lastError: String?

    public init(apiClient: APIClient, keychain: KeychainStoring) {
        self.apiClient = apiClient
        self.keychain = keychain
        restoreLocalSession()
    }

    public var isSignedIn: Bool {
        currentUser != nil
    }

    public func fetchCaptcha() async throws -> CaptchaResponse {
        try await apiClient.get("/auth/captcha", signed: false)
    }

    public func mobileSessionDiagnostics() -> MobileSessionDiagnostics {
        apiClient.mobileSessionDiagnostics(
            hasSignSecret: apiClient.signer.hasSignSecret(),
            expireAt: expireAt,
            isSignedIn: isSignedIn
        )
    }

    public func login(email: String, password: String, captchaCode: String, captchaUuid: String) async {
        lastError = nil
        do {
            let response: LoginResponse = try await apiClient.post(
                "/auth/login",
                body: LoginRequest(email: email, password: password, captchaCode: captchaCode, captchaUuid: captchaUuid),
                signed: false
            )
            try await acceptLoginResponse(response, fallbackEmail: email)
        } catch {
            lastError = Self.userFacingMessage(for: error)
        }
    }

    public func register(email: String, password: String, captchaCode: String, captchaUuid: String) async -> Bool {
        lastError = nil
        do {
            let _: EmptyResponse = try await apiClient.post(
                "/auth/register",
                body: RegisterRequest(email: email, password: password, captchaCode: captchaCode, captchaUuid: captchaUuid),
                signed: false
            )
            return true
        } catch {
            lastError = Self.userFacingMessage(for: error)
            return false
        }
    }

    public func forgotPassword(email: String, captchaCode: String, captchaUuid: String) async -> Bool {
        lastError = nil
        do {
            let _: EmptyResponse = try await apiClient.post(
                "/auth/forgot-password",
                body: ForgotPasswordRequest(email: email, captchaCode: captchaCode, captchaUuid: captchaUuid),
                signed: false
            )
            return true
        } catch {
            lastError = Self.userFacingMessage(for: error)
            return false
        }
    }

    public func resetPassword(token: String, newPassword: String) async -> Bool {
        lastError = nil
        do {
            let _: EmptyResponse = try await apiClient.post(
                "/auth/reset-password",
                body: ResetPasswordRequest(token: token, newPassword: newPassword),
                signed: false
            )
            return true
        } catch {
            lastError = Self.userFacingMessage(for: error)
            return false
        }
    }

    public func applyLoginResponse(_ response: LoginResponse, fallbackEmail: String? = nil) throws {
        try apiClient.signer.persistSignSecret(response.signSecret)
        persistExpireAt(response.expireAt)
        currentUser = CurrentUser(
            id: response.userId ?? 0,
            email: response.email ?? fallbackEmail ?? "passkey-user",
            role: response.role,
            avatarUrl: response.avatarUrl,
            nickname: nil,
            lastLoginIp: response.lastLoginIp
        )
        try persistCurrentUser()
        lastError = nil
    }

    public func acceptLoginResponse(_ response: LoginResponse, fallbackEmail: String? = nil) async throws {
        try applyLoginResponse(response, fallbackEmail: fallbackEmail)
        guard await confirmAuthenticatedSession() else {
            throw AuthSessionError.sessionConfirmationFailed
        }
    }

    @discardableResult
    public func confirmAuthenticatedSession() async -> Bool {
        do {
            let profile: UserProfile = try await apiClient.get("/user/info")
            try applyUserProfile(profile)
            lastError = nil
            return true
        } catch {
            clearLocalSession()
            lastError = "登录会话确认失败，请重新登录"
            return false
        }
    }

    public func applyUserProfile(_ profile: UserProfile) throws {
        currentUser = CurrentUser(
            id: profile.id,
            email: profile.email,
            role: profile.role,
            avatarUrl: profile.avatarUrl,
            nickname: profile.nickname,
            lastLoginIp: profile.lastLoginIp
        )
        try persistCurrentUser()
    }

    public func refreshSignature() async -> Bool {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let response: RefreshSignatureResponse = try await apiClient.post("/auth/refresh-signature", signed: false)
            try apiClient.signer.persistSignSecret(response.signSecret)
            persistExpireAt(response.expireAt)
            return true
        } catch {
            lastError = Self.userFacingMessage(for: error)
            return false
        }
    }

    public func logout() async {
        _ = try? await apiClient.post("/auth/logout", signed: true) as EmptyResponse
        clearLocalSession()
    }

    public func invalidateLocalSession(message: String = "登录已过期，请重新登录") {
        clearLocalSession()
        lastError = message
    }

    public func resetLocalSession() {
        clearLocalSession()
        lastError = nil
    }

    private func persistExpireAt(_ value: Int64?) {
        guard let value else {
            expireAt = nil
            try? keychain.remove(expireAtKey)
            return
        }
        let milliseconds = value < 1_000_000_000_000 ? value * 1000 : value
        expireAt = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
        try? keychain.setString(String(milliseconds), for: expireAtKey)
    }

    private func persistCurrentUser() throws {
        guard let currentUser else {
            try keychain.remove(currentUserKey)
            return
        }
        let data = try JSONEncoder().encode(currentUser)
        let value = data.base64EncodedString()
        try keychain.setString(value, for: currentUserKey)
    }

    private func restoreLocalSession() {
        guard
            let expireAtValue = try? keychain.string(for: expireAtKey),
            let milliseconds = Int64(expireAtValue)
        else {
            clearLocalSession()
            return
        }

        let restoredExpireAt = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
        guard restoredExpireAt > Date() else {
            clearLocalSession()
            return
        }

        guard
            let encodedUser = try? keychain.string(for: currentUserKey),
            let data = Data(base64Encoded: encodedUser),
            let user = try? JSONDecoder().decode(CurrentUser.self, from: data)
        else {
            clearLocalSession()
            return
        }

        expireAt = restoredExpireAt
        currentUser = user
    }

    private func clearLocalSession() {
        try? apiClient.signer.clearSignSecret()
        apiClient.clearSessionCookies()
        try? keychain.remove(expireAtKey)
        try? keychain.remove(currentUserKey)
        currentUser = nil
        expireAt = nil
    }

    private static func userFacingMessage(for error: Error) -> String {
        if error is AuthSessionError {
            return "登录会话确认失败，请重新登录"
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "网络似乎断开了，请检查连接后重试"
            case .timedOut:
                return "连接超时，请稍后重试"
            default:
                return "暂时无法连接服务，请稍后重试"
            }
        }

        guard let apiError = error as? APIError else {
            return "操作没有完成，请稍后重试"
        }

        switch apiError {
        case .invalidURL, .invalidResponse:
            return "服务响应异常，请稍后重试"
        case .httpStatus(let status, let message, _, _):
            let safeMessage = sanitizedServerMessage(message)
            switch status {
            case 400:
                return safeMessage ?? "请检查填写内容后重试"
            case 401:
                return "邮箱、密码或验证码不正确，请重新输入"
            case 403:
                return "当前账号无法执行此操作"
            case 404:
                return "请求的内容不存在或已被移除"
            case 409:
                return safeMessage ?? "当前状态已发生变化，请刷新后继续"
            case 429:
                return "操作有点频繁，请稍后再试"
            case 500...599:
                return "服务暂时开小差，请稍后重试"
            default:
                return safeMessage ?? "操作没有完成，请稍后重试"
            }
        }
    }

    private static func sanitizedServerMessage(_ message: String?) -> String? {
        guard let message = message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return nil
        }
        let normalized = message.lowercased()
        let technicalMarkers = ["request id", "trace id", "http ", "exception", "stack trace", "/auth/"]
        guard !technicalMarkers.contains(where: normalized.contains) else { return nil }
        return message
    }
}

public enum AuthSessionError: Error, LocalizedError {
    case sessionConfirmationFailed

    public var errorDescription: String? {
        switch self {
        case .sessionConfirmationFailed:
            "登录会话确认失败，请重新登录"
        }
    }
}
