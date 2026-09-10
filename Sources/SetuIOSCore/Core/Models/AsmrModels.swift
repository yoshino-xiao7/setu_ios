import Foundation

public struct AsmrWork: Decodable, Identifiable, Sendable, Hashable {
    public let id: Int
    public let title: String
    public let name: String?
    public let circleName: String?
    public let coverURL: String?
    public let durationSeconds: Int?
    public let nsfw: Bool?
    public let hasSubtitle: Bool?
    public let releaseDate: String?
    public let price: Int?

    public var displayTitle: String { title.isEmpty ? (name ?? "未命名作品") : title }
    public var subtitle: String { [circleName, formattedDuration].compactMap { $0 }.joined(separator: " · ") }

    public var favoriteSnapshot: ModuleFavoriteSnapshot {
        ModuleFavoriteSnapshot(
            module: .asmr,
            externalId: String(id),
            title: displayTitle,
            coverUrl: coverURL,
            subtitle: subtitle
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleInt(forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name)
        circleName = try Self.decodeCircleName(container)
        coverURL = try container.decodeIfPresent(String.self, forKey: .mainCoverUrl)
            ?? container.decodeIfPresent(String.self, forKey: .coverUrl)
            ?? container.decodeIfPresent(String.self, forKey: .thumbnailCoverUrl)
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .duration)
        nsfw = try container.decodeIfPresent(Bool.self, forKey: .nsfw)
        hasSubtitle = try container.decodeIfPresent(Bool.self, forKey: .hasSubtitle)
        releaseDate = try container.decodeIfPresent(String.self, forKey: .release)
        price = try container.decodeIfPresent(Int.self, forKey: .price)
    }

    public init(
        id: Int,
        title: String,
        circleName: String? = nil,
        coverURL: String? = nil,
        durationSeconds: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.name = title
        self.circleName = circleName
        self.coverURL = coverURL
        self.durationSeconds = durationSeconds
        self.nsfw = nil
        self.hasSubtitle = nil
        self.releaseDate = nil
        self.price = nil
    }

    private var formattedDuration: String? {
        guard let durationSeconds, durationSeconds > 0 else { return nil }
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        if hours > 0 { return "\(hours)小时\(minutes)分" }
        return "\(minutes)分钟"
    }

    private static func decodeCircleName(_ container: KeyedDecodingContainer<CodingKeys>) throws -> String? {
        if let name = try container.decodeIfPresent(String.self, forKey: .circleName) {
            return name
        }
        if let circle = try container.decodeIfPresent(AsmrNamedRef.self, forKey: .circle) {
            return circle.name
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, name, nsfw, price, duration, release
        case circle
        case circleName
        case mainCoverUrl
        case coverUrl
        case thumbnailCoverUrl
        case hasSubtitle = "has_subtitle"
    }
}

public struct AsmrWorkPage: Decodable, Sendable {
    public let page: Int
    public let pageSize: Int
    public let total: Int
    public let works: [AsmrWork]

    public init(page: Int, pageSize: Int, total: Int, works: [AsmrWork]) {
        self.page = page
        self.pageSize = pageSize
        self.total = total
        self.works = works
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let pagination = try container.decodeIfPresent(AsmrPagination.self, forKey: .pagination) {
            page = pagination.currentPage
            pageSize = pagination.pageSize
            total = pagination.totalCount
        } else {
            page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 1
            pageSize = try container.decodeIfPresent(Int.self, forKey: .pageSize) ?? 0
            total = try container.decodeIfPresent(Int.self, forKey: .totalCount)
                ?? container.decodeIfPresent(Int.self, forKey: .total) ?? 0
        }
        works = try container.decodeIfPresent([AsmrWork].self, forKey: .works) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case pagination, works, page, pageSize, total, totalCount
    }
}

public struct AsmrTrack: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let url: URL
    public let durationSeconds: Double?

    public init(id: String, title: String, url: URL, durationSeconds: Double? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.durationSeconds = durationSeconds
    }
}

struct AsmrNamedRef: Decodable, Sendable {
    let name: String?
}

struct AsmrPagination: Decodable, Sendable {
    let currentPage: Int
    let pageSize: Int
    let totalCount: Int
}

struct AsmrTrackNode: Decodable, Sendable {
    let type: String?
    let title: String?
    let name: String?
    let mediaDownloadUrl: String?
    let mediaStreamUrl: String?
    let hash: String?
    let duration: Double?
    let children: [AsmrTrackNode]?

    var displayTitle: String { title ?? name ?? "未命名音轨" }

    func flattenedAudio() -> [AsmrTrack] {
        let kind = (type ?? "").lowercased()
        if kind == "folder" || kind == "directory" {
            return (children ?? []).flatMap { $0.flattenedAudio() }
        }
        let candidates = [mediaStreamUrl, mediaDownloadUrl].compactMap { $0 }
        guard let raw = candidates.first, let url = URL(string: raw) else { return [] }
        let audioExtensions = ["mp3", "m4a", "flac", "wav", "ogg", "aac", "opus"]
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty, !audioExtensions.contains(ext) {
            return []
        }
        return [AsmrTrack(id: hash ?? url.absoluteString, title: displayTitle, url: url, durationSeconds: duration)]
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleInt(forKey key: Key) throws -> Int {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let raw = try? decode(String.self, forKey: key), let value = Int(raw) { return value }
        throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing int for \(key)"))
    }
}
