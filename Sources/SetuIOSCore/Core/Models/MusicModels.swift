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

public struct MusicUrlResponse: Decodable, Sendable {
    public let code: Int?
    public let data: [MusicUrlItem]?
    public let playability: String?
    public let fullPlayable: Bool?
    public let trial: Bool?
    public let playabilityReason: String?
    public let message: String?
    public let msg: String?
}

public struct MusicUrlItem: Decodable, Identifiable, Sendable {
    public let id: Int
    public let url: String?
    public let trialUrl: String?
    public let level: String?
    public let size: Int?
    public let playability: String?
    public let fullPlayable: Bool?
    public let trial: Bool?
    public let playabilityReason: String?
    public let message: String?
    public let msg: String?

    public var playableURLString: String? {
        guard playability == "FULL", fullPlayable == true else {
            return nil
        }
        return url
    }

    public var unavailableMessage: String {
        switch playability {
        case "TRIAL":
            return "当前音乐源仅支持试听，无法播放完整版"
        case "LOGIN_INVALID":
            return "音乐服务账号已失效，请稍后再试"
        case "UNAVAILABLE":
            return playabilityReason ?? message ?? msg ?? "该歌曲暂不可播放"
        default:
            return playabilityReason ?? message ?? msg ?? "该歌曲暂不可播放"
        }
    }
}

public struct MusicLyricResponse: Decodable, Sendable {
    public let lrc: MusicLyricPayload?
    public let tlyric: MusicLyricPayload?
}

public struct MusicLyricPayload: Decodable, Sendable {
    public let lyric: String?
}

public struct MusicMvDetailResponse: Decodable, Sendable {
    public let code: Int?
    public let data: MusicMvDetail
}

public struct MusicMvDetail: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let artistId: Int?
    public let artistName: String?
    public let briefDesc: String?
    public let desc: String?
    public let cover: String?
    public let coverId: Int?
    public let playCount: Int?
    public let subCount: Int?
    public let shareCount: Int?
    public let commentCount: Int?
    public let duration: Int?
    public let publishTime: String?
    public let brs: [MusicMvQuality]?
    public let artists: [MusicMvArtist]?
}

public struct MusicMvQuality: Decodable, Identifiable, Sendable {
    public let size: Int?
    public let br: Int
    public let point: Int?

    public var id: Int { br }
}

public struct MusicMvArtist: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let img1v1Url: String?
}

public struct MusicMvUrlResponse: Decodable, Sendable {
    public let code: Int?
    public let data: MusicMvUrlData?
}

public struct MusicMvUrlData: Decodable, Identifiable, Sendable {
    public let id: Int
    public let url: String?
    public let r: Int?
    public let size: Int?
    public let md5: String?
    public let duration: Int?
    public let br: Int?
    public let depth: Int?
    public let encodeType: String?
    public let type: String?
    public let expi: Int?
    public let fee: Int?

    public var httpsURLString: String? {
        url?.replacingOccurrences(of: "http://", with: "https://")
    }
}

public struct NeteaseToken: Decodable, Identifiable, Sendable {
    public let id: Int
    public let cookie: String
    public let nickname: String
    public let status: Int
    public let createdAt: String?
    public let updatedAt: String?

    public var statusTitle: String {
        status == 1 ? "启用" : "禁用"
    }

    public var maskedCookie: String {
        if cookie.isEmpty {
            return "-"
        }
        if cookie.count <= 20 {
            return cookie
        }
        return "\(cookie.prefix(20))..."
    }
}

public struct NeteaseTokenCreateRequest: Encodable, Sendable {
    public let cookie: String
    public let nickname: String

    public init(cookie: String, nickname: String) {
        self.cookie = cookie
        self.nickname = nickname
    }
}

public struct NeteaseTokenUpdateRequest: Encodable, Sendable {
    public let cookie: String?
    public let nickname: String?
    public let status: Int?

    public init(cookie: String? = nil, nickname: String? = nil, status: Int? = nil) {
        self.cookie = cookie
        self.nickname = nickname
        self.status = status
    }
}

