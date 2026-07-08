import SetuIOSCore
import SwiftUI

struct RootAppView: View {
    @Bindable var environment: AppEnvironment
    @State private var selectedTab: AppTab = .home
    @State private var tabRouter = TabRouter()
    @State private var loggedOutRouter = RouterPath()
    @State private var musicPlayer = MusicPlaybackController()
    @State private var isSessionReady = false

    init(environment: AppEnvironment) {
        self.environment = environment
        SetuAppAppearance.configure()
    }

    var body: some View {
        Group {
            if isSessionReady {
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
            } else {
                ZStack {
                    SetuColor.pageGradient
                        .ignoresSafeArea()
                    SetuEmptyState(title: "正在确认登录状态", systemImage: "person.crop.circle.badge.checkmark", isLoading: true)
                        .padding()
                }
            }
        }
        .task(id: environment.authSession.currentUser?.id) {
            await ensureSessionState()
        }
        .task {
            configureMusicPlayerResolver()
        }
        .tint(SetuColor.brandPink)
    }

    /// Lets the playback controller fetch a fresh URL for the next track on its own, so
    /// end-of-track auto-play and lock-screen/headphone skip work without a visible view.
    private func configureMusicPlayerResolver() {
        musicPlayer.resolveTrackURL = { track in
            await resolvePlaybackURL(for: track)
        }
        musicPlayer.recordPlaybackHistory = { track in
            try? await environment.musicClient.addHistory(
                AddMusicHistoryRequest(
                    songId: track.id,
                    songName: track.title,
                    artistName: track.artist,
                    albumName: track.album,
                    coverUrl: track.coverURLString,
                    duration: track.durationMilliseconds
                )
            )
        }
    }

    private func resolvePlaybackURL(for track: MusicPlaybackTrack) async -> MusicURLResolution {
        var highQualityFailure: String?
        do {
            let highQuality = try await environment.musicClient.url(songID: track.id, level: "exhigh")
            if let url = playableURL(from: highQuality) {
                return .success(url)
            }
            highQualityFailure = unavailableReason(from: highQuality)
        } catch {
            highQualityFailure = error.localizedDescription
        }

        do {
            let standard = try await environment.musicClient.url(songID: track.id, level: "standard")
            if let url = playableURL(from: standard) {
                return .success(url, notice: "已切换标准音质")
            }
            return .unavailable(unavailableReason(from: standard) ?? highQualityFailure ?? "这首歌暂时无法播放")
        } catch {
            return .unavailable(highQualityFailure ?? error.localizedDescription)
        }
    }

    private func playableURL(from response: MusicUrlResponse) -> URL? {
        guard let item = response.data?.first,
              let urlString = item.playableURLString else { return nil }
        return URL(string: urlString)
    }

    private func unavailableReason(from response: MusicUrlResponse) -> String? {
        response.data?.first?.unavailableMessage
            ?? response.playabilityReason
            ?? response.message
            ?? response.msg
    }

    private var appTabs: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                tabContent(for: tab)
                    .tabItem {
                        tab.label
                    }
                    .tag(tab)
            }
        }
        .background(SetuColor.pageGradient.ignoresSafeArea())
    }

    private func tabContent(for tab: AppTab) -> some View {
        NavigationStack(path: tabRouter.binding(for: tab)) {
            content(for: tab)
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
        }
        .environment(tabRouter.router(for: tab))
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
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .account:
            AccountView(environment: environment)
        case .authRegister:
            AccountView(environment: environment, initialAuthPage: .register)
        case .authRecovery:
            AccountView(environment: environment, initialAuthPage: .recovery)
        case .profile:
            ProfileView(environment: environment)
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
            MusicPlaylistsView(environment: environment, player: musicPlayer)
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

    private func ensureSessionState() async {
        guard environment.authSession.currentUser != nil else {
            isSessionReady = true
            return
        }
        _ = await environment.authSession.confirmAuthenticatedSession()
        isSessionReady = true
    }
}
