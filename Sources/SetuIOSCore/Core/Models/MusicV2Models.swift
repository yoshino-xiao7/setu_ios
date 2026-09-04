import Foundation

// MARK: - Wire primitives

/// A required-but-nullable JSON member. Unlike an Optional synthesized by Codable,
/// a missing key fails decoding while an explicit `null` is preserved as nil.
@propertyWrapper
public struct MusicV2RequiredNullable<Value: Decodable & Hashable & Sendable>: Decodable, Hashable, Sendable {
    public var wrappedValue: Value?

    public init(wrappedValue: Value?) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = container.decodeNil() ? nil : try container.decode(Value.self)
    }

}

extension MusicV2RequiredNullable: Encodable where Value: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue {
            try container.encode(wrappedValue)
        } else {
            try container.encodeNil()
        }
    }
}

public protocol MusicV2OpaqueID: Codable, Hashable, Sendable, RawRepresentable where RawValue == String {
    init(rawValue: String)
}

public extension MusicV2OpaqueID {
    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct MusicV2TrackID: MusicV2OpaqueID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct MusicV2ArtistID: MusicV2OpaqueID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct MusicV2AlbumID: MusicV2OpaqueID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct MusicV2MvID: MusicV2OpaqueID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct MusicV2ProviderPlaylistID: MusicV2OpaqueID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct MusicV2SetuPlaylistID: MusicV2OpaqueID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct MusicV2PlaylistRelationID: MusicV2OpaqueID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct MusicV2SetuUserID: MusicV2OpaqueID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }
public struct MusicV2ProviderUserID: MusicV2OpaqueID { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue } }

public enum MusicV2PlaylistID: Codable, Hashable, Sendable {
    case provider(MusicV2ProviderPlaylistID)
    case local(MusicV2SetuPlaylistID)
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .provider(let id): id.rawValue
        case .local(let id): id.rawValue
        case .unknown(let raw): raw
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw.hasPrefix("netease:playlist:") { self = .provider(.init(rawValue: raw)) }
        else if raw.hasPrefix("setu:playlist:") { self = .local(.init(rawValue: raw)) }
        else { self = .unknown(raw) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum MusicV2CreatorID: Codable, Hashable, Sendable {
    case setu(MusicV2SetuUserID), provider(MusicV2ProviderUserID), unknown(String)
    public var rawValue: String { switch self { case .setu(let id): id.rawValue; case .provider(let id): id.rawValue; case .unknown(let raw): raw } }
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw.hasPrefix("setu:user:") { self = .setu(.init(rawValue: raw)) }
        else if raw.hasPrefix("netease:creator:") { self = .provider(.init(rawValue: raw)) }
        else { self = .unknown(raw) }
    }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}

public enum MusicV2PlaylistOrigin: String, Codable, Hashable, Sendable { case provider, local }

public struct MusicV2RequiredNull: Codable, Hashable, Sendable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard container.decodeNil() else {
            throw DecodingError.typeMismatch(Self.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected required null"))
        }
    }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encodeNil() }
}

public enum MusicV2PlaybackQuality: Codable, Hashable, Sendable {
    case standard, higher, exhigh, lossless, hires
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .standard: "standard"
        case .higher: "higher"
        case .exhigh: "exhigh"
        case .lossless: "lossless"
        case .hires: "hires"
        case .unknown(let raw): raw
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = switch raw {
        case "standard": .standard; case "higher": .higher; case "exhigh": .exhigh
        case "lossless": .lossless; case "hires": .hires; default: .unknown(raw)
        }
    }

    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}

public enum MusicV2PlaybackMode: Codable, Hashable, Sendable {
    case sequence, loop, single, random
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .sequence: "sequence"; case .loop: "loop"; case .single: "single"; case .random: "random"
        case .unknown(let raw): raw
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = switch raw {
        case "sequence": .sequence; case "loop": .loop; case "single": .single; case "random": .random
        default: .unknown(raw)
        }
    }

    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}

public enum MusicV2SearchScope: String, Codable, CaseIterable, Sendable {
    case all, tracks, artists, albums, playlists, mvs
}

public enum MusicV2Area: String, Codable, CaseIterable, Sendable { case all, zh, ea, jp, kr }

// MARK: - Catalog

public struct MusicV2Artwork: Codable, Hashable, Sendable { public let url: String }

