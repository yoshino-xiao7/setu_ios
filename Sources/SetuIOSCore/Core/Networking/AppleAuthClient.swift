import Foundation

public struct AppleAuthClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func login(identityToken: String, nonce: String) async throws -> LoginResponse {
        try await apiClient.post(
            "/auth/apple/login",
            body: AppleAuthorizationPayload(identityToken: identityToken, nonce: nonce),
            signed: false
        )
    }

    public func binding() async throws -> AppleBindingStatus {
        try await apiClient.get("/user/apple")
    }

    public func bind(identityToken: String, nonce: String) async throws -> AppleBindingStatus {
        try await apiClient.post(
            "/user/apple/bind",
            body: AppleAuthorizationPayload(identityToken: identityToken, nonce: nonce)
        )
    }

    public func unbind() async throws -> AppleBindingStatus {
        try await apiClient.requestWithoutBody("/user/apple", method: "DELETE")
    }
}
