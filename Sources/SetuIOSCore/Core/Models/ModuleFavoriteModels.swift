import Foundation

public enum ModuleFavoriteModule: String, Codable, Sendable, CaseIterable {
    case asmr = "ASMR"
    case jm = "JM"
}

public struct ModuleFavoriteItem: Decodable, Identifiable, Sendable, Hashable {
    public let favoriteId: Int?
    public let module: ModuleFavoriteModule
    public let externalId: String
    public let title: String
    public let coverUrl: String?
    public let subtitle: String?
    public let extraJson: String?
    public let createdAt: String?

    public var id: String { "\(module.rawValue):\(externalId)" }

    public init(
        favoriteId: Int? = nil,
        module: ModuleFavoriteModule,
        externalId: String,
        title: String,
        coverUrl: String? = nil,
        subtitle: String? = nil,
        extraJson: String? = nil,
        createdAt: String? = nil
    ) {
        self.favoriteId = favoriteId
        self.module = module
        self.externalId = externalId
        self.title = title
        self.coverUrl = coverUrl
        self.subtitle = subtitle
        self.extraJson = extraJson
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favoriteId = try container.decodeIfPresent(Int.self, forKey: .id)
            ?? container.decodeIfPresent(Int.self, forKey: .favoriteId)
        module = try container.decode(ModuleFavoriteModule.self, forKey: .module)
        externalId = try container.decode(String.self, forKey: .externalId)
        title = try container.decode(String.self, forKey: .title)
        coverUrl = try container.decodeIfPresent(String.self, forKey: .coverUrl)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        extraJson = try container.decodeIfPresent(String.self, forKey: .extraJson)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, favoriteId, module, externalId, title, coverUrl, subtitle, extraJson, createdAt
    }
}

public struct ModuleFavoritePage: Decodable, Sendable {
    public let page: Int
    public let size: Int
    public let total: Int
    public let items: [ModuleFavoriteItem]

    public init(page: Int, size: Int, total: Int, items: [ModuleFavoriteItem]) {
        self.page = page
        self.size = size
        self.total = total
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 1
        size = try container.decodeIfPresent(Int.self, forKey: .size)
            ?? container.decodeIfPresent(Int.self, forKey: .pageSize)
            ?? 0
        total = try container.decodeIfPresent(Int.self, forKey: .total)
            ?? container.decodeIfPresent(Int.self, forKey: .count)
            ?? 0
        items = try container.decodeIfPresent([ModuleFavoriteItem].self, forKey: .items)
            ?? container.decodeIfPresent([ModuleFavoriteItem].self, forKey: .list)
            ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case page, size, pageSize, total, count, items, list
    }
}

public struct ModuleFavoriteSnapshot: Encodable, Sendable {
    public var module: ModuleFavoriteModule
    public var externalId: String
    public var title: String
    public var coverUrl: String?
    public var subtitle: String?
    public var extraJson: String?

    public init(
        module: ModuleFavoriteModule,
        externalId: String,
        title: String,
        coverUrl: String? = nil,
        subtitle: String? = nil,
        extraJson: String? = nil
    ) {
        self.module = module
        self.externalId = externalId
        self.title = title
        self.coverUrl = coverUrl
        self.subtitle = subtitle
        self.extraJson = extraJson
    }
}

public struct ModuleFavoriteExistsBatchRequest: Encodable, Sendable {
    public var module: ModuleFavoriteModule
    public var externalIds: [String]

    public init(module: ModuleFavoriteModule, externalIds: [String]) {
        self.module = module
        self.externalIds = externalIds
    }
}

public struct ModuleFavoriteExistsBatchResponse: Decodable, Sendable {
    public var exists: [String: Bool]
}
