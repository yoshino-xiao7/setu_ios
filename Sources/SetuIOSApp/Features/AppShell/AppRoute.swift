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
    case imageSwipe
    case collections
    case collectionDetail(Int)
    case squareHub
    case collectionSquare
    case publicCollectionDetail(Int)
    case publicUserProfile(Int)
    case galleryUploads
    case galleryUploadDetail(Int)
    case aiDraw
    case aiHistory
    case aiDeleteRequests
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
    case adminSystemStatus
    case adminMusicTokens
    case adminImageInfo
    case adminImageDetail(Int, Int)
    case adminImageDeleteRequests
    case adminImageDeleteRequestDetail(Int)
    case adminImageAudit
    case adminGallerySubmissions
    case adminGallerySubmissionDetail(Int)
    case adminOperationLogs
    case adminOperationLogDetail(Int)
    case adminPixivCrawl
    case adminPixivTask(String)
    case adminAiGenerations
    case adminAiWorkers
    case adminAiReviews
    case adminAiDeleteRequests
}

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case ai
    case images
    case music
    case square
    case settings

    var id: String { rawValue }

    @ViewBuilder
    var label: some View {
        Label(title, systemImage: systemImage)
    }

    var title: String {
        switch self {
        case .home:
            "首页"
        case .ai:
            "AI 绘画"
        case .images:
            "图片"
        case .music:
            "音乐"
        case .square:
            "广场"
        case .settings:
            "我的"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            "house"
        case .ai:
            "sparkles"
        case .images:
            "photo.on.rectangle"
        case .music:
            "music.note"
        case .square:
            "rectangle.stack"
        case .settings:
            "person.crop.circle"
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
