import Foundation

public struct CollectionClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func listMine() async throws -> [CollectionInfo] {
        try await apiClient.get("/collections/mine")
    }

    public func create(name: String, description: String?, visibility: CollectionVisibility) async throws -> Int {
        try await apiClient.post(
            "/collections",
            body: CollectionMutationRequest(name: name, description: description, visibility: visibility)
        )
    }

    public func info(collectionID: Int) async throws -> CollectionInfo {
        try await apiClient.get("/collections/\(collectionID)")
    }

    public func update(collectionID: Int, name: String, description: String?, visibility: CollectionVisibility) async throws {
        let _: String = try await apiClient.put(
            "/collections/\(collectionID)",
            body: CollectionMutationRequest(name: name, description: description, visibility: visibility)
        )
    }

    public func delete(collectionID: Int) async throws {
        let _: String = try await apiClient.requestWithoutBody("/collections/\(collectionID)", method: "DELETE")
    }

    public func items(collectionID: Int, page: Int = 1, size: Int = 24) async throws -> CollectionItemPage {
        try await apiClient.get("/collections/\(collectionID)/items?page=\(page)&size=\(size)")
    }

    public func removeItem(collectionID: Int, pid: Int, p: Int) async throws {
        let _: String = try await apiClient.requestWithoutBody("/collections/\(collectionID)/items/\(pid)/\(p)", method: "DELETE")
    }

    public func addItem(collectionID: Int, pid: Int, p: Int) async throws {
        let _: String = try await apiClient.post("/collections/\(collectionID)/items/\(pid)/\(p)")
    }

    public func share(collectionID: Int) async throws {
        let _: String = try await apiClient.post("/collections/\(collectionID)/share")
    }

    public func unshare(collectionID: Int) async throws {
        let _: String = try await apiClient.requestWithoutBody("/collections/\(collectionID)/share", method: "DELETE")
    }

    public func setCover(collectionID: Int, pid: Int, p: Int) async throws {
        let _: String = try await apiClient.requestWithoutBody("/collections/\(collectionID)/cover?pid=\(pid)&p=\(p)", method: "PUT")
    }

    public func square(
        page: Int = 1,
        size: Int = 20,
        sort: String = "hot",
        keyword: String? = nil,
        ownerID: Int? = nil
    ) async throws -> PageResult<CollectionInfo> {
        var components = URLComponents()
        components.path = "/square/collections"
        var queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: String(size)),
            URLQueryItem(name: "sort", value: sort)
        ]
        if let keyword = keyword?.trimmingCharacters(in: .whitespacesAndNewlines), !keyword.isEmpty {
            queryItems.append(URLQueryItem(name: "keyword", value: keyword))
        }
        if let ownerID {
            queryItems.append(URLQueryItem(name: "ownerId", value: String(ownerID)))
        }
        components.queryItems = queryItems
        return try await apiClient.get(components.string ?? "/square/collections")
    }

    public func squareDetail(id: Int) async throws -> CollectionInfo {
        try await apiClient.get("/square/collections/\(id)")
    }

    public func publicUserProfile(userID: Int) async throws -> PublicUserProfile {
        try await apiClient.get("/square/users/\(userID)")
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

private struct CollectionMutationRequest: Encodable, Sendable {
    let name: String
    let description: String?
    let visibility: CollectionVisibility
}
