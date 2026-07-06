import Foundation

public struct AiGenerationClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func listMine(status: String? = nil, page: Int = 1, pageSize: Int = 20) async throws -> PageResult<AiGenerationJob> {
        var path = "/ai/generations?page=\(page)&pageSize=\(pageSize)"
        if let status, !status.isEmpty {
            path += "&status=\(status)"
        }
        return try await apiClient.get(path)
    }

    public func square(category: String? = nil, page: Int = 1, pageSize: Int = 20) async throws -> PageResult<AiGenerationJob> {
        var path = "/ai/square?page=\(page)&pageSize=\(pageSize)"
        if let category, !category.isEmpty {
            path += "&category=\(category)"
        }
        return try await apiClient.get(path)
    }
}
