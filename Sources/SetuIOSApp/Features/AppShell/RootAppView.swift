import SetuIOSCore
import SwiftUI

struct RootAppView: View {
    @Bindable var environment: AppEnvironment
    @State private var selectedTab: AppTab = .home
    @State private var tabRouter = TabRouter()
    @State private var loggedOutRouter = RouterPath()
    @State private var musicPlayer = MusicPlaybackController()

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
        currentTabStack
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                MusicMiniPlayerBar(environment: environment, player: musicPlayer)
                UserTabBar(selectedTab: $selectedTab)
            }
        }
    }

    private var currentTabStack: some View {
        NavigationStack(path: tabRouter.binding(for: selectedTab)) {
            content(for: selectedTab)
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
        }
        .environment(tabRouter.router(for: selectedTab))
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            DashboardView(environment: environment)
        case .ai:
            AiHubView(environment: environment)
        case .images:
            ImageHubView(environment: environment)
        case .music:
            MusicHomeView(environment: environment, player: musicPlayer)
        case .square:
            SquareHubView(environment: environment)
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
            StaticInfoView(environment: environment, kind: .docs)
        case .about:
            StaticInfoView(environment: environment, kind: .about)
        case .privacy:
            StaticInfoView(environment: environment, kind: .privacy)
        case .passkeys:
            PasskeyListView(environment: environment)
        case .points:
            PointsCallView(environment: environment)
        case .pointsLogs:
            PointsLogsView(environment: environment)
        case .imageSwipe:
            RandomImageSwipeView(environment: environment)
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
        case .squareHub:
            SquareHubView(environment: environment)
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
        case .aiDraw:
            AiDrawView(environment: environment)
        case .aiAssets:
            AiAssetBrowserView(environment: environment)
        case .aiHistory:
            AiHistoryView(environment: environment)
        case .aiDeleteRequests:
            AiDeleteRequestsView(environment: environment)
        case .aiGenerationDetail(let id):
            AiGenerationDetailView(environment: environment, jobID: id)
        case .aiSquare:
            AiSquareView(environment: environment)
        case .musicHome:
            MusicHomeView(environment: environment, player: musicPlayer)
        case .musicSearch(let initialQuery):
            MusicSearchView(environment: environment, player: musicPlayer, initialQuery: initialQuery)
        case .musicHistory:
            MusicHistoryView(environment: environment, player: musicPlayer)
        case .playlists:
            MusicPlaylistsView(environment: environment)
        case .playlistDetail(let id):
            MusicPlaylistDetailView(environment: environment, player: musicPlayer, playlistID: id)
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
            StaticInfoView(environment: environment, kind: .docs)
        case .about:
            StaticInfoView(environment: environment, kind: .about)
        case .privacy:
            StaticInfoView(environment: environment, kind: .privacy)
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
            MusicHomeView(environment: environment, player: musicPlayer)
        case .playlists:
            MusicPlaylistsView(environment: environment)
        case .musicHistory:
            MusicHistoryView(environment: environment, player: musicPlayer)
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

private struct UserTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 17, weight: selectedTab == tab ? .semibold : .regular))
                        Text(tab.title)
                            .font(.caption2.weight(selectedTab == tab ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(selectedTab == tab ? .pink : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
