import SetuIOSCore
import SwiftUI

struct RootAppView: View {
    @Bindable var environment: AppEnvironment
    @State private var selectedTab: AppTab = .home
    @State private var tabRouter = TabRouter()
    @State private var loggedOutRouter = RouterPath()

    var body: some View {
        Group {
            if environment.authSession.isSignedIn {
                appTabs
            } else {
                NavigationStack(path: Binding(
                    get: { loggedOutRouter.path },
                    set: { loggedOutRouter.path = $0 }
                )) {
                    AccountView(environment: environment)
                        .navigationDestination(for: AppRoute.self) { route in
                            destination(for: route)
                        }
                }
                .environment(loggedOutRouter)
            }
        }
        .tint(.pink)
    }

    private var appTabs: some View {
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
        case .publicCollectionDetail(let id):
            PublicCollectionDetailView(environment: environment, collectionID: id)
        case .publicUserProfile(let userID):
            PublicUserProfileView(environment: environment, userID: userID)
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
        case .adminSystemStatus:
            SystemStatusView(environment: environment, title: "系统监控")
        case .adminMusicTokens:
            AdminMusicTokensView(environment: environment)
        case .adminImageInfo:
            AdminImageInfoView(environment: environment)
        case .adminImageDetail(let pid, let p):
            AdminImageInfoView(environment: environment, initialPID: pid, initialPage: p)
        case .adminImageDeleteRequests:
            AdminImageDeleteRequestsView(environment: environment)
        case .adminImageDeleteRequestDetail(let id):
            AdminImageDeleteRequestDetailView(environment: environment, requestID: id)
        case .adminImageAudit:
            AdminImageAuditView(environment: environment)
        case .adminGallerySubmissions:
            AdminGallerySubmissionsView(environment: environment)
        case .adminGallerySubmissionDetail(let id):
            AdminGallerySubmissionDetailView(environment: environment, batchID: id)
        case .adminOperationLogs:
            AdminOperationLogsView(environment: environment)
        case .adminOperationLogDetail(let id):
            AdminOperationLogDetailView(environment: environment, logID: id)
        case .adminPixivCrawl:
            AdminPixivCrawlView(environment: environment)
        case .adminPixivTask(let id):
            AdminPixivTaskDetailView(environment: environment, taskID: id)
        case .adminAiGenerations:
            AdminAiGenerationsView(environment: environment)
        case .adminAiWorkers:
            AdminAiWorkersView(environment: environment)
        case .adminAiReviews:
            AdminAiReviewsView(environment: environment)
        case .adminAiDeleteRequests:
            AdminAiDeleteRequestsView(environment: environment)
        }
    }

    @ViewBuilder
    private func featureDestination(_ featureID: AppFeatureID) -> some View {
        switch featureID {
        case .dashboard:
            DashboardView(environment: environment)
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
        case .aiAssets:
            AiAssetBrowserView(environment: environment)
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
        case .adminSystemStatus:
            SystemStatusView(environment: environment, title: "系统监控")
        case .adminMusicTokens:
            AdminMusicTokensView(environment: environment)
        case .adminImageDeleteRequests:
            AdminImageDeleteRequestsView(environment: environment)
        case .adminImageAudit:
            AdminImageAuditView(environment: environment)
        case .adminGallerySubmissions:
            AdminGallerySubmissionsView(environment: environment)
        case .adminOperationLogs:
            AdminOperationLogsView(environment: environment)
        case .adminPixivCrawl:
            AdminPixivCrawlView(environment: environment)
        case .adminAiGenerations:
            AdminAiGenerationsView(environment: environment)
        case .adminAiWorkers:
            AdminAiWorkersView(environment: environment)
        case .adminAiReviews:
            AdminAiReviewsView(environment: environment)
        case .adminAiDeleteRequests:
            AdminAiDeleteRequestsView(environment: environment)
        }
    }
}
