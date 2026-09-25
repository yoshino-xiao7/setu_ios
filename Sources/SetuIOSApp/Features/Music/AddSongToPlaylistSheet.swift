import SetuIOSCore
import SwiftUI

struct AddSongToPlaylistSheet: View {
    @Bindable var environment: AppEnvironment
    let song: MusicSong
    let onFeedback: (SetuFeedback) -> Void

    var body: some View {
        PlaylistSelectionSheet(
            environment: environment,
            presentation: .song,
            requests: [AddSongToPlaylistRequest(song: song)],
            onAdded: { playlist in
                onFeedback(.success("已加入 \(playlist.name)"))
            },
            onNeteaseAdded: { playlist in
                onFeedback(.success("已加入网易云歌单《\(playlist.name)》"))
            }
        ) {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "歌曲")
                MusicSongRow(song: song)
            }
        }
    }
}
