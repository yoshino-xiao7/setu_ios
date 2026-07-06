import Foundation

public struct StatusClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func overview() async throws -> StatusOverview {
        try await apiClient.get("/status/overview", signed: false)
    }

    public func health() async throws -> ServiceHealthData {
        try await apiClient.get("/status/health", signed: false)
    }
}