public struct MusicV2ArtistBrief: Codable, Hashable, Sendable {
    public let name: String
    @MusicV2RequiredNullable public var id: MusicV2ArtistID?
    @MusicV2RequiredNullable public var artwork: MusicV2Artwork?
}

public struct MusicV2AlbumBrief: Codable, Hashable, Sendable {
    public let title: String
    @MusicV2RequiredNullable public var id: MusicV2AlbumID?
    @MusicV2RequiredNullable public var artwork: MusicV2Artwork?
}

public struct MusicV2CreatorBrief: Codable, Hashable, Sendable {
    @MusicV2RequiredNullable public var identity: MusicV2CreatorID?
    public let displayName: String
    @MusicV2RequiredNullable public var avatar: MusicV2Artwork?
}

public enum MusicV2AvailabilityStatus: Codable, Hashable, Sendable {
    case unknown, playable, vipOnly, trialOnly, unavailable, regionBlocked
    case unrecognized(String)

    public var rawValue: String {
        switch self {
        case .unknown: "unknown"; case .playable: "playable"; case .vipOnly: "vipOnly"
        case .trialOnly: "trialOnly"; case .unavailable: "unavailable"; case .regionBlocked: "regionBlocked"
        case .unrecognized(let raw): raw
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = switch raw {
        case "unknown": .unknown; case "playable": .playable; case "vipOnly": .vipOnly
        case "trialOnly": .trialOnly; case "unavailable": .unavailable; case "regionBlocked": .regionBlocked
        default: .unrecognized(raw)
        }
    }

    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}

public struct MusicV2TrackAvailability: Codable, Hashable, Sendable {
    public let status: MusicV2AvailabilityStatus
    @MusicV2RequiredNullable public var reason: String?
    @MusicV2RequiredNullable public var maxQuality: MusicV2PlaybackQuality?
}

public struct MusicV2Track: Codable, Hashable, Sendable {
    public let id: MusicV2TrackID
    public let source: String
    public let title: String
    public let artists: [MusicV2ArtistBrief]
    public let availability: MusicV2TrackAvailability
    @MusicV2RequiredNullable public var album: MusicV2AlbumBrief?
    @MusicV2RequiredNullable public var durationMs: Int?
    @MusicV2RequiredNullable public var artwork: MusicV2Artwork?
    @MusicV2RequiredNullable public var mvId: MusicV2MvID?
    public let aliases: [String]
    @MusicV2RequiredNullable public var translatedTitle: String?
}

public struct MusicV2Artist: Codable, Hashable, Sendable {
    public let id: MusicV2ArtistID
    public let source: String
    public let name: String
    public let aliases: [String]
    @MusicV2RequiredNullable public var artwork: MusicV2Artwork?
    @MusicV2RequiredNullable public var description: String?
    @MusicV2RequiredNullable public var trackCount: Int?
    @MusicV2RequiredNullable public var albumCount: Int?
    @MusicV2RequiredNullable public var mvCount: Int?
}

public struct MusicV2Album: Codable, Hashable, Sendable {
    public let id: MusicV2AlbumID
    public let source: String
    public let title: String
    public let artists: [MusicV2ArtistBrief]
    @MusicV2RequiredNullable public var artwork: MusicV2Artwork?
    @MusicV2RequiredNullable public var releaseDate: String?
    @MusicV2RequiredNullable public var trackCount: Int?
    @MusicV2RequiredNullable public var company: String?
    @MusicV2RequiredNullable public var description: String?
    @MusicV2RequiredNullable public var editionLabel: String?
}

public struct MusicV2MvBrief: Codable, Hashable, Sendable {
    public let id: MusicV2MvID
    public let title: String
    public let artists: [MusicV2ArtistBrief]
    @MusicV2RequiredNullable public var artwork: MusicV2Artwork?
    @MusicV2RequiredNullable public var durationMs: Int?
    @MusicV2RequiredNullable public var playCount: Int?
}

public struct MusicV2ProviderPlaylist: Codable, Hashable, Sendable {
    public let id: MusicV2ProviderPlaylistID
    public let origin: MusicV2PlaylistOrigin
    public let title: String
    public let tags: [String]
    public let isRanking: Bool
    @MusicV2RequiredNullable public var artwork: MusicV2Artwork?
    @MusicV2RequiredNullable public var description: String?
    @MusicV2RequiredNullable public var trackCount: Int?
    @MusicV2RequiredNullable public var playCount: Int?
    @MusicV2RequiredNullable public var creator: MusicV2CreatorBrief?
    @MusicV2RequiredNullable public var updatedAt: String?
    @MusicV2RequiredNullable public var updateFrequency: String?
}

public struct MusicV2LocalPlaylist: Codable, Hashable, Sendable {
    public let id: MusicV2SetuPlaylistID
    public let origin: MusicV2PlaylistOrigin
    public let title: String
    public let tags: [String]
    public let isRanking: Bool
    @MusicV2RequiredNullable public var artwork: MusicV2Artwork?
    @MusicV2RequiredNullable public var description: String?
    @MusicV2RequiredNullable public var trackCount: Int?
    @MusicV2RequiredNullable public var playCount: Int?
    @MusicV2RequiredNullable public var creator: MusicV2CreatorBrief?
    @MusicV2RequiredNullable public var updatedAt: String?
    @MusicV2RequiredNullable public var updateFrequency: String?
    public let ownerId: MusicV2SetuUserID
    public let visibility: String
    public let defaultPlaybackMode: MusicV2PlaybackMode
    public let createdAt: String
}

public enum MusicV2Playlist: Codable, Hashable, Sendable {
    case provider(MusicV2ProviderPlaylist)
    case local(MusicV2LocalPlaylist)

