import SetuIOSCore
import SwiftUI

struct ArtistDetailView: View {
    @Environment(MusicStore.self) private var store
    let environment: AppEnvironment
    let artistID: String
    private var flags: MusicFeatureFlags { environment.config.musicFeatureFlags }
    var body: some View {
        List {
            MusicDetailState(resource: store.artistDetail(artistID), retry: { await load(force: true) }) { detail in
                Section { MusicDetailHeader(title: detail.artist.name, description: detail.artist.description, artwork: detail.artist.artwork?.url) }
                Section("热门歌曲") {
                    MusicDetailTracks(tracks: detail.topTracks,
                                      context: .artist(id: detail.artist.id.rawValue, selection: .topTracks, label: detail.artist.name), flags: flags)
                }
                Section("专辑") {
                    if detail.albums.isEmpty { Text("暂无专辑") }
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: SetuSpacing.md) {
                            ForEach(detail.albums.indices, id: \.self) { index in
                                let album = detail.albums[index]
                                if let route = MusicDetailRoutes.album(album.id, flags: flags) {
                                    NavigationLink(value: route) { albumCard(album) }.buttonStyle(.plain)
                                } else { albumCard(album) }
                            }
                        }
                    }
                }
                Section("MV") {
                    if detail.mvs.isEmpty { Text("暂无 MV") }
                    ForEach(detail.mvs, id: \.id) { mv in
                        HStack {
                            MusicArtworkView(urlString: mv.artwork?.url)
                            Text(mv.title).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Section("相似歌手") {
                    if detail.similar.isEmpty { Text("暂无相似歌手") }
                    ForEach(detail.similar.indices, id: \.self) { index in
                        let artist = detail.similar[index]
                        if let route = MusicDetailRoutes.artist(artist.id, flags: flags) {
                            NavigationLink(value: route) { artistLabel(artist) }
                        } else { artistLabel(artist) }
                    }
                }
            }
        }.listStyle(.plain).setuBackground().navigationTitle("歌手详情")
            .task(id: store.sessionToken) { await load() }
            .refreshable { await load(force: true) }
    }
    private func load(force: Bool = false) async {
        guard flags.artistDetailEnabled else { return }
        await store.loadArtistDetail(artistID, client: environment.musicV2Client, force: force)
    }
    private func albumCard(_ album: MusicV2AlbumBrief) -> some View {
        VStack(alignment: .leading) {
            MusicArtworkView(urlString: album.artwork?.url, width: 120, height: 120)
            Text(album.title).font(SetuTypography.body).fixedSize(horizontal: false, vertical: true)
        }.frame(width: 144, alignment: .leading)
    }
    private func artistLabel(_ artist: MusicV2ArtistBrief) -> some View {
        HStack { MusicArtworkView(urlString: artist.artwork?.url); Text(artist.name).fixedSize(horizontal: false, vertical: true) }
    }
}
