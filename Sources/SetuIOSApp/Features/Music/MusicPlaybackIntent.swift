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
