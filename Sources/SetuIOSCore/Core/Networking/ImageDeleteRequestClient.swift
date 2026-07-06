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
}

private struct ImageDeleteRequestSubmitRequest: Encodable, Sendable {
    let pid: Int
    let p: Int
    let reason: String?
}