    private enum CodingKeys: String, CodingKey { case origin }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(MusicV2PlaylistOrigin.self, forKey: .origin) {
        case .provider: self = .provider(try MusicV2ProviderPlaylist(from: decoder))
        case .local: self = .local(try MusicV2LocalPlaylist(from: decoder))
        }
    }
    public func encode(to encoder: Encoder) throws {
        switch self { case .provider(let value): try value.encode(to: encoder); case .local(let value): try value.encode(to: encoder) }
    }
}

public struct MusicV2ProviderMembership: Codable, Hashable, Sendable {
    public let playlistId: MusicV2ProviderPlaylistID
    public let trackId: MusicV2TrackID
    public let position: Int
    @MusicV2RequiredNullable public var track: MusicV2Track?
    public let relationId: MusicV2RequiredNull
    @MusicV2RequiredNullable public var addedAt: String?
}

public struct MusicV2LocalMembership: Codable, Hashable, Sendable {
    public let playlistId: MusicV2SetuPlaylistID
    public let trackId: MusicV2TrackID
    public let position: Int
    @MusicV2RequiredNullable public var track: MusicV2Track?
    public let relationId: MusicV2PlaylistRelationID
    public let addedAt: String
}

public enum MusicV2PlaylistTrack: Codable, Hashable, Sendable {
    case provider(MusicV2ProviderMembership)
    case local(MusicV2LocalMembership)

    private enum CodingKeys: String, CodingKey { case playlistId }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .playlistId)
        if id.hasPrefix("netease:playlist:") { self = .provider(try MusicV2ProviderMembership(from: decoder)) }
        else if id.hasPrefix("setu:playlist:") { self = .local(try MusicV2LocalMembership(from: decoder)) }
        else { throw DecodingError.dataCorruptedError(forKey: .playlistId, in: container, debugDescription: "Unknown playlist identity domain") }
    }
    public func encode(to encoder: Encoder) throws {
        switch self { case .provider(let value): try value.encode(to: encoder); case .local(let value): try value.encode(to: encoder) }
    }
}

public struct MusicV2Page<Item: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public let items: [Item]
    public let offset: Int
    public let limit: Int
    public let hasMore: Bool
    @MusicV2RequiredNullable public var total: Int?
    @MusicV2RequiredNullable public var nextOffset: Int?
}

public struct MusicV2ExactPage<Item: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public let items: [Item]
    public let offset: Int
    public let limit: Int
    public let hasMore: Bool
    public let total: Int
    @MusicV2RequiredNullable public var nextOffset: Int?
}

public typealias MusicV2TrackPage = MusicV2Page<MusicV2Track>
public typealias MusicV2ArtistPage = MusicV2Page<MusicV2Artist>
public typealias MusicV2AlbumPage = MusicV2Page<MusicV2Album>
public typealias MusicV2PlaylistPage = MusicV2Page<MusicV2ProviderPlaylist>
public typealias MusicV2MvPage = MusicV2Page<MusicV2MvBrief>
public typealias MusicV2MembershipPage = MusicV2Page<MusicV2PlaylistTrack>

