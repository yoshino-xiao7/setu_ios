import SetuIOSCore
import SwiftUI

struct AlbumDetailView: View {
    @Environment(MusicStore.self) private var store
    let environment: AppEnvironment
    let albumID: String
    private var flags: MusicFeatureFlags { environment.config.musicFeatureFlags }
    var body: some View {
        List {
            MusicDetailState(resource: store.albumDetail(albumID), retry: { await load(force: true) }) { detail in
                Section {
                    MusicDetailHeader(title: detail.album.title, description: detail.album.description, artwork: detail.album.artwork?.url)
                    if let date = detail.album.releaseDate { Text(date) }
                    if let company = detail.album.company { Text(company) }
                    if let edition = detail.album.editionLabel { Text(edition) }
                    ForEach(detail.album.artists.indices, id: \.self) { index in
                        let artist = detail.album.artists[index]
                        if let route = MusicDetailRoutes.artist(artist.id, flags: flags) {
                            NavigationLink(artist.name, value: route)
                        } else { Text(artist.name) }
                    }
                }
                Section("歌曲") {
                    MusicDetailTracks(tracks: detail.tracks, context: .album(id: detail.album.id.rawValue, label: detail.album.title), flags: flags)
                }
            }
        }.listStyle(.plain).setuBackground().navigationTitle("专辑详情")
            .task(id: store.sessionToken) { await load() }.refreshable { await load(force: true) }
    }
    private func load(force: Bool = false) async {
        guard flags.albumDetailEnabled else { return }
        await store.loadAlbumDetail(albumID, client: environment.musicV2Client, force: force)
    }
}
