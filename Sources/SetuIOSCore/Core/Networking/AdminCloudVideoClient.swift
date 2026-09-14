import Foundation

public protocol CloudVideoUploadSessioning: Sendable {
    func createUploadSession(title: String) async throws -> CloudVideoUploadSession
    func refreshTusTicket(id: Int) async throws -> CloudVideoUploadSession
    func syncAdminCloudVideo(id: Int) async throws -> AdminCloudVideoItem
    func updateAdminCloudVideo(id: Int, update: AdminCloudVideoUpdate) async throws -> AdminCloudVideoItem
    func deleteAdminCloudVideo(id: Int) async throws
}

public struct AdminCloudVideoClient: CloudVideoUploadSessioning, Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func list(
        status: String? = nil,
        keywords: String? = nil,
        rating: String? = nil,
        page: Int = 1,
        pageSize: Int = 20
    ) async throws -> PageResult<AdminCloudVideoItem> {
        try await apiClient.get(queryPath(
            "/admin/cloud-video",
            items: [
                URLQueryItem(name: "status", value: status),
                URLQueryItem(name: "keywords", value: keywords),
                URLQueryItem(name: "rating", value: rating),
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "pageSize", value: "\(pageSize)")
            ]
        ))
    }

    public func detail(id: Int) async throws -> AdminCloudVideoItem {
        try await apiClient.get("/admin/cloud-video/\(id)")
    }

    public func createUploadSession(title: String) async throws -> CloudVideoUploadSession {
        struct Body: Encodable, Sendable { var title: String }
        return try await apiClient.post("/admin/cloud-video/upload-sessions", body: Body(title: title))
    }

    public func refreshTusTicket(id: Int) async throws -> CloudVideoUploadSession {
        try await apiClient.post("/admin/cloud-video/\(id)/tus-ticket")
    }

    public func syncAdminCloudVideo(id: Int) async throws -> AdminCloudVideoItem {
        try await apiClient.post("/admin/cloud-video/\(id)/sync")
    }

    public func updateAdminCloudVideo(id: Int, update: AdminCloudVideoUpdate) async throws -> AdminCloudVideoItem {
        try await apiClient.patch("/admin/cloud-video/\(id)", body: update)
    }

    public func deleteAdminCloudVideo(id: Int) async throws {
        let _: String = try await apiClient.requestWithoutBody("/admin/cloud-video/\(id)", method: "DELETE")
    }

    private func queryPath(_ path: String, items: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.path = path
        components.queryItems = items.filter { item in
            guard let value = item.value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return components.string ?? path
    }
}