public struct MusicV2ArtistDetail: Codable, Hashable, Sendable {
    public let artist: MusicV2Artist
    public let topTracks: [MusicV2Track]
    public let albums: [MusicV2AlbumBrief]
    public let mvs: [MusicV2MvBrief]
    public let similar: [MusicV2ArtistBrief]
}
public struct MusicV2AlbumDetail: Codable, Hashable, Sendable { public let album: MusicV2Album; public let tracks: [MusicV2Track] }
public struct MusicV2PlaylistDetail: Codable, Hashable, Sendable { public let playlist: MusicV2Playlist; public let memberships: MusicV2MembershipPage }
public struct MusicV2TrackBatch: Codable, Hashable, Sendable { public let items: [MusicV2Track] }

// MARK: - Error and playback

public enum MusicV2ErrorCode: Codable, Hashable, Sendable {
    case upstreamUnavailable, upstreamAuthInvalid, upstreamRateLimited, resourceNotFound
    case trackNotPlayable, invalidRequest, unauthorized, forbidden, rateLimited, internalError
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .upstreamUnavailable: "UPSTREAM_UNAVAILABLE"; case .upstreamAuthInvalid: "UPSTREAM_AUTH_INVALID"
        case .upstreamRateLimited: "UPSTREAM_RATE_LIMITED"; case .resourceNotFound: "RESOURCE_NOT_FOUND"
        case .trackNotPlayable: "TRACK_NOT_PLAYABLE"; case .invalidRequest: "INVALID_REQUEST"
        case .unauthorized: "UNAUTHORIZED"; case .forbidden: "FORBIDDEN"; case .rateLimited: "RATE_LIMITED"
        case .internalError: "INTERNAL"; case .unknown(let raw): raw
        }
    }

    public init(rawValue: String) {
        self = switch rawValue {
        case "UPSTREAM_UNAVAILABLE": .upstreamUnavailable; case "UPSTREAM_AUTH_INVALID": .upstreamAuthInvalid
        case "UPSTREAM_RATE_LIMITED": .upstreamRateLimited; case "RESOURCE_NOT_FOUND": .resourceNotFound
        case "TRACK_NOT_PLAYABLE": .trackNotPlayable; case "INVALID_REQUEST": .invalidRequest
        case "UNAUTHORIZED": .unauthorized; case "FORBIDDEN": .forbidden; case "RATE_LIMITED": .rateLimited
        case "INTERNAL": .internalError; default: .unknown(rawValue)
        }
    }
    public init(from decoder: Decoder) throws { self.init(rawValue: try decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}

public struct MusicV2Error: Codable, Hashable, Sendable {
    public let code: MusicV2ErrorCode
    public let message: String
    public let retryable: Bool
    @MusicV2RequiredNullable public var traceId: String?
}

public struct MusicV2PlaybackSource: Codable, Hashable, Sendable {
    public let trackId: MusicV2TrackID
    public let url: String
    public let requestedQuality: MusicV2PlaybackQuality
    @MusicV2RequiredNullable public var actualQuality: MusicV2PlaybackQuality?
    public let expiresAt: String
    @MusicV2RequiredNullable public var bitrate: Int?
    @MusicV2RequiredNullable public var sizeBytes: Int?
    @MusicV2RequiredNullable public var format: String?
    @MusicV2RequiredNullable public var notice: String?
}

public enum MusicV2PlaybackResolution: Codable, Hashable, Sendable {
    case success(MusicV2PlaybackSource)
    case denied(trackId: MusicV2TrackID, availability: MusicV2TrackAvailability)
    case failure(trackId: MusicV2TrackID, error: MusicV2Error)
    case unsupported(kind: String)

    private enum CodingKeys: String, CodingKey { case kind, source, trackId, availability, error }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "success": self = .success(try c.decode(MusicV2PlaybackSource.self, forKey: .source))
        case "denied": self = .denied(trackId: try c.decode(MusicV2TrackID.self, forKey: .trackId), availability: try c.decode(MusicV2TrackAvailability.self, forKey: .availability))
        case "failure": self = .failure(trackId: try c.decode(MusicV2TrackID.self, forKey: .trackId), error: try c.decode(MusicV2Error.self, forKey: .error))
        default: self = .unsupported(kind: kind)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .success(let source): try c.encode("success", forKey: .kind); try c.encode(source, forKey: .source)
        case .denied(let id, let availability): try c.encode("denied", forKey: .kind); try c.encode(id, forKey: .trackId); try c.encode(availability, forKey: .availability)
        case .failure(let id, let error): try c.encode("failure", forKey: .kind); try c.encode(id, forKey: .trackId); try c.encode(error, forKey: .error)
        case .unsupported(let kind): try c.encode(kind, forKey: .kind)
        }
    }
}

