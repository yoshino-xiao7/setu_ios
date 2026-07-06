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
        case .create:
            PlaceholderFeatureView(
                title: "AI 绘图",
                systemImage: "sparkles",
                summary: "后续接入 AI 绘图、资产选择、历史和生成进度。"
            )
        case .collections:
            PlaceholderFeatureView(
                title: "收藏",
                systemImage: "rectangle.stack",
                summary: "后续接入我的收藏夹、公开收藏夹和收藏夹广场。"
            )
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
        case .profile:
            AccountView(environment: environment)
        case .apiKeys:
            PlaceholderFeatureView(title: "API Keys", systemImage: "key", summary: "管理程序化调用密钥。")
        case .pointsLogs:
            PlaceholderFeatureView(title: "积分流水", systemImage: "list.bullet.rectangle", summary: "查看积分变动与调用记录。")
        case .collections:
            PlaceholderFeatureView(title: "我的收藏夹", systemImage: "heart", summary: "浏览、编辑和分享收藏夹。")
        case .collectionSquare:
            PlaceholderFeatureView(title: "收藏夹广场", systemImage: "globe.asia.australia", summary: "发现公开收藏夹。")
        case .aiHistory:
            PlaceholderFeatureView(title: "AI 绘图历史", systemImage: "clock", summary: "查看生成记录和任务状态。")
        case .aiSquare:
            PlaceholderFeatureView(title: "AI 广场", systemImage: "photo.on.rectangle", summary: "浏览公开 AI 作品。")
        case .musicHistory:
            PlaceholderFeatureView(title: "播放历史", systemImage: "clock.arrow.circlepath", summary: "查看最近播放记录。")
        case .playlists:
            PlaceholderFeatureView(title: "我的歌单", systemImage: "music.note.list", summary: "管理歌单与歌曲。")
        case .notifications:
            PlaceholderFeatureView(title: "通知中心", systemImage: "bell", summary: "接收系统、任务和审核通知。")
        case .admin:
            PlaceholderFeatureView(title: "管理后台", systemImage: "shield", summary: "管理员审核、日志和系统操作。")
        }
    }
}
