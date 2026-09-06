import SetuIOSCore
import SwiftUI

// Op19 has no successful v2 representation. Home navigation retains the legacy capability.
struct DailyRecommendView: View {
    @Environment(MusicStore.self) private var store
    let environment: AppEnvironment
    let player: MusicPlaybackController
    var body: some View {
        List {
            MusicDetailState(resource: store.dailySongs, retry: { await store.loadLegacyDaily(force: true) }) { songs in
                if songs.isEmpty { ContentUnavailableView("暂无每日推荐", systemImage: "music.note") }
                ForEach(songs) { song in
                    Button(song.name) {
                        Task {
                            await player.play(track: MusicPlaybackTrack(song: song), in: songs.map { MusicPlaybackTrack(song: $0) },
                                context: .discovery(source: .sharedAlgorithmic(label: "每日推荐"), selectionKey: "dailyTracks", label: "每日推荐"))
                        }
                    }.frame(minHeight: 44)
                }
            }
        }.listStyle(.plain).setuBackground().navigationTitle("每日推荐")
        .task(id: store.userID) { await store.loadLegacyDaily() }
        .refreshable { await store.loadLegacyDaily(force: true) }
    }
}
