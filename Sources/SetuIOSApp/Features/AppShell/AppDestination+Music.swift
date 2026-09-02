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
        case .playlists:
            MusicPlaylistsView(environment: environment, player: musicPlayer)
        case .playlistDetail(let id):
            MusicPlaylistDetailView(environment: environment, player: musicPlayer, playlistID: id)
        default:
            EmptyView()
        }
    }
}
