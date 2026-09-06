import SetuIOSCore
import SwiftUI

enum AppRoute: Hashable {
    case account
    case profile
    case docs
    case about
    case privacy
    case terms
    case passkeys
    case points
    case apiKeys
    case pointsLogs
    case imageSwipe
    case collections
    case collectionDetail(Int)
    case collectionSquare
    case publicCollectionDetail(Int)
    case publicUserProfile(Int)
    case galleryUploads
    case galleryUploadDetail(Int)
    case aiDraw
    case aiAssets
    case aiHistory
    case aiDeleteRequests
    case aiGenerationDetail(Int)
    case publicAiWork(PublicAiWorkSnapshot)
    case aiSquare
    case musicSearch(String?)
    case likedTracks
    case favoritePlaylists
    case musicHistory
    case playlists
    case playlistDetail(Int)
    case artistDetail(String)
    case albumDetail(String)
    case playlistDetailV2(String)
    case radioFM
    case rankings
    case newReleases(albums: Bool)
    case dailyRecommend
    case recommendedPlaylists
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

struct PublicAiWorkSnapshot: Hashable {
    let id: Int
    let ownerUserID: Int?
    let imageURLString: String?
    let prompt: String
    let width: Int
    let height: Int
    let category: String?
    let createdAt: String?
    let likeCount: Int
    let favoriteCount: Int
    let likedByMe: Bool
    let favoritedByMe: Bool

    init(work: AiPublicWork) {
        id = work.id
        ownerUserID = work.userId
        imageURLString = work.imageUrl
        prompt = work.promptCn
        width = work.width
        height = work.height
        category = work.publicCategory
        createdAt = work.createdAt
        likeCount = work.likeCount
        favoriteCount = work.favoriteCount
        likedByMe = work.likedByMe
        favoritedByMe = work.favoritedByMe
    }

    init(
        id: Int,
        ownerUserID: Int?,
        imageURLString: String?,
        prompt: String,
        width: Int,
        height: Int,
        category: String?,
        createdAt: String?,
        likeCount: Int = 0,
        favoriteCount: Int = 0,
        likedByMe: Bool = false,
        favoritedByMe: Bool = false
    ) {
        self.id = id
        self.ownerUserID = ownerUserID
        self.imageURLString = imageURLString
        self.prompt = prompt
        self.width = width
        self.height = height
        self.category = category
        self.createdAt = createdAt
        self.likeCount = likeCount
        self.favoriteCount = favoriteCount
        self.likedByMe = likedByMe
        self.favoritedByMe = favoritedByMe
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case ai
    case images
    case music
    case square

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

/// Owns both the selected tab and each tab's navigation stack so cross-tab
/// navigation cannot accidentally append a destination to the source stack.
@MainActor
@Observable
final class AppNavigationCoordinator {
    var selectedTab: AppTab = .home
    private let tabRouter = TabRouter()

    func router(for tab: AppTab) -> RouterPath {
        tabRouter.router(for: tab)
    }

    func binding(for tab: AppTab) -> Binding<[AppRoute]> {
        tabRouter.binding(for: tab)
    }

    func navigate(to tab: AppTab, route: AppRoute? = nil, reset: Bool = false) {
        let targetRouter = router(for: tab)
        if reset {
            targetRouter.reset()
        }
        selectedTab = tab
        if let route {
            targetRouter.navigate(to: route)
        }
    }
}
