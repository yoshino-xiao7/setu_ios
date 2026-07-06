import Foundation

public struct GalleryUploadClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func listMine(status: String? = nil, page: Int = 1, pageSize: Int = 20) async throws -> PageResult<GalleryUploadBatchSummary> {
        var path = "/gallery/uploads/batches?page=\(page)&pageSize=\(pageSize)"
        if let status, !status.isEmpty, status != "ALL" {
            path += "&status=\(status)"
        }
        return try await apiClient.get(path)
    }

    public func detail(batchID: Int) async throws -> GalleryUploadBatchDetail {
        try await apiClient.get("/gallery/uploads/batches/\(batchID)")
    }

    public func cancel(batchID: Int) async throws {
        let _: String = try await apiClient.post("/gallery/uploads/batches/\(batchID)/cancel")
    }

    public func adminList(status: String? = nil, page: Int = 1, pageSize: Int = 20) async throws -> PageResult<GalleryUploadBatchSummary> {
        var path = "/admin/gallery-submission-batches?page=\(page)&pageSize=\(pageSize)"
        if let status, !status.isEmpty, status != "ALL" {
            path += "&status=\(status)"
        }
        return try await apiClient.get(path)
    }

    public func adminDetail(batchID: Int) async throws -> GalleryUploadBatchDetail {
        try await apiClient.get("/admin/gallery-submission-batches/\(batchID)")
    }

    public func approve(batchID: Int, request: GalleryAdminApproveRequest) async throws -> GalleryAdminReviewResponse {
        try await apiClient.post("/admin/gallery-submission-batches/\(batchID)/approve", body: request)
    }

    public func reject(batchID: Int, request: GalleryAdminRejectRequest) async throws -> GalleryAdminReviewResponse {
        try await apiClient.post("/admin/gallery-submission-batches/\(batchID)/reject", body: request)
    }
}
