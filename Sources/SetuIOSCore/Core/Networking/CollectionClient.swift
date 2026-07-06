import Foundation

public struct CollectionClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func listMine() async throws -> [CollectionInfo] {
        try await apiClient.get("/collections/mine")
    }

    public func items(collectionID: Int, page: Int = 1, size: Int = 24) async throws -> CollectionItemPage {
        try await apiClient.get("/collections/\(collectionID)/items?page=\(page)&size=\(size)")
    }
}
