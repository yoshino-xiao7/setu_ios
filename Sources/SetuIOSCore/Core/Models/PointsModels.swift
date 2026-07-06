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
}
