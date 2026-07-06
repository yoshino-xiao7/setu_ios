import Foundation

public struct DownloadClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func sign(url: String, filename: String) async throws -> DownloadSignResponse {
        try await apiClient.post("/download/sign", body: DownloadSignRequest(url: url, filename: filename))
    }
}
