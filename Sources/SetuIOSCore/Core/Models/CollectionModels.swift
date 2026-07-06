import Foundation

public enum CollectionVisibility: Int, Codable, Sendable {
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
    public let createdAt: String?
    public let updatedAt: String?
    public let itemCount: Int?
    public let isShared: Bool?
    public let tags: [String]?
    public let themeTags: [String]?
    public let curatorNote: String?
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
}
