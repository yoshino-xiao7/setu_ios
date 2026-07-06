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
            MusicHomeView(environment: environment)
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
        case .docs:
            StaticInfoView(kind: .docs)
        case .about:
            StaticInfoView(kind: .about)
        case .privacy:
            StaticInfoView(kind: .privacy)
        case .passkeys:
            PasskeyListView(environment: environment)
        case .points:
            PointsCallView(environment: environment)
        case .pointsLogs:
            PointsLogsView(environment: environment)
        case .notifications:
            NotificationsView(environment: environment)
        case .favorites:
            FavoriteListView(environment: environment)
        case .imageDeleteRequests:
            ImageDeleteRequestsView(environment: environment)
        case .imageDeleteRequestDetail(let id):
            ImageDeleteRequestDetailView(environment: environment, requestID: id)
        case .qqBinding:
            QqBindingView(environment: environment)
        case .security:
            SecuritySettingsView(environment: environment)
        case .collections:
            CollectionListView(environment: environment)
        case .collectionDetail(let id):
            CollectionDetailView(environment: environment, collectionID: id)
        case .collectionSquare:
            CollectionSquareView(environment: environment)
        case .galleryUploads:
            GalleryUploadBatchesView(environment: environment)
        case .galleryUploadDetail(let id):
            GalleryUploadDetailView(environment: environment, batchID: id)
        case .aiHistory:
            AiHistoryView(environment: environment)
        case .aiGenerationDetail(let id):
            AiGenerationDetailView(environment: environment, jobID: id)
        case .aiSquare:
            AiSquareView(environment: environment)
        case .musicHistory:
            MusicHistoryView(environment: environment)
        case .playlists:
            MusicPlaylistsView(environment: environment)
        case .playlistDetail(let id):
            MusicPlaylistDetailView(environment: environment, playlistID: id)
        case .admin:
            AdminOverviewView(environment: environment)
        case .adminUsers:
            AdminUsersView(environment: environment)
        case .adminUserDetail(let id):
            AdminUserDetailView(environment: environment, userID: id)
        case .adminBlacklist:
            AdminBlacklistView(environment: environment)
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
        case .aiSquare:
            AiSquareView(environment: environment)
        case .aiDraw:
            AiDrawView(environment: environment)
        case .collectionSquare:
            CollectionSquareView(environment: environment)
        case .galleryUpload:
            GalleryUploadBatchesView(environment: environment)
        case .qqBinding:
            QqBindingView(environment: environment)
        case .docs:
            StaticInfoView(kind: .docs)
        case .about:
            StaticInfoView(kind: .about)
        case .privacy:
            StaticInfoView(kind: .privacy)
        case .deleteRequests:
            ImageDeleteRequestsView(environment: environment)
        case .pointsLogs:
            PointsLogsView(environment: environment)
        case .points:
            PointsCallView(environment: environment)
        case .notifications:
            NotificationsView(environment: environment)
        case .systemStatus:
            SystemStatusView(environment: environment)
        case .musicPlayer:
            MusicHomeView(environment: environment)
        case .playlists:
            MusicPlaylistsView(environment: environment)
        case .musicHistory:
            MusicHistoryView(environment: environment)
        case .adminOverview:
            AdminOverviewView(environment: environment)
        case .adminUsers:
            AdminUsersView(environment: environment)
        case .adminBlacklist:
            AdminBlacklistView(environment: environment)
        default:
            if let feature = AppFeatureCatalog.feature(id: featureID) {
                FeatureDetailView(feature: feature)
            } else {
                PlaceholderFeatureView(title: "功能", systemImage: "questionmark.circle", summary: "功能定义不存在。")
            }
        }
    }
}
