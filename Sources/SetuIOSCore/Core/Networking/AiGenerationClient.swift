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

    public func create(_ request: AiGenerationCreateRequest) async throws -> AiGenerationJob {
        try await apiClient.post("/ai/generations", body: request)
    }

    public func translatePrompt(_ request: AiPromptTranslateRequest) async throws -> AiPromptTranslateResponse {
        try await apiClient.post("/ai/prompt/translate", body: request)
    }

    public func promptTranslation(id: Int) async throws -> AiPromptTranslateResponse {
        try await apiClient.get("/ai/prompt/translations/\(id)")
    }

    public func capabilities() async throws -> AiCapabilityResponse {
        try await apiClient.get("/ai/capabilities")
    }

    public func serviceStatus() async throws -> AiServiceStatusResponse {
        try await apiClient.get("/ai/status")
    }

    public func square(category: String? = nil, page: Int = 1, pageSize: Int = 20) async throws -> PageResult<AiGenerationJob> {
        var path = "/ai/square?page=\(page)&pageSize=\(pageSize)"
        if let category, !category.isEmpty {
            path += "&category=\(category)"
        }
        return try await apiClient.get(path)
    }
}
