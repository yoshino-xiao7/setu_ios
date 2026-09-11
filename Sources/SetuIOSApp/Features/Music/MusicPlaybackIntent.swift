import SetuIOSCore
import SwiftUI

@MainActor
struct MusicPlaybackIntent {
    let player: MusicPlaybackController
    let store: MusicStore
    var libraryClient: MusicV2Client? = nil
    var libraryEnabled = false

    func play(_ track: MusicV2Track, in tracks: [MusicV2Track], context: PlaybackContext,
              mode: MusicPlayMode? = nil) async {
        await player.play(track: MusicPlaybackTrack(track: track), in: tracks.map(MusicPlaybackTrack.init(track:)),
                          context: context, playMode: mode)
        await completePlaylistQueue(context: context)
    }

    private func completePlaylistQueue(context: PlaybackContext) async {
        guard let client = libraryClient, let playlistID = catalogPlaylistID(from: context) else { return }
        await store.loadRemainingPlaylistDetail(playlistID, client: client)
        guard let tracks = store.playlistDetailV2(playlistID.rawValue).value?.tracks else { return }
        player.appendUpcoming(tracks.map(MusicPlaybackTrack.init(track:)), matching: context)
    }

    private func catalogPlaylistID(from context: PlaybackContext) -> MusicV2PlaylistID? {
        switch context {
        case .playlist(id: .provider(.canonical(let id)), _):
            .provider(.init(rawValue: id.rawValue))
        case .playlist(id: .local(.canonical(let id)), _):
            .local(.init(rawValue: id.rawValue))
        case .playlist(id: .provider(.legacy(let id)), _):
            .provider(.init(rawValue: "netease:playlist:\(id)"))
        case .playlist(id: .local(.legacy(let id)), _):
            .local(.init(rawValue: "setu:playlist:\(id)"))
        default:
            nil
        }
    }
    func playNext(_ track: MusicV2Track) { player.playNext(MusicPlaybackTrack(track: track)) }
    func toggleLike(_ track: MusicV2Track, client: MusicV2Client, enabled: Bool) async {
        let owner = store.sessionToken
        do { try await store.toggleLike(track.id, track: track, client: client, enabled: enabled) }
        catch {
            guard owner == store.sessionToken else { return }
            player.showFeedback(.error(UserFacingErrorMapper.map(error)))
        }
    }

}

private struct MusicPlaybackIntentKey: EnvironmentKey {
    static let defaultValue: MusicPlaybackIntent? = nil
}
extension EnvironmentValues {
    var musicPlaybackIntent: MusicPlaybackIntent? {
        get { self[MusicPlaybackIntentKey.self] }
        set { self[MusicPlaybackIntentKey.self] = newValue }
    }
}
