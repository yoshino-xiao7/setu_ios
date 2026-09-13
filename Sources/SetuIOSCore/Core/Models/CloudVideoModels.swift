import Foundation

public struct CloudVideoItem: Decodable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let title: String
    public let description: String?
    public let tags: String?
    public let durationSeconds: Int?
    public let width: Int?
    public let height: Int?
    public let coverUrl: String?
    public let createdAt: String?
    public let updatedAt: String?

    public var durationText: String {
        let total = max(0, durationSeconds ?? 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

public struct CloudVideoPage: Decodable, Sendable {
    public let items: [CloudVideoItem]
    public let total: Int
    public let offset: Int
    public let limit: Int
}

public struct CloudVideoPlayback: Decodable, Sendable {
    public let id: Int
    public let title: String
    public let hlsUrl: String
    public let posterUrl: String?
    public let expireAt: Int64

    public var hlsURL: URL? { URL(string: hlsUrl) }

    public var expiresAtDate: Date {
        Date(timeIntervalSince1970: TimeInterval(expireAt))
    }

    public func isExpiring(within interval: TimeInterval = 90) -> Bool {
        expiresAtDate.timeIntervalSinceNow <= interval
    }
}
