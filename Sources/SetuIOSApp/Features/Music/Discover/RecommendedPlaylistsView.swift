import SetuIOSCore
import SwiftUI

struct RecommendedPlaylistsView: View {
    @Environment(MusicStore.self) private var store
    let environment: AppEnvironment

    var body: some View {
        List {
            MusicDetailState(resource: store.v2RecommendedPlaylists, retry: { await load(force: true) }) { result in
                Section { MusicDiscoverSourceLabel(source: result.source) }
                if result.items.isEmpty {
                    ContentUnavailableView("暂无推荐歌单", systemImage: "music.note.list")
                }
                ForEach(result.items, id: \.id) { playlist in
                    MusicDiscoverPlaylistRow(playlist: .provider(playlist), flags: environment.config.musicFeatureFlags)
                }
            }
        }.listStyle(.plain).setuBackground().navigationTitle("推荐歌单")
            .task(id: store.userID) { await load() }
            .refreshable { await load(force: true) }
    }

    private func load(force: Bool = false) async {
        guard environment.config.musicFeatureFlags.usesV2Home else { return }
        await store.loadRecommendedPlaylists(client: environment.musicV2Client, force: force)
    }
}
