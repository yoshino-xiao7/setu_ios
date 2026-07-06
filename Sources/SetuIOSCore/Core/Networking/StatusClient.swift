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

    public func imageCount(cacheBust: Bool = true) async throws -> Int {
        let path = cacheBust ? "/status/image-count?t=\(Int(Date().timeIntervalSince1970))" : "/status/image-count"
        if let value: Int = try? await apiClient.get(path, signed: false) {
            return value
        }
        let response: ImageCountResponse = try await apiClient.get(path, signed: false)
        return response.normalizedCount
    }
}
