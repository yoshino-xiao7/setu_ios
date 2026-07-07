import Foundation

public enum CollectionVisibility: Int, Codable, Sendable, CaseIterable {
    case `private` = 0
    case publicVisible = 1

    public var title: String {
        switch self {
        case .private: "私有"
        case .publicVisible: "公开"
        }
    }
}

public struct CollectionInfo: Decodable, Identifiable, Sendable {
    public let id: Int
    public let userId: Int
    public let name: String
    public let description: String?
    public let visibility: CollectionVisibility
    public let isDefault: Bool
    public let coverPid: Int?
    public let coverP: Int?
    public let coverUrl: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let ownerNickname: String?
    public let ownerAvatarUrl: String?
    public let itemCount: Int?
    public let isShared: Bool?
    public let shareViewCount: Int?
    public let shareLikeCount: Int?
    public let shareFavCount: Int?
    public let shareCreatedAt: String?
    public let likedByMe: Bool?
    public let favoritedByMe: Bool?
    public let likeCount: Int?
    public let favoriteCount: Int?
    public let previewImages: [CollectionPreviewImage]?
    public let tags: [String]?
    public let themeTags: [String]?
    public let curatorNote: String?
    public let scoreReason: String?
    public let recentItemCount: Int?
    public let ownerCollectionCount: Int?
}

public struct CollectionPreviewImage: Decodable, Identifiable, Sendable {
    public let pid: Int
    public let p: Int?
    public let title: String?
    public let author: String?
    public let url: String?
    public let urlSmall: String?
    public let urlRegular: String?
    public let urlOriginal: String?
    public let width: Int?
    public let height: Int?
    public let r18: Int?
    public let tags: [String]?

    public var id: String {
        "\(pid)-\(p ?? 0)"
    }

    public var bestURLString: String? {
        urlSmall ?? urlRegular ?? url ?? urlOriginal
    }
}

public struct FavoriteImage: Decodable, Identifiable, Sendable {
    public let id: Int
    public let pid: Int
    public let p: Int
    public let uid: Int
    public let title: String
    public let author: String
    public let r18: Int
    public let width: Int
    public let height: Int
    public let tags: [String]
    public let urlOriginal: String?
    public let urlRegular: String?
    public let urlSmall: String?
}

public struct CollectionItem: Decodable, Identifiable, Sendable {
    public let itemId: Int
    public let pid: Int
    public let p: Int
    public let addedAt: String?
    public let image: FavoriteImage?

    public var id: Int { itemId }
}

public struct CollectionItemPage: Decodable, Sendable {
    public let page: Int
    public let size: Int
    public let total: Int
    public let items: [CollectionItem]

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
            if let values = try container.decodeIfPresent([CollectionItem].self, forKey: key) {
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
