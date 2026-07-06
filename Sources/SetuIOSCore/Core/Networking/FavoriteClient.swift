import Foundation

public struct FavoriteClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func list(page: Int = 1, size: Int = 24) async throws -> FavoritePage {
        try await apiClient.get("/favorite/list?page=\(page)&size=\(size)")
    }

    public func add(pid: Int, p: Int = 0) async throws {
        let _: String = try await apiClient.post("/favorite/\(pid)/\(p)")
    }

    public func remove(pid: Int, p: Int = 0) async throws {
        let _: String = try await apiClient.requestWithoutBody("/favorite/\(pid)/\(p)", method: "DELETE")
    }
}
