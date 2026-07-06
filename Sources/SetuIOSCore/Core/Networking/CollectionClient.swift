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

    public func square(page: Int = 1, size: Int = 20, sort: String = "hot") async throws -> PageResult<CollectionInfo> {
        try await apiClient.get("/square/collections?page=\(page)&size=\(size)&sort=\(sort)")
    }

    public func likeSquareCollection(id: Int, liked: Bool) async throws {
        if liked {
            let _: String = try await apiClient.post("/square/collections/\(id)/like")
        } else {
            let _: String = try await apiClient.requestWithoutBody("/square/collections/\(id)/like", method: "DELETE")
        }
    }

    public func favoriteSquareCollection(id: Int, favorited: Bool) async throws {
        if favorited {
            let _: String = try await apiClient.post("/square/collections/\(id)/favorite")
        } else {
            let _: String = try await apiClient.requestWithoutBody("/square/collections/\(id)/favorite", method: "DELETE")
        }
    }
}