public struct MusicV2PlaybackBatch: Codable, Hashable, Sendable { public let items: [MusicV2PlaybackResolution] }

// MARK: - Lyrics

public struct MusicV2LyricWord: Codable, Hashable, Sendable { public let text: String; public let startMs: Int; public let durationMs: Int }
public struct MusicV2LyricLine: Codable, Hashable, Sendable {
    public let text: String
    public let words: [MusicV2LyricWord]
    @MusicV2RequiredNullable public var startMs: Int?
    @MusicV2RequiredNullable public var durationMs: Int?
    @MusicV2RequiredNullable public var translation: String?
}
public struct MusicV2Lyric: Codable, Hashable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        case none, plain, line, word, unknown(String)
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = switch raw { case "none": .none; case "plain": .plain; case "line": .line; case "word": .word; default: .unknown(raw) }
        }
        public func encode(to encoder: Encoder) throws {
            let raw = switch self { case .none: "none"; case .plain: "plain"; case .line: "line"; case .word: "word"; case .unknown(let raw): raw }
            var c = encoder.singleValueContainer(); try c.encode(raw)
        }
    }
    public let trackId: MusicV2TrackID
    public let kind: Kind
    public let lines: [MusicV2LyricLine]
    public let hasTranslation: Bool
    public let contributors: [String]
}

// MARK: - Discovery and search

public struct MusicV2DiscoverySource: Codable, Hashable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        case editorial, curated, sharedAlgorithmic, ranking, newRelease, historyDerived, personalized, unknown(String)
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = switch raw {
            case "editorial": .editorial; case "curated": .curated; case "sharedAlgorithmic": .sharedAlgorithmic
            case "ranking": .ranking; case "newRelease": .newRelease; case "historyDerived": .historyDerived
            case "personalized": .personalized; default: .unknown(raw)
            }
        }
        public func encode(to encoder: Encoder) throws {
            let raw = switch self { case .editorial: "editorial"; case .curated: "curated"; case .sharedAlgorithmic: "sharedAlgorithmic"; case .ranking: "ranking"; case .newRelease: "newRelease"; case .historyDerived: "historyDerived"; case .personalized: "personalized"; case .unknown(let raw): raw }
            var c = encoder.singleValueContainer(); try c.encode(raw)
        }
    }
    public let kind: Kind
    public let audience: String
    public let personalized: Bool
    @MusicV2RequiredNullable public var catalogSource: String?
    @MusicV2RequiredNullable public var label: String?
    @MusicV2RequiredNullable public var ownerId: MusicV2SetuUserID?
}

public enum MusicV2ResourceRef: Codable, Hashable, Sendable {
    case track(MusicV2TrackID), artist(MusicV2ArtistID), album(MusicV2AlbumID), playlist(MusicV2PlaylistID), mv(MusicV2MvID)
    case unknown(String)
    private enum CodingKeys: String, CodingKey { case kind, id }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self); let kind = try c.decode(String.self, forKey: .kind)
        self = switch kind {
        case "track": .track(try c.decode(MusicV2TrackID.self, forKey: .id)); case "artist": .artist(try c.decode(MusicV2ArtistID.self, forKey: .id))
        case "album": .album(try c.decode(MusicV2AlbumID.self, forKey: .id)); case "playlist": .playlist(try c.decode(MusicV2PlaylistID.self, forKey: .id))
        case "mv": .mv(try c.decode(MusicV2MvID.self, forKey: .id)); default: .unknown(kind)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .track(let id): try c.encode("track", forKey: .kind); try c.encode(id, forKey: .id)
        case .artist(let id): try c.encode("artist", forKey: .kind); try c.encode(id, forKey: .id)
        case .album(let id): try c.encode("album", forKey: .kind); try c.encode(id, forKey: .id)
        case .playlist(let id): try c.encode("playlist", forKey: .kind); try c.encode(id, forKey: .id)
        case .mv(let id): try c.encode("mv", forKey: .kind); try c.encode(id, forKey: .id)
        case .unknown(let kind): try c.encode(kind, forKey: .kind)
        }
    }
}

