import Foundation

public struct PasskeyClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func list() async throws -> [PasskeyItem] {
        let response: PasskeyListResponse = try await apiClient.get("/user/passkeys")
        return response.list
    }

    public func beginRegistration(nickname: String) async throws -> PasskeyOptionsResponse {
        try await apiClient.post(
            "/user/passkeys/registration/options",
            body: PasskeyRegistrationStartRequest(nickname: nickname)
        )
    }

    public func finishRegistration(challengeID: String, nickname: String, credential: PasskeyRegistrationCredential) async throws -> PasskeyItem {
        try await apiClient.post(
            "/user/passkeys/registration/finish",
            body: PasskeyRegistrationFinishRequest(challengeId: challengeID, nickname: nickname, credential: credential)
        )
    }

    public func beginAuthentication() async throws -> PasskeyOptionsResponse {
        try await apiClient.post("/auth/passkeys/authentication/options")
    }

    public func finishAuthentication(challengeID: String, credential: PasskeyAssertionCredential) async throws -> LoginResponse {
        try await apiClient.post(
            "/auth/passkeys/authentication/finish",
            body: PasskeyAuthenticationFinishRequest(challengeId: challengeID, credential: credential),
            signed: false
        )
    }

    public func rename(id: Int, nickname: String) async throws -> PasskeyItem {
        try await apiClient.patch("/user/passkeys/\(id)", body: PasskeyRenameRequest(nickname: nickname))
    }

    public func delete(id: Int) async throws {
        let _: String = try await apiClient.requestWithoutBody("/user/passkeys/\(id)", method: "DELETE")
    }
}

private struct PasskeyRenameRequest: Encodable, Sendable {
    let nickname: String
}
