import Foundation

public struct NeteaseUserProfile: Codable, Hashable, Sendable {
    public let userId: Int
    public let nickname: String
    public let avatarUrl: String?
    public let vipType: Int
    public let signature: String?

    public init(userId: Int, nickname: String, avatarUrl: String?, vipType: Int, signature: String? = nil) {
        self.userId = userId
        self.nickname = nickname
        self.avatarUrl = avatarUrl
        self.vipType = vipType
        self.signature = signature
    }

    public var isVIP: Bool {
        vipType > 0
    }
}

public struct NeteaseUserPlaylist: Codable, Hashable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let coverImgUrl: String?
    public let trackCount: Int?
    public let playCount: Int?
    public let subscribed: Bool?
    public let creator: NeteasePlaylistCreator?

    public struct NeteasePlaylistCreator: Codable, Hashable, Sendable {
        public let userId: Int
        public let nickname: String?
    }

    public init(id: Int, name: String, coverImgUrl: String?, trackCount: Int?, playCount: Int?, subscribed: Bool?, creator: NeteasePlaylistCreator? = nil) {
        self.id = id
        self.name = name
        self.coverImgUrl = coverImgUrl
        self.trackCount = trackCount
        self.playCount = playCount
        self.subscribed = subscribed
        self.creator = creator
    }
}

public struct NeteaseQrKeyResponse: Codable, Sendable {
    public struct DataBody: Codable, Sendable {
        public let code: Int
        public let unikey: String
    }
    public let data: DataBody
    public let code: Int
}

public struct NeteaseQrCreateResponse: Codable, Sendable {
    public struct DataBody: Codable, Sendable {
        public let qrurl: String
        public let qrimg: String
    }
    public let data: DataBody
    public let code: Int
}

public struct NeteaseQrCheckResponse: Codable, Sendable {
    public let code: Int
    public let message: String?
    public let cookie: String?
}

public struct NeteaseLoginStatusResponse: Codable, Sendable {
    public struct DataBody: Codable, Sendable {
        public let code: Int
        public let profile: NeteaseUserProfile?
    }
    public let data: DataBody
}

public struct NeteaseCellphoneLoginResponse: Codable, Sendable {
    public let code: Int
    public let cookie: String?
    public let profile: NeteaseUserProfile?
    public let message: String?
}

public struct NeteaseFreeTrialInfo: Codable, Sendable {
    public let fragmentType: Int?
    public let start: Int?
    public let end: Int?

    public init(fragmentType: Int? = nil, start: Int? = nil, end: Int? = nil) {
        self.fragmentType = fragmentType
        self.start = start
        self.end = end
    }
}

public struct NeteaseSongUrlItem: Codable, Sendable, Identifiable {
    public let id: Int
    public let url: String?
    public let br: Int?
    public let size: Int?
    public let level: String?
    public let fee: Int?
    public let type: String?
    public let freeTrialInfo: NeteaseFreeTrialInfo?

    public var securePlaybackURLString: String? {
        guard let url, !url.isEmpty else { return nil }
        if url.hasPrefix("http://") {
            return "https://" + url.dropFirst("http://".count)
        }
        return url
    }

    public var isPlayable: Bool {
        guard let url, !url.isEmpty else { return false }
        return true
    }

    public var isFreeTrial: Bool {
        freeTrialInfo != nil
    }

    public init(
        id: Int,
        url: String?,
        br: Int? = nil,
        size: Int? = nil,
        level: String? = nil,
        fee: Int? = nil,
        type: String? = nil,
        freeTrialInfo: NeteaseFreeTrialInfo? = nil
    ) {
        self.id = id
        self.url = url
        self.br = br
        self.size = size
        self.level = level
        self.fee = fee
        self.type = type
        self.freeTrialInfo = freeTrialInfo
    }
}

public struct NeteaseSongUrlResponse: Codable, Sendable {
    public let code: Int
    public let data: [NeteaseSongUrlItem]
}

public struct NeteaseTokenContributeRequest: Codable, Sendable {
    public let cookie: String
    public let nickname: String?

    public init(cookie: String, nickname: String? = nil) {
        self.cookie = cookie
        self.nickname = nickname
    }
}

public struct NeteaseTokenContributeResponse: Codable, Sendable {
    public let code: Int
    public let status: String
    public let message: String

    public init(code: Int, status: String, message: String) {
        self.code = code
        self.status = status
        self.message = message
    }
}

