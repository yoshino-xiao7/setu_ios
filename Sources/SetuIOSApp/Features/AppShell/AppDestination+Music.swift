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
                .environment(\.musicPlaybackIntent, MusicPlaybackIntent(player: musicPlayer, store: musicStore))
        case .radioFM:
            if environment.config.musicFeatureFlags.radioFMEnabled {
                RadioFMView(environment: environment, player: musicPlayer).environment(musicStore)
            }
        case .rankings:
            if environment.config.musicFeatureFlags.rankingsEnabled {
                RankingsView(environment: environment).environment(musicStore)
            }
        case .newReleases(let albums):
            if environment.config.musicFeatureFlags.newReleasesEnabled {
                NewReleasesView(environment: environment, albums: albums).environment(musicStore)
                    .environment(\.musicPlaybackIntent, MusicPlaybackIntent(player: musicPlayer, store: musicStore, libraryClient: environment.musicV2Client, libraryEnabled: environment.config.musicFeatureFlags.likedTracksEnabled))
            }
        case .dailyRecommend:
            if environment.config.musicFeatureFlags.usesV2Home {
                DailyRecommendView(environment: environment, player: musicPlayer).environment(musicStore)
                    .environment(\.musicPlaybackIntent, MusicPlaybackIntent(player: musicPlayer, store: musicStore, libraryClient: environment.musicV2Client, libraryEnabled: environment.config.musicFeatureFlags.likedTracksEnabled))
            }
        case .likedTracks:
            if environment.config.musicFeatureFlags.likedTracksEnabled {
                LikedTracksView(environment: environment).environment(musicStore)
                    .environment(\.musicPlaybackIntent, MusicPlaybackIntent(player: musicPlayer, store: musicStore, libraryClient: environment.musicV2Client, libraryEnabled: environment.config.musicFeatureFlags.likedTracksEnabled))
            }
        case .favoritePlaylists:
            if environment.config.musicFeatureFlags.favoritePlaylistsEnabled {
                FavoritePlaylistsView(environment: environment).environment(musicStore)
            }
        case .musicHistory:
            MusicHistoryView(environment: environment, player: musicPlayer)
                .environment(\.musicPlaybackIntent, MusicPlaybackIntent(player: musicPlayer, store: musicStore))
                .environment(musicStore)
        case .playlists:
            MusicPlaylistsView(environment: environment, player: musicPlayer)
                .environment(musicStore)
        case .playlistDetail(let id):
            // The owned-playlist management surface remains /user/playlists/**
            // under the cutover manifest; external detail uses playlistDetailV2.
            MusicPlaylistDetailView(environment: environment, player: musicPlayer, playlistID: id).environment(musicStore)
        case .artistDetail(let id):
            if MusicDetailRoutes.artist(.init(rawValue: id), flags: environment.config.musicFeatureFlags) != nil {
                ArtistDetailView(environment: environment, artistID: id).environment(musicStore)
                    .environment(\.musicPlaybackIntent, MusicPlaybackIntent(player: musicPlayer, store: musicStore, libraryClient: environment.musicV2Client, libraryEnabled: environment.config.musicFeatureFlags.likedTracksEnabled))
            }
        case .albumDetail(let id):
            if MusicDetailRoutes.album(.init(rawValue: id), flags: environment.config.musicFeatureFlags) != nil {
                AlbumDetailView(environment: environment, albumID: id).environment(musicStore)
                    .environment(\.musicPlaybackIntent, MusicPlaybackIntent(player: musicPlayer, store: musicStore, libraryClient: environment.musicV2Client, libraryEnabled: environment.config.musicFeatureFlags.likedTracksEnabled))
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
            .environment(\.musicPlaybackIntent, MusicPlaybackIntent(player: musicPlayer, store: musicStore, libraryClient: environment.musicV2Client, libraryEnabled: environment.config.musicFeatureFlags.likedTracksEnabled))
    }
}