public struct NeteaseTokenCheckResult: Decodable, Sendable {
    public let tokenId: Int
    public let nickname: String?
    public let status: Int?
    public let cookieValid: Bool
    public let account: NeteaseAccountInfo?
    public let vip: Bool?
    public let vipType: Int?
    public let accountVipType: Int?
    public let profileVipType: Int?
    public let playbackProbe: NeteasePlaybackProbe?

    public var label: String {
        if !cookieValid || playbackProbe?.playability == "LOGIN_INVALID" {
            return "Cookie 失效"
        }
        if playbackProbe?.fullPlayable == true {
            return "完整可播"
        }
        if playbackProbe?.playability == "TRIAL" {
            return "仅试听"
        }
        if playbackProbe?.playability == "UNAVAILABLE" {
            return "不可播"
        }
        if vip == true {
            return "疑似 VIP"
        }
        return "非 VIP/未知"
    }

    public var reason: String {
        if !cookieValid || playbackProbe?.playability == "LOGIN_INVALID" {
            return "网易云 Cookie 已失效，请更新"
        }
        if playbackProbe?.fullPlayable == true {
            return playbackProbe?.reason ?? "测试歌曲可完整播放"
        }
        if playbackProbe?.playability == "TRIAL" {
            return playbackProbe?.reason ?? "测试歌曲仅返回试听链接"
        }
        if playbackProbe?.playability == "UNAVAILABLE" {
            return playbackProbe?.reason ?? "测试歌曲暂不可播，建议换一首确认是 VIP 的歌曲复查"
        }
        if playbackProbe?.skipped == true {
            return "未传测试歌曲，仅检查登录态和账号字段"
        }
        if vip == true {
            return "账号字段疑似 VIP，建议填写测试歌曲 ID 复查"
        }
        return "账号字段未显示 VIP，或尚未验证播放能力"
    }
}

public struct NeteaseAccountInfo: Decodable, Sendable {
    public let code: Int?
    public let userId: Int?
    public let nickname: String?
    public let avatarUrl: String?
    public let profileVipType: Int?
    public let accountId: Int?
    public let accountVipType: Int?
}

public struct NeteasePlaybackProbe: Decodable, Sendable {
    public let skipped: Bool?
    public let songId: String?
    public let level: String?
    public let playability: String?
    public let fullPlayable: Bool?
    public let trial: Bool?
    public let reason: String?
    public let neteaseCode: Int?
    public let fee: Int?
    public let payed: Int?
    public let requestedLevel: String?
    public let effectiveLevel: String?
    public let urlAvailable: Bool?
    public let trialUrlAvailable: Bool?
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

public struct UserMusicPlaylistDetail: Decodable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let description: String?
    public let coverUrl: String?
    public let isPublic: Int?
    public let playMode: String?
    public let songCount: Int?
    public let playCount: Int?
    public let createdAt: String?
    public let updatedAt: String?
    public let songs: [PlaylistSong]?
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

public struct CreateMusicPlaylistRequest: Encodable, Sendable {
    public let name: String
    public let description: String?
    public let coverUrl: String?
    public let isPublic: Int?

    public init(name: String, description: String? = nil, coverUrl: String? = nil, isPublic: Int? = 0) {
        self.name = name
        self.description = description
        self.coverUrl = coverUrl
        self.isPublic = isPublic
    }
}

public struct AddSongToPlaylistRequest: Encodable, Sendable {
    public let songId: Int
    public let songName: String
    public let artistName: String
    public let albumName: String?
    public let coverUrl: String?
    public let duration: Int

    public init(song: MusicSong) {
        self.songId = song.id
        self.songName = song.name
        self.artistName = song.artistNames
        self.albumName = song.albumName
        self.coverUrl = song.coverURLString
        self.duration = song.durationMilliseconds
    }
}

public struct AddMusicHistoryRequest: Encodable, Sendable {
    public let songId: Int
    public let songName: String
    public let artistName: String
    public let albumName: String?
    public let coverUrl: String?
    public let duration: Int

    public init(song: MusicSong) {
        self.songId = song.id
        self.songName = song.name
        self.artistName = song.artistNames
        self.albumName = song.albumName
        self.coverUrl = song.coverURLString
        self.duration = song.durationMilliseconds
    }
}

public struct UpdateMusicPlayModeRequest: Encodable, Sendable {
    public let playMode: String

    public init(playMode: String) {
        self.playMode = playMode
    }
}
