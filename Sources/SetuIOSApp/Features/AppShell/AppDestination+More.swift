import SetuIOSCore
import SwiftUI

extension RootAppView {

    @ViewBuilder
    func moreDestination(for route: AppRoute) -> some View {
        switch route {
        case .plaza:
            PlazaHubView(environment: environment)
        case .asmrHome:
            AsmrHomeView(environment: environment)
        case .asmrWork(let workID):
            AsmrWorkDetailView(environment: environment, workID: workID)
        case .asmrFavorites:
            AsmrFavoriteListView(environment: environment)
        case .asmrHistory:
            ModuleWatchHistoryView(environment: environment, module: .asmr, aspectRatio: 1)
        case .jmHome:
            JmHomeView(environment: environment)
        case .jmAlbum(let albumID):
            JmAlbumDetailView(environment: environment, albumID: albumID)
        case .jmReader(let albumID, let chapterID):
            JmReaderView(environment: environment, albumID: albumID, chapterID: chapterID)
        case .jmFavorites:
            JmFavoriteListView(environment: environment)
        case .jmHistory:
            ModuleWatchHistoryView(environment: environment, module: .jm)
        default:
            EmptyView()
        }
    }
}
