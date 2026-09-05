import SetuIOSCore
import SwiftUI

@MainActor
struct MusicPlaybackIntent {
    let player: MusicPlaybackController
    let store: MusicStore

    func play(_ track: MusicV2Track, in tracks: [MusicV2Track], context: PlaybackContext,
              mode: MusicPlayMode? = nil) async {
        await player.play(track: MusicPlaybackTrack(track: track), in: tracks.map(MusicPlaybackTrack.init(track:)),
                          context: context, playMode: mode)
    }
    func playNext(_ track: MusicV2Track) { player.playNext(MusicPlaybackTrack(track: track)) }
    func toggleLike(_ track: MusicV2Track) async {
        // P15 owns the mutation and reconciliation; do not guess a liked state here.
        player.showFeedback(.info("喜欢歌曲功能尚未启用"))
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
