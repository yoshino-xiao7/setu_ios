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
            lastError = error.localizedDescription
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
            lastError = error.localizedDescription
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
            lastError = error.localizedDescription
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
            lastError = error.localizedDescription
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
            currentUser = CurrentUser(
                id: profile.id,
                email: profile.email,
                role: profile.role,
                avatarUrl: profile.avatarUrl,
                nickname: profile.nickname,
                lastLoginIp: profile.lastLoginIp
            )
            try persistCurrentUser()
            lastError = nil
            return true
        } catch {
            clearLocalSession()
            lastError = "登录会话确认失败，请重新登录"
            return false
        }
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
            lastError = error.localizedDescription
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
