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

    public func createBatch(_ request: GalleryUploadInitRequest) async throws -> GalleryUploadInitResponse {
        let headers = request.clientRequestId.map { ["Idempotency-Key": $0] } ?? [:]
        return try await apiClient.post("/gallery/uploads/batches", body: request, headers: headers)
    }

    public func updateItemStatus(batchID: Int, clientItemID: String, request: GalleryUploadItemStatusRequest) async throws -> GalleryUploadItem {
        let encodedID = clientItemID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? clientItemID
        return try await apiClient.post("/gallery/uploads/batches/\(batchID)/items/\(encodedID)/status", body: request)
    }

    public func completeBatch(batchID: Int, items: [GalleryUploadCompleteItem]) async throws -> GalleryUploadCompleteResponse {
        try await apiClient.post("/gallery/uploads/batches/\(batchID)/complete", body: GalleryUploadCompleteRequest(items: items))
    }

    public func uploadPreparedItem(initResponse: GalleryUploadInitResponse, item: GalleryUploadItem, data: Data, contentType: String) async throws -> String? {
        if initResponse.uploadPolicy.provider == "mock" {
            try await Task.sleep(nanoseconds: 180_000_000)
            return "mock-etag-\(item.submissionId)"
        }

        let uploadURLString = item.uploadUrl ?? initResponse.uploadPolicy.uploadUrl
        guard let uploadURLString, let uploadURL = URL(string: uploadURLString) else {
            throw APIError.invalidURL("gallery direct upload")
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = item.uploadMethod ?? initResponse.uploadPolicy.uploadMethod ?? "PUT"
        let headers = (initResponse.uploadPolicy.uploadHeaders ?? [:]).merging(item.uploadHeaders ?? [:]) { _, itemValue in itemValue }
        for (name, value) in headers where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.upload(for: request, from: data)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.httpStatus(httpResponse.statusCode, message: "图库直传失败")
        }
        return httpResponse.value(forHTTPHeaderField: "etag")?.replacingOccurrences(of: "\"", with: "")
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
