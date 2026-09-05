import SetuIOSCore
import SwiftUI

struct RankingsView: View {
    @Environment(MusicStore.self) private var store
    let environment: AppEnvironment
    var body: some View {
        List {
            MusicDetailState(resource: store.rankings, retry: { await load(force: true) }) { result in
                Section { MusicDiscoverSourceLabel(source: result.source) }
                if result.items.isEmpty { ContentUnavailableView("暂无榜单", systemImage: "chart.bar") }
                ForEach(result.items, id: \.id) { playlist in
                    MusicDiscoverPlaylistRow(playlist: .provider(playlist), flags: environment.config.musicFeatureFlags)
                }
            }
        }.listStyle(.plain).setuBackground().navigationTitle("排行榜")
            .task(id: store.userID) { await load() }.refreshable { await load(force: true) }
    }
    private func load(force: Bool = false) async {
        guard environment.config.musicFeatureFlags.rankingsEnabled else { return }
        await store.loadRankings(client: environment.musicV2Client, force: force)
    }
}
