import Foundation

public struct PointsLogItem: Decodable, Identifiable, Sendable {
    public let id: Int
    public let delta: Int
    public let bizType: String
    public let endpoint: String?
    public let createdAt: String?
}

public struct PointsLogPage: Decodable, Sendable {
    public let page: Int
    public let size: Int
    public let total: Int
    public let items: [PointsLogItem]
}

public struct SetuImageItem: Decodable, Identifiable, Sendable {
    public let pid: Int
    public let p: Int?
    public let uid: Int
    public let title: String
    public let author: String
    public let r18: Int
    public let width: Int
    public let height: Int
    public let ext: String?
    public let aiType: Int?
    public let uploadDate: Int?
    public let tags: [String]?
    public let urls: [String: String]?
    public let url: String?
    public let urlOriginal: String?
    public let urlRegular: String?
    public let urlSmall: String?

    public var id: String {
        "\(pid)-\(p ?? 0)"
    }

    public var page: Int {
        p ?? 0
    }

    public var previewURLString: String? {
        urls?["regular"] ?? urls?["small"] ?? urlRegular ?? urlSmall ?? url ?? urls?["original"] ?? urlOriginal
    }

    public var originalURLString: String? {
        urls?["original"] ?? urlOriginal ?? urls?["regular"] ?? urlRegular ?? url
    }

    private enum CodingKeys: String, CodingKey {
        case pid
        case p
        case uid
        case title
        case author
        case r18
        case width
        case height
        case ext
        case aiType
        case uploadDate
        case tags
        case urls
        case url
        case urlOriginal
        case urlRegular
        case urlSmall
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pid = try container.decode(Int.self, forKey: .pid)
        p = try container.decodeIfPresent(Int.self, forKey: .p)
        uid = try container.decodeIfPresent(Int.self, forKey: .uid) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "未命名图片"
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? "未知作者"
        r18 = Self.decodeR18(from: container)
        width = try container.decodeIfPresent(Int.self, forKey: .width) ?? 0
        height = try container.decodeIfPresent(Int.self, forKey: .height) ?? 0
        ext = try container.decodeIfPresent(String.self, forKey: .ext)
        aiType = try container.decodeIfPresent(Int.self, forKey: .aiType)
        uploadDate = try container.decodeIfPresent(Int.self, forKey: .uploadDate)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        urls = Self.decodeURLs(from: container)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        urlOriginal = try container.decodeIfPresent(String.self, forKey: .urlOriginal)
        urlRegular = try container.decodeIfPresent(String.self, forKey: .urlRegular)
        urlSmall = try container.decodeIfPresent(String.self, forKey: .urlSmall)
    }

    private static func decodeR18(from container: KeyedDecodingContainer<CodingKeys>) -> Int {
        if let value = try? container.decode(Int.self, forKey: .r18) {
            return value
        }
        if let value = try? container.decode(Bool.self, forKey: .r18) {
            return value ? 1 : 0
        }
        return 0
    }

    private static func decodeURLs(from container: KeyedDecodingContainer<CodingKeys>) -> [String: String]? {
        if let values = try? container.decodeIfPresent([String: String].self, forKey: .urls) {
            return values
        }
        guard let values = try? container.decodeIfPresent([String: String?].self, forKey: .urls) else {
            return nil
        }
        return values.compactMapValues { $0 }
    }
}
