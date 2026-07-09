import Foundation

public struct ImageFeedClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func feed(_ request: ImageFeedRequest) async throws -> ImageFeedResponse {
        try await apiClient.post("/mobile/images/feed", body: request)
    }

    public func consume(feedID: String, token: String, reason: String? = nil) async throws -> ImageFeedConsumeResponse {
        try await apiClient.post(
            "/mobile/images/feed/consume",
            body: ImageFeedConsumeRequest(feedId: feedID, token: token, reason: reason)
        )
    }
}
