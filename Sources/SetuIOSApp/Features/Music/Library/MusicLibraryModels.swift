import Foundation
import SetuIOSCore

struct MusicLibraryPage<Item: Identifiable & Sendable>: Sendable where Item.ID: Sendable {
    var items: [Item]
    var nextOffset: Int?
    var total: Int
}

/// UI projection retains the relation identity even when the display snapshot is unavailable.
struct MusicLibraryTrack: Identifiable, Sendable {
    let id: MusicV2TrackID
    let ownerID: String
    let track: MusicV2Track?
    let likedAt: String?
    init(_ relation: MusicV2LikedTrack) {
        id = relation.trackId; ownerID = relation.ownerId.rawValue
        track = relation.track; likedAt = relation.likedAt
    }
    init(id: MusicV2TrackID, ownerID: String, track: MusicV2Track?) {
        self.id = id; self.ownerID = ownerID; self.track = track; likedAt = nil
    }
}
struct MusicLibraryPlaylist: Identifiable, Sendable {
    let id: MusicV2ProviderPlaylistID
    let ownerID: String
    let playlist: MusicV2ProviderPlaylist?
    let savedAt: String?
    init(_ relation: MusicV2SavedPlaylist) {
        id = relation.playlistId; ownerID = relation.ownerId.rawValue
        playlist = relation.playlist; savedAt = relation.savedAt
    }
    init(id: MusicV2ProviderPlaylistID, ownerID: String, playlist: MusicV2ProviderPlaylist?) {
        self.id = id; self.ownerID = ownerID; self.playlist = playlist; savedAt = nil
    }
}
