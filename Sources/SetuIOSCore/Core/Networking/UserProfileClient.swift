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

    public func uploadAvatarFile(data: Data, fileName: String, mimeType: String) async throws -> AvatarUploadResponse {
        try await apiClient.postMultipart(
            "/user/profile/avatar-file",
            fileFieldName: "file",
            fileName: fileName,
            mimeType: mimeType,
            fileData: data
        )
    }

    public func getQqBinding() async throws -> QqBinding {
        try await apiClient.get("/user/qq-binding")
    }

    public func sendQqBindingVerificationCode(qqNumber: String) async throws -> QqBindingVerificationResponse {
        try await apiClient.post(
            "/user/qq-binding/verification-code",
            body: QqBindingVerificationRequest(qqNumber: qqNumber)
        )
    }

    public func saveQqBinding(qqNumber: String, verificationCode: String) async throws -> QqBinding {
        try await apiClient.post(
            "/user/qq-binding",
            body: SaveQqBindingRequest(qqNumber: qqNumber, verificationCode: verificationCode)
        )
    }

    public func disableQqBinding() async throws -> QqBinding {
        try await apiClient.requestWithoutBody("/user/qq-binding", method: "DELETE")
    }

    public func changePassword(oldPassword: String, newPassword: String) async throws {
        let _: EmptyResponse = try await apiClient.post(
            "/auth/change-password",
            body: ChangePasswordRequest(oldPassword: oldPassword, newPassword: newPassword)
        )
    }
}
