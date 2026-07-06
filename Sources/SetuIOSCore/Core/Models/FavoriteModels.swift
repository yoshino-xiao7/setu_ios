import Foundation

public struct FavoriteItem: Decodable, Identifiable, Sendable {
    public let favoriteId: Int
    public let imageId: Int?
    public let pid: Int
    public let p: Int
    public let favoritedAt: String?
    public let image: FavoriteImage?

    public var id: Int { favoriteId }
}

public struct FavoritePage: Decodable, Sendable {
    public let page: Int
    public let size: Int
    public let total: Int
    public let items: [FavoriteItem]
}
