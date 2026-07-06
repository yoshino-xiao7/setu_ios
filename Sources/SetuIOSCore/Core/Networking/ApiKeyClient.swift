import Foundation

public struct ApiKeyClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func list() async throws -> [ApiKeyItem] {
        try await apiClient.get("/api-key/list")
    }

    public func create(name: String, dailyQuota: Int = 1000, totalQuota: Int? = nil) async throws -> String {
        try await apiClient.post(
            "/api-key/create",
            body: ApiKeyCreateRequest(name: name, dailyQuota: dailyQuota, totalQuota: totalQuota)
        )
    }

    public func setEnabled(id: Int, enabled: Bool) async throws {
        let path = enabled ? "/api-key/\(id)/enable" : "/api-key/\(id)/disable"
        let _: String = try await apiClient.post(path)
    }

    public func rename(id: Int, name: String) async throws {
        let _: String = try await apiClient.post("/api-key/\(id)/rename", body: ApiKeyRenameRequest(name: name))
    }

    public func delete(id: Int) async throws {
        let _: String = try await apiClient.requestWithoutBody("/api-key/\(id)", method: "DELETE")
    }
}
