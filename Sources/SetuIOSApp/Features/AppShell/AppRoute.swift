import SetuIOSCore
import SwiftUI

enum AppRoute: Hashable {
    case feature(AppFeatureID)
    case profile
    case apiKeys
    case docs
    case about
    case privacy
    case passkeys
    case points
    case pointsLogs
    case collections
    case collectionDetail(Int)
    case collectionSquare
    case galleryUploads
    case galleryUploadDetail(Int)
    case aiHistory
    case aiGenerationDetail(Int)
    case aiSquare
    case musicHistory
    case playlists
    case playlistDetail(Int)
    case notifications
    case favorites
    case imageDeleteRequests
    case imageDeleteRequestDetail(Int)
    case qqBinding
    case security
    case admin
    case adminUsers
    case adminUserDetail(Int)
    case adminBlacklist
    case adminMusicTokens
    case adminImageDeleteRequests
    case adminImageDeleteRequestDetail(Int)
    case adminGallerySubmissions
    case adminGallerySubmissionDetail(Int)
}

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case features
    case collections
    case music
    case settings

    var id: String { rawValue }

    @ViewBuilder
    var label: some View {
        switch self {
        case .home:
            Label("首页", systemImage: "house")
        case .features:
            Label("功能", systemImage: "square.grid.2x2")
        case .collections:
            Label("收藏", systemImage: "rectangle.stack")
        case .music:
            Label("音乐", systemImage: "music.note")
        case .settings:
            Label("我的", systemImage: "person.crop.circle")
        }
    }
}

@MainActor
@Observable
final class RouterPath {
    var path: [AppRoute] = []

    func navigate(to route: AppRoute) {
        path.append(route)
    }

    func reset() {
        path.removeAll()
    }
}

@MainActor
@Observable
final class TabRouter {
    private var routers: [AppTab: RouterPath] = [:]

    func router(for tab: AppTab) -> RouterPath {
        if let router = routers[tab] {
            return router
        }
        let router = RouterPath()
        routers[tab] = router
        return router
    }

    func binding(for tab: AppTab) -> Binding<[AppRoute]> {
        let router = router(for: tab)
        return Binding(
            get: { router.path },
            set: { router.path = $0 }
        )
    }
}
