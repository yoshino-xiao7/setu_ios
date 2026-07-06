import Foundation

public struct UserProfileClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func getUserInfo() async throws -> UserProfile {
        try await apiClient.get("/user/info")
    }

    public func updateNickname(_ nickname: String) async throws {
        let _: String = try await apiClient.post("/user/profile/nickname", body: UpdateNicknameRequest(nickname: nickname))
    }
}
