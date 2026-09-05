import SetuIOSCore
import SwiftUI

struct NewReleasesView: View {
    @Environment(MusicStore.self) private var store
    let environment: AppEnvironment
    @State private var albums: Bool
    @State private var area: MusicV2Area = .all
    init(environment: AppEnvironment, albums: Bool = false) {
        self.environment = environment; _albums = State(initialValue: albums)
    }
    private var key: String { (albums ? "albums:" : "tracks:") + area.rawValue }
    private var loadKey: String { store.sessionToken.uuidString + key }
    var body: some View {
        List {
            Section {
                Picker("发行类型", selection: $albums) { Text("新歌").tag(false); Text("新专辑").tag(true) }.pickerStyle(.segmented)
                Picker("地区", selection: $area) {
                    Text("全部").tag(MusicV2Area.all); Text("华语").tag(MusicV2Area.zh)
                    Text("欧美").tag(MusicV2Area.ea); Text("日本").tag(MusicV2Area.jp); Text("韩国").tag(MusicV2Area.kr)
                }.accessibilityIdentifier("music.discover.area")
            }
            if albums {
                MusicDetailState(resource: store.releaseAlbums(area), retry: { await load(force: true) }) { result in
                    Section { MusicDiscoverSourceLabel(source: result.source) }
                    if result.items.isEmpty { ContentUnavailableView("暂无专辑", systemImage: "opticaldisc") }
                    ForEach(result.items, id: \.id) { album in
                        MusicDiscoverAlbumRow(album: album, flags: environment.config.musicFeatureFlags)
                    }
                    more(result.nextOffset)
                }
            } else {
                MusicDetailState(resource: store.releaseTracks(area), retry: { await load(force: true) }) { result in
                    Section { MusicDiscoverSourceLabel(source: result.source) }
                    Section("歌曲") {
                        MusicDetailTracks(tracks: result.items,
                            context: MusicDiscoverRoutes.context(source: result.source, selection: "newTracks:\(area.rawValue)", title: "新发行"),
                            flags: environment.config.musicFeatureFlags)
                    }
                    more(result.nextOffset)
                }
            }
        }.listStyle(.plain).setuBackground().navigationTitle("新发行")
            .task(id: loadKey) { await load() }.refreshable { await load(force: true) }
    }
    private func more(_ offset: Int?) -> some View {
        MusicDiscoverMore(nextOffset: offset, loading: store.discoverMoreLoading.contains(key), error: store.discoverMoreErrors[key]) {
            await load(more: true)
        }
    }
    private func load(force: Bool = false, more: Bool = false) async {
        guard environment.config.musicFeatureFlags.newReleasesEnabled else { return }
        if albums { await store.loadNewAlbums(area, client: environment.musicV2Client, force: force, more: more) }
        else { await store.loadNewTracks(area, client: environment.musicV2Client, force: force, more: more) }
    }
}
