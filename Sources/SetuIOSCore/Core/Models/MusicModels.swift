import Foundation

public struct MusicArtist: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String
}

public struct MusicAlbum: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let picUrl: String?
}

public struct MusicSong: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let artists: [MusicArtist]?
    public let ar: [MusicArtist]?
    public let album: MusicAlbum?
    public let al: MusicAlbum?
    public let duration: Int?
    public let dt: Int?
    public let picUrl: String?
    public let mv: Int?

    public var artistNames: String {
        (artists ?? ar ?? []).map(\.name).joined(separator: " / ")
    }

    public var albumName: String {
        album?.name ?? al?.name ?? "未知专辑"
    }

    public var coverURLString: String? {
        picUrl ?? album?.picUrl ?? al?.picUrl
    }

    public var durationMilliseconds: Int {
        duration ?? dt ?? 0
    }
}

public struct MusicSearchResult: Decodable, Sendable {
    public let result: MusicSearchPayload
}

public struct MusicSearchPayload: Decodable, Sendable {
    public let songs: [MusicSong]
    public let songCount: Int
}

public struct MusicHotSearchResponse: Decodable, Sendable {
    public let code: Int?
    public let result: MusicHotSearchPayload
}

public struct MusicHotSearchPayload: Decodable, Sendable {
    public let hots: [MusicHotSearchItem]
}

public struct MusicHotSearchItem: Decodable, Identifiable, Sendable {
    public let first: String
    public let second: Int?
    public let iconType: Int?

    public var id: String { first }
}

public struct UserMusicPlaylist: Decodable, Identifiable, Sendable {
    public let id: Int
    public let userId: Int?
    public let name: String
    public let description: String?
    public let coverUrl: String?
    public let isPublic: Int?
    public let playMode: String?
    public let songCount: Int?
    public let playCount: Int?
    public let createdAt: String?
    public let updatedAt: String?
}

public struct PlaylistSong: Decodable, Identifiable, Sendable {
    public let id: Int
    public let songId: Int
    public let songName: String
    public let artistName: String
    public let albumName: String?
    public let coverUrl: String?
    public let duration: Int?
    public let sortOrder: Int?
    public let createdAt: String?
}

public struct MusicHistoryRecord: Decodable, Identifiable, Sendable {
    public let id: Int
    public let userId: Int
    public let songId: Int
    public let songName: String
    public let artistName: String
    public let albumName: String?
    public let coverUrl: String?
    public let duration: Int?
    public let playTime: String
}
