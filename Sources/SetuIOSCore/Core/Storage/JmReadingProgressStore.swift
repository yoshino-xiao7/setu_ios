import Foundation

public struct JmReadingProgress: Codable, Hashable, Sendable {
    public var albumID: String
    public var chapterID: String
    public var pageIndex: Int
    public var pageCount: Int
    public var chapterTitle: String?
    public var updatedAt: Date

    public init(
        albumID: String,
        chapterID: String,
        pageIndex: Int,
        pageCount: Int,
        chapterTitle: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.albumID = albumID
        self.chapterID = chapterID
        self.pageIndex = max(pageIndex, 0)
        self.pageCount = max(pageCount, 0)
        self.chapterTitle = chapterTitle
        self.updatedAt = updatedAt
    }

    public var displayText: String {
        let page = pageProgressText
        if let chapterTitle, !chapterTitle.isEmpty, chapterTitle != page {
            return "\(chapterTitle) · \(page)"
        }
        return page
    }

    public var pageProgressText: String {
        let page = pageIndex + 1
        if pageCount > 0 {
            return "\(page)/\(pageCount)"
        }
        return "第 \(page) 页"
    }

    public var extraJSONString: String? {
        let payload = Envelope(reading: Payload(
            chapterId: chapterID,
            pageIndex: pageIndex,
            pageCount: pageCount,
            chapterTitle: chapterTitle,
            updatedAt: updatedAt.timeIntervalSince1970
        ))
        return (try? JSONEncoder().encode(payload)).flatMap { String(data: $0, encoding: .utf8) }
    }

    public static func fromExtraJSON(_ raw: String?) -> JmReadingProgress? {
        guard let raw, let data = raw.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let reading = envelope.reading else { return nil }
        return JmReadingProgress(
            albumID: "",
            chapterID: reading.chapterId,
            pageIndex: reading.pageIndex,
            pageCount: reading.pageCount,
            chapterTitle: reading.chapterTitle,
            updatedAt: Date(timeIntervalSince1970: reading.updatedAt)
        )
    }

    public func assigning(albumID: String) -> JmReadingProgress {
        var copy = self
        copy.albumID = albumID
        return copy
    }

    public static func newer(_ lhs: JmReadingProgress?, _ rhs: JmReadingProgress?) -> JmReadingProgress? {
        switch (lhs, rhs) {
        case let (left?, right?):
            return left.updatedAt >= right.updatedAt ? left : right
        case let (left?, nil):
            return left
        case let (nil, right?):
            return right
        case (nil, nil):
            return nil
        }
    }

    private struct Envelope: Codable {
        var reading: Payload?
    }

    private struct Payload: Codable {
        var chapterId: String
        var pageIndex: Int
        var pageCount: Int
        var chapterTitle: String?
        var updatedAt: TimeInterval
    }
}

@MainActor
public final class JmReadingProgressStore {
    private let defaults: UserDefaults
    private let ownerID: () -> String

    public init(defaults: UserDefaults = .standard, ownerID: @escaping () -> String) {
        self.defaults = defaults
        self.ownerID = ownerID
    }

    public func progress(albumID: String) -> JmReadingProgress? {
        load()[albumID]
    }

    public func save(_ progress: JmReadingProgress) {
        var items = load()
        items[progress.albumID] = progress
        save(items)
    }

    public func mergeFromFavorite(albumID: String, extraJSON: String?) {
        guard var remote = JmReadingProgress.fromExtraJSON(extraJSON) else { return }
        remote.albumID = albumID
        var items = load()
        if let chosen = JmReadingProgress.newer(items[albumID], remote) {
            items[albumID] = chosen
            save(items)
        }
    }

    private func load() -> [String: JmReadingProgress] {
        guard let data = defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([String: JmReadingProgress].self, from: data) else { return [:] }
        return items
    }

    private func save(_ items: [String: JmReadingProgress]) {
        defaults.set(try? JSONEncoder().encode(items), forKey: key)
    }

    private var key: String {
        "icu.yukiryou.setu.jmReadingProgress.v1.\(ownerID())"
    }
}
