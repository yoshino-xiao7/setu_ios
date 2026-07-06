import SetuIOSCore
import SwiftUI

struct RootAppView: View {
    @Bindable var environment: AppEnvironment
    @State private var selectedTab: AppTab = .home
    @State private var tabRouter = TabRouter()

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack(path: tabRouter.binding(for: tab)) {
                    content(for: tab)
                        .navigationDestination(for: AppRoute.self) { route in
                            destination(for: route)
                        }
                }
                .environment(tabRouter.router(for: tab))
                .tabItem { tab.label }
                .tag(tab)
            }
        }
        .tint(.pink)
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            DashboardView(environment: environment)
        case .features:
            FeatureMapView()
        case .collections:
            CollectionListView(environment: environment)
        case .music:
            PlaceholderFeatureView(
                title: "音乐",
                systemImage: "music.note",
                summary: "后续接入播放器、歌单、播放历史和后台音频。"
            )
        case .settings:
            AccountView(environment: environment)
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .feature(let featureID):
            featureDestination(featureID)
        case .profile:
            ProfileView(environment: environment)
        case .apiKeys:
            ApiKeyListView(environment: environment)
        case .pointsLogs:
            PointsLogsView(environment: environment)
        case .notifications:
            NotificationsView(environment: environment)
        case .collections:
            CollectionListView(environment: environment)
        case .collectionSquare:
            PlaceholderFeatureView(title: "收藏夹广场", systemImage: "globe.asia.australia", summary: "发现公开收藏夹。")
        case .aiHistory:
            AiHistoryView(environment: environment)
        case .aiSquare:
            PlaceholderFeatureView(title: "AI 广场", systemImage: "photo.on.rectangle", summary: "浏览公开 AI 作品。")
        case .musicHistory:
            PlaceholderFeatureView(title: "播放历史", systemImage: "clock.arrow.circlepath", summary: "查看最近播放记录。")
        case .playlists:
            PlaceholderFeatureView(title: "我的歌单", systemImage: "music.note.list", summary: "管理歌单与歌曲。")
        case .admin:
            PlaceholderFeatureView(title: "管理后台", systemImage: "shield", summary: "管理员审核、日志和系统操作。")
        }
    }

    @ViewBuilder
    private func featureDestination(_ featureID: AppFeatureID) -> some View {
        switch featureID {
        case .profile:
            ProfileView(environment: environment)
        case .apiKeys:
            ApiKeyListView(environment: environment)
        case .collections:
            CollectionListView(environment: environment)
        case .aiHistory:
            AiHistoryView(environment: environment)
        case .pointsLogs:
            PointsLogsView(environment: environment)
        case .notifications:
            NotificationsView(environment: environment)
        case .systemStatus:
            SystemStatusView(environment: environment)
        default:
            if let feature = AppFeatureCatalog.feature(id: featureID) {
                FeatureDetailView(feature: feature)
            } else {
                PlaceholderFeatureView(title: "功能", systemImage: "questionmark.circle", summary: "功能定义不存在。")
            }
        }
    }
}
