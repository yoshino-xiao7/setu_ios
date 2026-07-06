import Foundation

public struct ImageDeleteRequestClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func listMine(page: Int = 1, pageSize: Int = 10) async throws -> PageResult<ImageDeleteRequestItem> {
        try await apiClient.get("/image-delete/my?page=\(page)&pageSize=\(pageSize)")
    }

    public func detail(id: Int) async throws -> ImageDeleteRequestDetail {
        try await apiClient.get("/image-delete/my/\(id)")
    }

    public func submit(pid: Int, p: Int, reason: String?) async throws {
        let _: String = try await apiClient.post("/image-delete/submit", body: ImageDeleteRequestSubmitRequest(pid: pid, p: p, reason: reason))
    }

    public func adminList(status: Int? = nil, page: Int = 1, pageSize: Int = 20) async throws -> PageResult<ImageDeleteRequestItem> {
        var path = "/admin/image-delete/list?page=\(page)&pageSize=\(pageSize)"
        if let status {
            path += "&status=\(status)"
        }
        return try await apiClient.get(path)
    }

    public func adminPending(page: Int = 1, pageSize: Int = 20) async throws -> PageResult<ImageDeleteRequestItem> {
        try await apiClient.get("/admin/image-delete/pending?page=\(page)&pageSize=\(pageSize)")
    }

    public func adminDetail(id: Int) async throws -> ImageDeleteRequestDetail {
        try await apiClient.get("/admin/image-delete/\(id)")
    }

    public func review(requestID: Int, approve: Bool, remark: String?) async throws {
        let _: String = try await apiClient.post(
            "/admin/image-delete/review",
            body: ImageDeleteRequestReviewRequest(requestId: requestID, approve: approve, remark: remark)
        )
    }

    public func batchReview(requestIDs: [Int], approve: Bool, remark: String?) async throws -> DeleteRequestBatchReviewResponse {
        try await apiClient.post(
            "/admin/image-delete/batch-review",
            body: ImageDeleteRequestBatchReviewRequest(requestIds: requestIDs, approve: approve, remark: remark)
        )
    }
}

private struct ImageDeleteRequestSubmitRequest: Encodable, Sendable {
    let pid: Int
    let p: Int
    let reason: String?
}

private struct ImageDeleteRequestReviewRequest: Encodable, Sendable {
    let requestId: Int
    let approve: Bool
    let remark: String?
}

private struct ImageDeleteRequestBatchReviewRequest: Encodable, Sendable {
    let requestIds: [Int]
    let approve: Bool
    let remark: String?
}