public enum MusicV2SearchSection: Codable, Hashable, Sendable {
    case tracks(MusicV2TrackPage), artists(MusicV2ArtistPage), albums(MusicV2AlbumPage), playlists(MusicV2PlaylistPage), mvs(MusicV2MvPage)
    case failed(scope: MusicV2SearchScope, error: MusicV2Error)
    case unknown(scope: String, status: String)
    private enum CodingKeys: String, CodingKey { case scope, status, items, error }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let scopeRaw = try c.decode(String.self, forKey: .scope), status = try c.decode(String.self, forKey: .status)
        guard let scope = MusicV2SearchScope(rawValue: scopeRaw), scope != .all else { self = .unknown(scope: scopeRaw, status: status); return }
        if status == "failed" { self = .failed(scope: scope, error: try c.decode(MusicV2Error.self, forKey: .error)); return }
        guard status == "loaded" else { self = .unknown(scope: scopeRaw, status: status); return }
        self = switch scope {
        case .tracks: .tracks(try c.decode(MusicV2TrackPage.self, forKey: .items))
        case .artists: .artists(try c.decode(MusicV2ArtistPage.self, forKey: .items))
        case .albums: .albums(try c.decode(MusicV2AlbumPage.self, forKey: .items))
        case .playlists: .playlists(try c.decode(MusicV2PlaylistPage.self, forKey: .items))
        case .mvs: .mvs(try c.decode(MusicV2MvPage.self, forKey: .items))
        case .all: .unknown(scope: scopeRaw, status: status)
        }
    }
    public func encode(to encoder: Encoder) throws { throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath, debugDescription: "Response-only union")) }
}

public struct MusicV2SearchResult: Decodable, Hashable, Sendable {
    public let query: String
    public let scope: MusicV2SearchScope
    public let sections: [MusicV2SearchSection]
    @MusicV2RequiredNullable public var best: MusicV2ResourceRef?

    private enum CodingKeys: String, CodingKey { case query, scope, sections, best }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        query = try c.decode(String.self, forKey: .query); scope = try c.decode(MusicV2SearchScope.self, forKey: .scope)
        sections = try c.decode([MusicV2SearchSection].self, forKey: .sections).filter { if case .unknown = $0 { false } else { true } }
        _best = try c.decode(MusicV2RequiredNullable<MusicV2ResourceRef>.self, forKey: .best)
    }
}

public struct MusicV2SearchSuggestions: Codable, Hashable, Sendable { public let keywords: [String]; public let tracks: [MusicV2Track]; public let artists: [MusicV2ArtistBrief]; public let playlists: [MusicV2ProviderPlaylist] }
public struct MusicV2HotKeyword: Codable, Hashable, Sendable { public let query: String; @MusicV2RequiredNullable public var rank: Int? }
public struct MusicV2HotSearch: Codable, Hashable, Sendable { public let items: [MusicV2HotKeyword]; public let source: MusicV2DiscoverySource }
public struct MusicV2SimilarTracks: Codable, Hashable, Sendable { public let tracks: [MusicV2Track]; public let playlists: [MusicV2ProviderPlaylist]; public let source: MusicV2DiscoverySource }

// MARK: - Home

public enum MusicV2HomeAction: Decodable, Hashable, Sendable {
    case resource(ref: MusicV2ResourceRef, label: String?)
    case discovery(selection: String, label: String?)
    case library(collection: String, label: String?)
    case search(query: String, label: String?)
    case disabled(kind: String)
    private enum CodingKeys: String, CodingKey { case kind, ref, selection, collection, query, label }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self); let kind = try c.decode(String.self, forKey: .kind)
        let label = try c.decode(MusicV2RequiredNullable<String>.self, forKey: .label).wrappedValue
        switch kind {
        case "resource": self = .resource(ref: try c.decode(MusicV2ResourceRef.self, forKey: .ref), label: label)
        case "discovery":
            let selection = try c.decode(String.self, forKey: .selection)
            self = ["dailyTracks", "recommendedPlaylists", "newTracks", "newAlbums", "rankings", "radio"].contains(selection)
                ? .discovery(selection: selection, label: label) : .disabled(kind: "discovery:\(selection)")
        case "library":
            let collection = try c.decode(String.self, forKey: .collection)
            self = ["liked", "history", "savedPlaylists"].contains(collection)
                ? .library(collection: collection, label: label) : .disabled(kind: "library:\(collection)")
        case "search": self = .search(query: try c.decode(String.self, forKey: .query), label: label)
        default: self = .disabled(kind: kind)
        }
    }
}

