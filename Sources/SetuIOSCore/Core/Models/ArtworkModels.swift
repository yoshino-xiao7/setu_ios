import Foundation

public enum ArtworkSource: String, Codable, Sendable, CaseIterable, Identifiable {
    case pixiv, gallery
    public var id: String { rawValue }
    public var title: String { self == .pixiv ? "Pixiv 在线" : "本站图库" }
}

public struct ArtworkArtist: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let avatarUrl: String?
    public var followed: Bool?
}

public struct ArtworkPage: Codable, Sendable, Identifiable {
    public let index: Int
    public let pid: String
    public let width: Int
    public let height: Int
    public let thumbnailUrl: String?
    public let previewUrl: String?
    public let originalUrl: String?
    public var bookmarked: Bool?
    public var id: String { "\(pid):\(index)" }
    public var aspectRatio: Double { width > 0 && height > 0 ? Double(width) / Double(height) : 1 }
}

public struct BrowserArtwork: Codable, Sendable, Identifiable {
    public let source: ArtworkSource
    public let id: String
    public let pid: String
    public let title: String
    public var artist: ArtworkArtist
    public let kind: String
    public let pageCount: Int
    public var pages: [ArtworkPage]
    public let tags: [String]
    public let caption: String?
    public let createdAt: String?
    public let views: Int?
    public let bookmarks: Int?
    public var bookmarked: Bool
    public let restricted: Bool
    public let aiGenerated: Bool
}

public struct ArtworkListResponse: Codable, Sendable {
    public let items: [BrowserArtwork]
    public let nextCursor: String?
}

public struct ArtworkSpotlight: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let thumbnailUrl: String?
    public let url: String
}

public struct PixivAccountBinding: Codable, Sendable {
    public let bound: Bool
    public let accountId: String?
    public let name: String?
    public let version: String?
}

public struct PixivAuthorization: Codable, Sendable, Identifiable {
    public let sessionId: String
    public let loginUrl: String
    public var id: String { sessionId }
}

public struct ArtworkAnimation: Codable, Sendable {
    public let id: String
    public let status: String
    public let mediaUrl: String?
    public let message: String?
}

public enum PixivPIDInput {
    public static func parse(_ input: String) throws -> [Int] {
        let parts = input.split { $0.isWhitespace || $0 == "," || $0 == "，" }.map(String.init)
        guard !parts.isEmpty else { throw ValidationError(message: "请输入至少一个 PID") }
        var ids: [Int] = []
        for part in parts {
            guard part.first != "0", part.utf8.allSatisfy({ (48...57).contains($0) }), let id = Int(part), id > 0, id <= Int(Int32.max) else {
                throw ValidationError(message: "PID 无效：\(part.prefix(40))")
            }
            if !ids.contains(id) { ids.append(id) }
        }
        guard ids.count <= 100 else { throw ValidationError(message: "每次最多提交 100 个 PID") }
        return ids
    }
    public struct ValidationError: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }
}
