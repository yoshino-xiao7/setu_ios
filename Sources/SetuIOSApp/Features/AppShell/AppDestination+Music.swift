import SetuIOSCore
import SwiftUI

// Music 域的导航 destination。新增页面：在 AppRoute 加 case 后，把视图挂到对应域的此处——
// 无需再改 RootAppView（其 destination 会自动聚合各域解析器）。
extension RootAppView {

    @ViewBuilder
    func musicDestination(for route: AppRoute) -> some View {
        switch route {
        case .musicSearch(let initialQuery):
            MusicSearchView(environment: environment, player: musicPlayer, initialQuery: initialQuery)
        case .musicHistory:
            MusicHistoryView(environment: environment, player: musicPlayer)
                .environment(musicStore)
        case .playlists:
            MusicPlaylistsView(environment: environment, player: musicPlayer)
                .environment(musicStore)
        case .playlistDetail(let id):
            if environment.config.musicFeatureFlags.usesV2PlaylistDetail {
                playlistDetailDestination(.local(.init(rawValue: "setu:playlist:\(id)")))
            } else {
                MusicPlaylistDetailView(environment: environment, player: musicPlayer, playlistID: id).environment(musicStore)
            }
        case .artistDetail(let id):
            if MusicDetailRoutes.artist(.init(rawValue: id), flags: environment.config.musicFeatureFlags) != nil {
                ArtistDetailView(environment: environment, artistID: id).environment(musicStore)
                    .environment(\.musicPlaybackIntent, MusicPlaybackIntent(player: musicPlayer, store: musicStore))
            }
        case .albumDetail(let id):
            if MusicDetailRoutes.album(.init(rawValue: id), flags: environment.config.musicFeatureFlags) != nil {
                AlbumDetailView(environment: environment, albumID: id).environment(musicStore)
                    .environment(\.musicPlaybackIntent, MusicPlaybackIntent(player: musicPlayer, store: musicStore))
            }
        case .playlistDetailV2(let raw):
            if environment.config.musicFeatureFlags.usesV2PlaylistDetail {
                switch MusicDetailRoutes.playlistID(raw) {
                case .unknown: EmptyView()
                case let id: playlistDetailDestination(id)
                }
            }
        default:
            EmptyView()
        }
    }
    private func playlistDetailDestination(_ id: MusicV2PlaylistID) -> some View {
        PlaylistDetailView(environment: environment, playlistID: id).environment(musicStore)
            .environment(\.musicPlaybackIntent, MusicPlaybackIntent(player: musicPlayer, store: musicStore))
    }
}