public enum MusicV2HomeItem: Decodable, Hashable, Sendable {
    case track(MusicV2Track), playlist(MusicV2Playlist), album(MusicV2Album)
    case keyword(query: String, rank: Int?)
    case entry(key: String, title: String, action: MusicV2HomeAction, count: Int?)
    case unknown(String)
    private enum CodingKeys: String, CodingKey { case kind, track, playlist, album, query, rank, key, title, action, count }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self), kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "track": self = .track(try c.decode(MusicV2Track.self, forKey: .track))
        case "playlist": self = .playlist(try c.decode(MusicV2Playlist.self, forKey: .playlist))
        case "album": self = .album(try c.decode(MusicV2Album.self, forKey: .album))
        case "keyword": self = .keyword(query: try c.decode(String.self, forKey: .query), rank: try c.decode(MusicV2RequiredNullable<Int>.self, forKey: .rank).wrappedValue)
        case "entry":
            let key = try c.decode(String.self, forKey: .key)
            guard ["dailyTracks", "radio", "rankings", "liked"].contains(key) else { self = .unknown("entry:\(key)"); return }
            self = .entry(key: key, title: try c.decode(String.self, forKey: .title), action: try c.decode(MusicV2HomeAction.self, forKey: .action), count: try c.decode(MusicV2RequiredNullable<Int>.self, forKey: .count).wrappedValue)
        default: self = .unknown(kind)
        }
    }
}

public struct MusicV2HomeSection: Decodable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case quickEntries, dailyTracks, recommendedPlaylists, newTracks, newAlbums, rankings, hotSearch, continueListening, favoritePlaylists }
    public let id: String
    public let kind: Kind
    public let title: String
    public let items: [MusicV2HomeItem]
    public let degraded: Bool
    @MusicV2RequiredNullable public var subtitle: String?
    @MusicV2RequiredNullable public var source: MusicV2DiscoverySource?
    @MusicV2RequiredNullable public var action: MusicV2HomeAction?

    private enum CodingKeys: String, CodingKey { case id, kind, title, items, degraded, subtitle, source, action }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        title = try c.decode(String.self, forKey: .title)
        degraded = try c.decode(Bool.self, forKey: .degraded)
        _subtitle = try c.decode(MusicV2RequiredNullable<String>.self, forKey: .subtitle)
        _source = try c.decode(MusicV2RequiredNullable<MusicV2DiscoverySource>.self, forKey: .source)
        _action = try c.decode(MusicV2RequiredNullable<MusicV2HomeAction>.self, forKey: .action)
        let rawItems = try c.decode([MusicV2HomeItem].self, forKey: .items)
        var known: [MusicV2HomeItem] = []
        for item in rawItems {
            if case .unknown = item { continue }
            guard Self.accepts(item, in: kind) else {
                throw DecodingError.dataCorruptedError(forKey: .items, in: c, debugDescription: "Home item discriminator does not match section kind")
            }
            known.append(item)
        }
        items = known
        let mustHaveSource = ![Kind.quickEntries, .continueListening, .favoritePlaylists].contains(kind)
        guard mustHaveSource == (source != nil) else {
            throw DecodingError.dataCorruptedError(forKey: .source, in: c, debugDescription: "Home section source does not match section kind")
        }
    }

    private static func accepts(_ item: MusicV2HomeItem, in kind: Kind) -> Bool {
        switch (kind, item) {
        case (.quickEntries, .entry), (.dailyTracks, .track), (.recommendedPlaylists, .playlist),
             (.newTracks, .track), (.newAlbums, .album), (.rankings, .playlist),
             (.hotSearch, .keyword), (.continueListening, .track), (.favoritePlaylists, .playlist): true
        default: false
        }
    }
}

public struct MusicV2HomeFeed: Decodable, Hashable, Sendable {
    public let sections: [MusicV2HomeSection]
    public let generatedAt: String
    private enum CodingKeys: String, CodingKey { case sections, generatedAt }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try c.decode(String.self, forKey: .generatedAt)
        var values = try c.nestedUnkeyedContainer(forKey: .sections), decoded: [MusicV2HomeSection] = []
        while !values.isAtEnd {
            let probe = try values.superDecoder()
            let keyed = try probe.container(keyedBy: DynamicCodingKey.self)
            let raw = try keyed.decode(String.self, forKey: .init("kind"))
            guard MusicV2HomeSection.Kind(rawValue: raw) != nil else { continue }
            decoded.append(try MusicV2HomeSection(from: probe))
        }
        sections = decoded
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String; let intValue: Int? = nil
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}

