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

    public func get(id: Int) async throws -> AiGenerationJob {
        try await apiClient.get("/ai/generations/\(id)")
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

    public func adminControlStatus() async throws -> AiControlStatus {
        try await apiClient.get("/admin/ai/control/status")
    }

    public func startAdminStack() async throws -> AiControlStatus {
        try await apiClient.post("/admin/ai/control/start")
    }

    public func stopAdminStack() async throws -> AiControlStatus {
        try await apiClient.post("/admin/ai/control/stop")
    }

    public func restartAdminStack() async throws -> AiControlStatus {
        try await apiClient.post("/admin/ai/control/restart")
    }

    public func imageURL(id: Int) async throws -> AiImageURL {
        try await apiClient.get("/ai/generations/\(id)/image-url")
    }

    public func download(id: Int) async throws -> AiImageDownload {
        try await apiClient.post("/ai/generations/\(id)/download")
    }

    public func submitReview(id: Int, category: String, note: String? = nil) async throws -> AiGenerationReview {
        try await apiClient.post(
            "/ai/generations/\(id)/review",
            body: AiReviewSubmitRequest(category: category, note: note)
        )
    }

    public func submitDeleteRequest(id: Int, reason: String? = nil) async throws -> AiGenerationDeleteRequest {
        try await apiClient.post(
            "/ai/generations/\(id)/delete-request",
            body: AiDeleteRequestSubmitRequest(reason: reason)
        )
    }

    public func deleteRequests(status: String? = nil, page: Int = 1, pageSize: Int = 20) async throws -> PageResult<AiGenerationDeleteRequest> {
        var path = "/ai/delete-requests?page=\(page)&pageSize=\(pageSize)"
        if let status, !status.isEmpty, status != "ALL" {
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

    public func adminGenerations(
        jobId: Int? = nil,
        userId: Int? = nil,
        status: String? = nil,
        reviewStatus: String? = nil,
        deleteStatus: String? = nil,
        recordState: String? = nil,
        page: Int = 1,
        pageSize: Int = 20
    ) async throws -> PageResult<AiGenerationJob> {
        var path = "/admin/ai/generations?page=\(page)&pageSize=\(pageSize)"
        if let jobId {
            path += "&jobId=\(jobId)"
        }
        if let userId {
            path += "&userId=\(userId)"
        }
        if let status, !status.isEmpty, status != "ALL" {
            path += "&status=\(status)"
        }
        if let reviewStatus, !reviewStatus.isEmpty, reviewStatus != "ALL" {
            path += "&reviewStatus=\(reviewStatus)"
        }
        if let deleteStatus, !deleteStatus.isEmpty, deleteStatus != "ALL" {
            path += "&deleteStatus=\(deleteStatus)"
        }
        if let recordState, !recordState.isEmpty, recordState != "ALL" {
            path += "&recordState=\(recordState)"
        }
        return try await apiClient.get(path)
    }

    public func unpublishAdminGeneration(id: Int) async throws -> AiGenerationJob {
        try await apiClient.post("/admin/ai/generations/\(id)/unpublish")
    }

    public func deleteAdminGeneration(id: Int, reason: String? = nil) async throws -> AiGenerationJob {
        try await apiClient.post(
            "/admin/ai/generations/\(id)/delete",
            body: AiGenerationDeleteCommandRequest(reason: reason)
        )
    }

    public func deleteAdminLocalImage(id: Int, reason: String? = nil) async throws -> AiLocalImageDeleteCommand {
        try await apiClient.post(
            "/admin/ai/generations/\(id)/local-image/delete",
            body: AiGenerationDeleteCommandRequest(reason: reason)
        )
    }

    public func adminReviews(status: String? = nil, category: String? = nil, page: Int = 1, pageSize: Int = 20) async throws -> PageResult<AiGenerationReview> {
        var path = "/admin/ai/reviews?page=\(page)&pageSize=\(pageSize)"
        if let status, !status.isEmpty, status != "ALL" {
            path += "&status=\(status)"
        }
        if let category, !category.isEmpty, category != "ALL" {
            path += "&category=\(category)"
        }
        return try await apiClient.get(path)
    }

    public func approveAdminReview(id: Int) async throws -> AiGenerationReview {
        try await apiClient.post("/admin/ai/reviews/\(id)/approve")
    }

    public func rejectAdminReview(id: Int, reason: String) async throws -> AiGenerationReview {
        try await apiClient.post("/admin/ai/reviews/\(id)/reject", body: AiReviewRejectRequest(reason: reason))
    }

    public func adminDeleteRequests(status: String? = nil, page: Int = 1, pageSize: Int = 20) async throws -> PageResult<AiGenerationDeleteRequest> {
        var path = "/admin/ai/delete-requests?page=\(page)&pageSize=\(pageSize)"
        if let status, !status.isEmpty, status != "ALL" {
            path += "&status=\(status)"
        }
        return try await apiClient.get(path)
    }

    public func approveAdminDeleteRequest(id: Int) async throws -> AiGenerationDeleteRequest {
        try await apiClient.post("/admin/ai/delete-requests/\(id)/approve")
    }

    public func rejectAdminDeleteRequest(id: Int, reason: String) async throws -> AiGenerationDeleteRequest {
        try await apiClient.post("/admin/ai/delete-requests/\(id)/reject", body: AiDeleteRejectRequest(reason: reason))
    }
}
