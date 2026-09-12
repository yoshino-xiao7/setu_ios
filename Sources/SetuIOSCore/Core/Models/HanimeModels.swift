import Foundation

public struct HanimeGenre: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case latest
        case search
        case previews
    }

    public let id: String
    public let title: String
    public let kind: Kind
    public let query: String?

    public static let latest = HanimeGenre(id: "latest", title: "最新", kind: .latest, query: nil)

    public static let catalog: [HanimeGenre] = [
        .latest,
        HanimeGenre(id: "riban", title: "里番", kind: .search, query: "裏番"),
        HanimeGenre(id: "previews", title: "新番预告", kind: .previews, query: nil),
        HanimeGenre(id: "paomian", title: "泡面番", kind: .search, query: "泡麵番"),
        HanimeGenre(id: "motion", title: "Motion Anime", kind: .search, query: "Motion Anime"),
        HanimeGenre(id: "3dcg", title: "3DCG", kind: .search, query: "3DCG"),
        HanimeGenre(id: "25d", title: "2.5D", kind: .search, query: "2.5D"),
        HanimeGenre(id: "2d", title: "2D动画", kind: .search, query: "2D動畫"),
        HanimeGenre(id: "ai", title: "AI生成", kind: .search, query: "AI生成"),
        HanimeGenre(id: "mmd", title: "MMD", kind: .search, query: "MMD"),
        HanimeGenre(id: "cosplay", title: "Cosplay", kind: .search, query: "Cosplay"),
    ]

    public init(id: String, title: String, kind: Kind, query: String? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.query = query
    }
}

public struct HanimeWork: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let coverURL: String?
    public let subtitle: String
    public let summary: String?

    public var displayTitle: String { title.isEmpty ? "未命名作品" : title }

    public var favoriteSnapshot: ModuleFavoriteSnapshot {
        ModuleFavoriteSnapshot(
            module: .hanime,
            externalId: id,
            title: displayTitle,
            coverUrl: coverURL,
            subtitle: subtitle.isEmpty ? nil : subtitle
        )
    }

    public var watchRecord: ModuleWatchRecord {
        ModuleWatchRecord(
            module: .hanime,
            externalId: id,
            title: displayTitle,
            coverUrl: coverURL,
            subtitle: subtitle.isEmpty ? nil : subtitle
        )
    }

    public init(
        id: String,
        title: String,
        coverURL: String? = nil,
        subtitle: String = "",
        summary: String? = nil
    ) {
        self.id = id
        self.title = title
        self.coverURL = coverURL
        self.subtitle = subtitle
        self.summary = summary
    }
}

public struct HanimeWorkPage: Sendable {
    public let page: Int
    public let total: Int
    public let hasMore: Bool
    public let works: [HanimeWork]

    public init(page: Int, total: Int, hasMore: Bool, works: [HanimeWork]) {
        self.page = page
        self.total = total
        self.hasMore = hasMore
        self.works = works
    }
}

public struct HanimeStream: Identifiable, Hashable, Sendable {
    public let quality: String
    public let url: URL
    public let isHLS: Bool
    public let rank: Int

    public var id: String { "\(quality):\(url.absoluteString)" }

    public init(quality: String, url: URL, isHLS: Bool = false, rank: Int? = nil) {
        self.quality = quality
        self.url = url
        self.isHLS = isHLS
        self.rank = rank ?? Self.rank(for: quality, isHLS: isHLS)
    }

    public static func rank(for quality: String, isHLS: Bool) -> Int {
        let digits = quality.filter(\.isNumber)
        if let value = Int(digits), value > 0 { return value }
        return isHLS ? 1 : 0
    }

    public static func preferred(in streams: [HanimeStream]) -> HanimeStream? {
        streams.max { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            if lhs.isHLS != rhs.isHLS { return lhs.isHLS && !rhs.isHLS }
            return false
        }
    }
}

public struct HanimeWatchPage: Sendable {
    public let work: HanimeWork
    public let streams: [HanimeStream]
    public let related: [HanimeWork]

    public init(work: HanimeWork, streams: [HanimeStream], related: [HanimeWork] = []) {
        self.work = work
        self.streams = streams
        self.related = related
    }

    public var preferredStream: HanimeStream? {
        HanimeStream.preferred(in: streams)
    }
}
