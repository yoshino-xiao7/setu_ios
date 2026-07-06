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
