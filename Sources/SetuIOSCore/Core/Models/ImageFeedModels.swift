import Foundation

public struct ImageFeedRequest: Encodable, Sendable {
    public let r18: Int
    public let limit: Int
    public let keyword: String?
    public let tags: [String]
    public let excludeAI: Bool
    public let aspectRatio: String?
    public let source: String?

    public init(
        r18: Int = 0,
        limit: Int = 10,
        keyword: String? = nil,
        tags: [String] = [],
        excludeAI: Bool = true,
        aspectRatio: String? = nil,
        source: String? = nil
    ) {
        self.r18 = r18
        self.limit = limit
        self.keyword = keyword
        self.tags = tags
        self.excludeAI = excludeAI
        self.aspectRatio = aspectRatio
        self.source = source
    }
}

public struct ImageFeedResponse: Decodable, Sendable {
    public let feedId: String
    public let expiresAt: String
    public let costPerImage: Int
    public let balance: Int
    public let items: [ImageFeedItem]
}

public struct ImageFeedItem: Decodable, Identifiable, Sendable {
    public let token: String
    public let pid: Int
    public let p: Int?
    public let uid: Int
    public let title: String
    public let author: String
    public let r18: Bool
    public let width: Int
    public let height: Int
    public let tags: [String]?
    public let ext: String?
    public let aiType: Int?
    public let uploadDate: Int?
    public let thumbnailUrl: String?
    public let previewUrl: String?

    public var id: String { token }

    public var page: Int { p ?? 0 }

    public var previewURLString: String? {
        previewUrl ?? thumbnailUrl
    }

    private enum CodingKeys: String, CodingKey {
        case token
        case pid
        case p
        case uid
        case title
        case author
        case r18
        case width
        case height
        case tags
        case ext
        case aiType
        case uploadDate
        case thumbnailUrl
        case previewUrl
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decode(String.self, forKey: .token)
        pid = try container.decode(Int.self, forKey: .pid)
        p = try container.decodeIfPresent(Int.self, forKey: .p)
        uid = try container.decodeIfPresent(Int.self, forKey: .uid) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "未命名图片"
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? "未知作者"
        r18 = Self.decodeR18(from: container)
        width = try container.decodeIfPresent(Int.self, forKey: .width) ?? 0
        height = try container.decodeIfPresent(Int.self, forKey: .height) ?? 0
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        ext = try container.decodeIfPresent(String.self, forKey: .ext)
        aiType = try container.decodeIfPresent(Int.self, forKey: .aiType)
        uploadDate = try container.decodeIfPresent(Int.self, forKey: .uploadDate)
        thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        previewUrl = try container.decodeIfPresent(String.self, forKey: .previewUrl)
    }

    private static func decodeR18(from container: KeyedDecodingContainer<CodingKeys>) -> Bool {
        if let value = try? container.decode(Bool.self, forKey: .r18) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: .r18) {
            return value == 1
        }
        return false
    }
}

public struct ImageFeedConsumeRequest: Encodable, Sendable {
    public let feedId: String
    public let token: String
    public let reason: String?

    public init(feedId: String, token: String, reason: String? = nil) {
        self.feedId = feedId
        self.token = token
        self.reason = reason
    }
}

public struct ImageFeedConsumeResponse: Decodable, Sendable {
    public let feedId: String
    public let token: String
    public let charged: Bool
    public let cost: Int
    public let balance: Int
    public let item: SetuImageItem
}
