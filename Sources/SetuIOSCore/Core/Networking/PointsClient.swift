import Foundation

public struct PointsClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func balance() async throws -> PointsBalance {
        try await apiClient.get("/points/me")
    }

    public func logs(page: Int = 1, size: Int = 20) async throws -> PointsLogPage {
        try await apiClient.get("/points/logs?page=\(page)&size=\(size)")
    }
}
