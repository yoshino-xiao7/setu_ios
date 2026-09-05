import SetuIOSCore
import SwiftUI

struct DailyRecommendView: View {
    @Environment(MusicStore.self) private var store
    let environment: AppEnvironment
    var body: some View {
        List {
            MusicDetailState(resource: store.dailyRecommendations, retry: { await load(force: true) }) { result in
                Section { MusicDiscoverSourceLabel(source: result.source) }
                Section("歌曲") {
                    MusicDetailTracks(tracks: result.tracks,
                        context: MusicDiscoverRoutes.context(source: result.source, selection: "dailyTracks", title: "每日推荐"),
                        flags: environment.config.musicFeatureFlags)
                }
            }
        }.listStyle(.plain).setuBackground().navigationTitle("每日推荐")
            .task(id: store.userID) { await load() }.refreshable { await load(force: true) }
    }
    private func load(force: Bool = false) async {
        guard environment.config.musicFeatureFlags.usesV2Home else { return }
        await store.loadDailyRecommendations(client: environment.musicV2Client, force: force)
    }
}
