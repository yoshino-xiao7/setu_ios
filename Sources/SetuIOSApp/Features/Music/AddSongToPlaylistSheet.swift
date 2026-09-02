import SetuIOSCore
import SwiftUI

struct AddSongToPlaylistSheet: View {
    @Bindable var environment: AppEnvironment
    let song: MusicSong
    let onFeedback: (SetuFeedback) -> Void

    var body: some View {
        PlaylistSelectionSheet(presentation: .song, requests: [AddSongToPlaylistRequest(song: song)]) { playlist in
            onFeedback(.success("已加入 \(playlist.name)"))
        } summary: {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "歌曲")
                MusicSongRow(song: song)
            }
        }
    }
}
