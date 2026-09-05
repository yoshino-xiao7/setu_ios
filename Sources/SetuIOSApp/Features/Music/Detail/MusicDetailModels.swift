import Foundation
import SetuIOSCore

struct MusicPlaylistDetailData: Sendable {
    let playlist: MusicV2Playlist
    private(set) var memberships: [MusicV2PlaylistTrack]
    private(set) var tracks: [MusicV2Track]
    private(set) var nextOffset: Int?
    private(set) var loadedOffsets: Set<Int>
    let title: String
    let description: String?
    let artwork: String?
    let context: PlaybackContext

    init(_ detail: MusicV2PlaylistDetail) {
        playlist = detail.playlist; memberships = detail.memberships.items
        loadedOffsets = [detail.memberships.offset]
        tracks = detail.memberships.items.compactMap(\.projectedTrack)
        nextOffset = detail.memberships.hasMore ? detail.memberships.nextOffset : nil
        switch detail.playlist {
        case .provider(let value):
            title = value.title; description = value.description; artwork = value.artwork?.url
            context = .playlist(id: .provider(.canonical(.init(rawValue: value.id.rawValue))), label: value.title)
        case .local(let value):
            title = value.title; description = value.description; artwork = value.artwork?.url
            context = .playlist(id: .local(.canonical(.init(rawValue: value.id.rawValue))), label: value.title)
        }
    }
    mutating func append(_ page: MusicV2MembershipPage) {
        // Preserve provider order and null projections; relation removal never uses TrackId.
        loadedOffsets.insert(page.offset)
        memberships.append(contentsOf: page.items)
        tracks.append(contentsOf: page.items.compactMap(\.projectedTrack))
        nextOffset = page.hasMore ? page.nextOffset : nil
    }
    func ownedLocal(by userID: Int?) -> MusicV2LocalPlaylist? {
        guard case .local(let value) = playlist, let userID,
              value.ownerId.rawValue == "setu:user:\(userID)" else { return nil }
        return value
    }
}

extension MusicV2PlaylistTrack {
    var projectedTrack: MusicV2Track? {
        switch self { case .local(let value): value.track; case .provider(let value): value.track }
    }
    var position: Int { switch self { case .local(let value): value.position; case .provider(let value): value.position } }
    var trackID: MusicV2TrackID { switch self { case .local(let value): value.trackId; case .provider(let value): value.trackId } }
}

/// Only the documented Setu legacy bridge accepts decimal DB paths. No TrackId participates.
enum MusicLocalPlaylistBridge {
    static func path(_ id: MusicV2SetuPlaylistID) throws -> String { try decimalPath(id.rawValue, prefix: "setu:playlist:") }
    static func path(_ id: MusicV2PlaylistRelationID) throws -> String { try decimalPath(id.rawValue, prefix: "setu:playlistMembership:") }
    private static func decimalPath(_ raw: String, prefix: String) throws -> String {
        guard raw.hasPrefix(prefix) else { throw UserFacingError(message: "歌单身份无效") }
        let value = String(raw.dropFirst(prefix.count))
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }), value.first != "0" else {
            throw UserFacingError(message: "此歌单身份不支持旧版编辑接口")
        }
        return value
    }
}
