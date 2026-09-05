import SetuIOSCore
import SwiftUI

struct RadioFMView: View {
    @Environment(MusicStore.self) private var store
    let environment: AppEnvironment
    @Bindable var player: MusicPlaybackController

    var body: some View {
        List {
            Section {
                Text("共享曲库推荐 · 根据你的不再播放记录过滤")
                    .foregroundStyle(.secondary)
            }
            if let feedback = player.feedback {
                Section { SetuFeedbackBanner(feedback: feedback) }
            }
            if player.context?.isInfinite == true {
                Section("当前曲与即将播放") {
                    ForEach(Array(player.queueTracks.enumerated()), id: \.offset) { index, track in
                        if index >= (player.currentQueueIndex ?? 0) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(track.title).font(.headline)
                                    Text(track.artist).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("不再播放") { Task { await player.blockRadioTrack(track) } }
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                        }
                    }
                }
                Section { Button("获取更多歌曲") { player.retryRadio() }.frame(minHeight: 44) }
            }
        }
        .listStyle(.plain).setuBackground().navigationTitle("私人 FM")
        .task(id: store.userID) {
            guard environment.config.musicFeatureFlags.radioFMEnabled else { return }
            player.startRadio(client: environment.musicV2Client)
        }
    }
}
