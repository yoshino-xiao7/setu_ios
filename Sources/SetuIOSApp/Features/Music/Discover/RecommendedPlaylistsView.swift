import SetuIOSCore
import SwiftUI

struct RecommendedPlaylistsView: View {
    @Environment(MusicStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let environment: AppEnvironment

    var body: some View {
        GeometryReader { proxy in
            let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
            let width = max(120, (proxy.size.width - 48 - CGFloat(columns - 1) * 16) / CGFloat(columns))
            ScrollView {
                VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                    Text("发现下一份心动歌单")
                        .font(.title2.weight(.bold)).foregroundStyle(SetuColor.textPrimary)
                    MusicDetailState(resource: store.v2RecommendedPlaylists, retry: { await load(force: true) }) { result in
                        if result.items.isEmpty {
                            ContentUnavailableView("暂无推荐歌单", systemImage: "music.note.list")
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: columns), alignment: .leading, spacing: 24) {
                            ForEach(result.items, id: \.id) { playlist in
                                MusicDiscoverPlaylistCard(playlist: .provider(playlist), flags: environment.config.musicFeatureFlags, width: width)
                            }
                        }
                    }
                }.padding(24)
            }
        }.setuBackground().navigationTitle("推荐歌单")
            .task(id: store.userID) { await load() }
            .refreshable { await load(force: true) }
    }

    private func load(force: Bool = false) async {
        guard environment.config.musicFeatureFlags.usesV2Home else { return }
        await store.loadRecommendedPlaylists(client: environment.musicV2Client, force: force)
    }
}
