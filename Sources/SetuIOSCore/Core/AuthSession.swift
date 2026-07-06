import Foundation

@MainActor
@Observable
public final class AuthSession {
    private let apiClient: APIClient
    private let keychain: KeychainStoring
    private let expireAtKey = "authExpireAt"

    public var currentUser: CurrentUser?
    public var expireAt: Date?
    public var isRefreshing = false
    public var lastError: String?

    public init(apiClient: APIClient, keychain: KeychainStoring) {
        self.apiClient = apiClient
        self.keychain = keychain
    }

    public var isSignedIn: Bool {
        currentUser != nil
    }

    public func login(email: String, password: String, captchaCode: String, captchaUuid: String) async {
        lastError = nil
        do {
            let response: LoginResponse = try await apiClient.post(
                "/auth/login",
                body: LoginRequest(email: email, password: password, captchaCode: captchaCode, captchaUuid: captchaUuid),
                signed: false
            )
            try applyLoginResponse(response, fallbackEmail: email)
        } catch {
            lastError = error.localizedDescription
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
        lastError = nil
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
        try? apiClient.signer.clearSignSecret()
        try? keychain.remove(expireAtKey)
        currentUser = nil
        expireAt = nil
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
}