public struct MusicV2Rankings: Codable, Hashable, Sendable { public let items: [MusicV2ProviderPlaylist]; public let source: MusicV2DiscoverySource }
public struct MusicV2RecommendedTracks: Codable, Hashable, Sendable { public let tracks: [MusicV2Track]; public let source: MusicV2DiscoverySource }
public struct MusicV2RecommendedPlaylists: Codable, Hashable, Sendable { public let items: [MusicV2ProviderPlaylist]; public let source: MusicV2DiscoverySource }
public struct MusicV2RadioBatch: Codable, Hashable, Sendable { public let tracks: [MusicV2Track]; public let source: MusicV2DiscoverySource }
public struct MusicV2NewTracks: Codable, Hashable, Sendable { public let area: MusicV2Area; public let items: MusicV2TrackPage; public let source: MusicV2DiscoverySource }
public struct MusicV2NewAlbums: Codable, Hashable, Sendable { public let area: MusicV2Area; public let items: MusicV2AlbumPage; public let source: MusicV2DiscoverySource }

// MARK: - User library and write projections

public struct MusicV2LikedTrack: Codable, Hashable, Sendable { public let ownerId: MusicV2SetuUserID; public let trackId: MusicV2TrackID; public let likedAt: String; @MusicV2RequiredNullable public var track: MusicV2Track? }
public struct MusicV2SavedPlaylist: Codable, Hashable, Sendable { public let ownerId: MusicV2SetuUserID; public let playlistId: MusicV2ProviderPlaylistID; public let savedAt: String; @MusicV2RequiredNullable public var playlist: MusicV2ProviderPlaylist? }
public struct MusicV2PlaybackHistoryEntry: Codable, Hashable, Sendable { public let ownerId: MusicV2SetuUserID; public let trackId: MusicV2TrackID; public let lastPlayedAt: String; @MusicV2RequiredNullable public var track: MusicV2Track? }
public typealias MusicV2LikedPage = MusicV2ExactPage<MusicV2LikedTrack>
public typealias MusicV2SavedPage = MusicV2ExactPage<MusicV2SavedPlaylist>
public typealias MusicV2HistoryPage = MusicV2ExactPage<MusicV2PlaybackHistoryEntry>

public struct MusicV2UserLibrary: Codable, Hashable, Sendable {
    public let ownerId: MusicV2SetuUserID
    public let likedTrackCount: Int
    public let savedPlaylistCount: Int
    public let historyCount: Int
    public let ownedPlaylistCount: Int
    public let recentHistory: [MusicV2PlaybackHistoryEntry]
    public let ownedPlaylists: [MusicV2LocalPlaylist]
    public let savedPlaylists: [MusicV2SavedPlaylist]
}

public struct MusicV2TrackDisplaySnapshot: Codable, Hashable, Sendable {
    public let title: String
    public let artists: [MusicV2ArtistBrief]
    @MusicV2RequiredNullable public var album: MusicV2AlbumBrief?
    @MusicV2RequiredNullable public var durationMs: Int?
    @MusicV2RequiredNullable public var artwork: MusicV2Artwork?
    @MusicV2RequiredNullable public var mvId: MusicV2MvID?
    public let aliases: [String]
    @MusicV2RequiredNullable public var translatedTitle: String?
}
public struct MusicV2PlaylistDisplaySnapshot: Codable, Hashable, Sendable {
    public let title: String
    @MusicV2RequiredNullable public var artwork: MusicV2Artwork?
    @MusicV2RequiredNullable public var trackCount: Int?
    @MusicV2RequiredNullable public var creator: MusicV2CreatorBrief?
}
public struct MusicV2LikeRequest: Codable, Sendable { public let snapshot: MusicV2TrackDisplaySnapshot?; public init(snapshot: MusicV2TrackDisplaySnapshot? = nil) { self.snapshot = snapshot } }
public struct MusicV2SaveRequest: Codable, Sendable { public let snapshot: MusicV2PlaylistDisplaySnapshot?; public init(snapshot: MusicV2PlaylistDisplaySnapshot? = nil) { self.snapshot = snapshot } }
public struct MusicV2HistoryRequest: Codable, Sendable { public let trackId: MusicV2TrackID; public let snapshot: MusicV2TrackDisplaySnapshot?; public init(trackId: MusicV2TrackID, snapshot: MusicV2TrackDisplaySnapshot? = nil) { self.trackId = trackId; self.snapshot = snapshot } }
public struct MusicV2FMBlockRequest: Codable, Sendable { public let trackId: MusicV2TrackID; public init(trackId: MusicV2TrackID) { self.trackId = trackId } }
