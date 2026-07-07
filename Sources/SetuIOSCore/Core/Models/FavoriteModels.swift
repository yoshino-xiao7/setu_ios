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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 1
        size = try container.decodeIfPresent(Int.self, forKey: .size)
            ?? container.decodeIfPresent(Int.self, forKey: .pageSize)
            ?? 0
        total = try container.decodeIfPresent(Int.self, forKey: .total)
            ?? container.decodeIfPresent(Int.self, forKey: .count)
            ?? 0
        for key in CodingKeys.listKeys {
            if let values = try container.decodeIfPresent([FavoriteItem].self, forKey: key) {
                items = values
                return
            }
        }
        items = []
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case count
        case content
        case items
        case list
        case page
        case pageSize
        case records
        case rows
        case size
        case total

        static let listKeys: [CodingKeys] = [.items, .list, .records, .rows, .content]
    }
}
