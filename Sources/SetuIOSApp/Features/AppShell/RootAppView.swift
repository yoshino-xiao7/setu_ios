import SetuIOSCore
import SwiftUI

struct RootAppView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var environment: AppEnvironment
    @Bindable var pushNotifications: SystemPushCoordinator
    @State private var navigationCoordinator = AppNavigationCoordinator()
    @State private var loggedOutRouter = RouterPath()
    @State var musicStore: MusicStore
    @State var musicPlayer = MusicPlaybackController()
    @State private var showingMusicQueueDrawer = false
    @State private var musicInsetHeight: CGFloat = 0
    @State private var musicInsetFrame: CGRect = .zero
    @State private var isSessionReady = false
    @State private var showingReauthentication = false
    @State private var sessionOwnerID: Int?

    init(
        environment: AppEnvironment,
        pushNotifications: SystemPushCoordinator,
        navigationCoordinator: AppNavigationCoordinator? = nil,
        musicPlayer: MusicPlaybackController? = nil
    ) {
        _musicStore = State(initialValue: MusicStore(client: environment.musicClient, userID: environment.authSession.currentUser?.id))
        _musicPlayer = State(initialValue: musicPlayer ?? MusicPlaybackController())
        _navigationCoordinator = State(initialValue: navigationCoordinator ?? AppNavigationCoordinator())
        self.environment = environment
        _sessionOwnerID = State(initialValue: environment.authSession.currentUser?.id)
        self.pushNotifications = pushNotifications
        SetuAppAppearance.configure()
    }

    var body: some View {
        Group {
            if isSessionReady {
                if environment.authSession.isSignedIn || environment.authSession.requiresReauthentication {
                    appTabs
                        .id(sessionOwnerID)
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
            if environment.authSession.isSignedIn {
                await pushNotifications.syncForSignedInUser()
                openPendingPushIfPossible()
            }
        }
        .task {
            switchMusicPlaybackUser(from: environment.authSession.currentUser?.id, to: environment.authSession.currentUser?.id)
            configureMusicPlayerResolver()
        }
        .onChange(of: environment.authSession.currentUser?.id) { oldUserID, newUserID in
            musicStore.reset(for: newUserID)
            switchMusicPlaybackUser(from: oldUserID, to: newUserID)
            configureMusicPlayerResolver()
            if newUserID != nil {
                if !environment.authSession.requiresReauthentication { updateSessionOwner() }
                Task { await pushNotifications.syncForSignedInUser() }
                openPendingPushIfPossible()
            }
        }
        .onChange(of: pushNotifications.pendingDestination) {
            openPendingPushIfPossible()
        }
        .onChange(of: navigationCoordinator.selectedTab) { oldValue, _ in
            if oldValue == .music {
                musicPlayer.savePlaybackSnapshot()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                musicPlayer.savePlaybackSnapshot()
            }
        }
        .tint(SetuColor.brandPink)
        .sheet(isPresented: $showingReauthentication) {
            NavigationStack(path: Binding(get: { loggedOutRouter.path }, set: { loggedOutRouter.path = $0 })) {
                AccountView(environment: environment, initialAuthPage: .login)
                    .navigationDestination(for: AppRoute.self) { destination(for: $0) }
            }
            .environment(loggedOutRouter)
        }
        .onChange(of: environment.authSession.requiresReauthentication) { _, required in
            if !required, environment.authSession.isSignedIn {
                showingReauthentication = false
                updateSessionOwner()
            }
        }
        .environment(pushNotifications)
        .environment(musicStore)
    }

    private func beginReauthentication() {
        environment.authSession.invalidateLocalSession()
        loggedOutRouter.reset()
        showingReauthentication = true
    }

    private func updateSessionOwner() {
        let userID = environment.authSession.currentUser?.id
        if let previous = sessionOwnerID, previous != userID {
            navigationCoordinator = AppNavigationCoordinator()
        }
        sessionOwnerID = userID
    }

    private func switchMusicPlaybackUser(from oldUserID: Int?, to newUserID: Int?) {
        guard oldUserID != newUserID else {
            musicPlayer.setSnapshotUserID(newUserID)
            if let newUserID {
                musicPlayer.restorePlaybackSnapshotIfNeeded(for: newUserID)
            }
            return
        }

        if let oldUserID {
            musicPlayer.savePlaybackSnapshot(userID: oldUserID)
        }
        musicPlayer.resetForUserChange()
        musicPlayer.setSnapshotUserID(newUserID)
        if let newUserID {
            musicPlayer.restorePlaybackSnapshotIfNeeded(for: newUserID)
        }
    }

    /// Lets the playback controller fetch a fresh URL for the next track on its own, so
    /// end-of-track auto-play and lock-screen/headphone skip work without a visible view.
    private func configureMusicPlayerResolver() {
        musicPlayer.urlResolver = PlaybackURLResolver(client: environment.musicClient)
        let store = musicStore
        musicPlayer.recordPlaybackHistory = { track in
            try? await store.addHistory(
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

    private var appTabs: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: Binding(
                get: { navigationCoordinator.selectedTab },
                set: { navigationCoordinator.selectedTab = $0 }
            )) {
                ForEach(AppTab.allCases) { tab in
                    tabContent(for: tab)
                        .tabItem {
                            tab.label
                        }
                        .tag(tab)
                }
            }
            .background(SetuColor.pageGradient.ignoresSafeArea())
            .overlay {
                if musicPlayer.currentTrack != nil {
                    GeometryReader { rootGeometry in
                        musicPlayerInset
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { musicInsetHeight = $0 }
                            .position(
                                x: rootGeometry.size.width / 2,
                                y: musicInsetFrame.minY - rootGeometry.frame(in: .global).minY + musicInsetHeight / 2
                            )
                            .opacity(musicInsetFrame.isEmpty ? 0 : 1)
                    }
                }
            }

            if showingMusicQueueDrawer {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showingMusicQueueDrawer = false
                    }
                    .zIndex(2)

                MusicQueueDrawerView(player: musicPlayer) {
                    showingMusicQueueDrawer = false
                }
                .padding(.horizontal, SetuSpacing.md)
                .padding(.bottom, SetuSpacing.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(3)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: showingMusicQueueDrawer)
        .onChange(of: musicPlayer.currentTrack?.id) { _, trackID in
            if trackID == nil {
                showingMusicQueueDrawer = false
            }
        }
        .environment(navigationCoordinator)
    }

    private func tabContent(for tab: AppTab) -> some View {
        NavigationStack(path: navigationCoordinator.binding(for: tab)) {
            content(for: tab)
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                        .safeAreaInset(edge: .bottom, spacing: 0) { musicPlayerSpace(for: tab) }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { musicPlayerSpace(for: tab) }
        }
        .environment(navigationCoordinator.router(for: tab))
        .environment(\.setuRecoveryActions, SetuRecoveryActions(
            signIn: beginReauthentication,
            goBack: {
                let router = navigationCoordinator.router(for: tab)
                if !router.path.isEmpty { router.path.removeLast() }
            },
            viewPoints: { navigationCoordinator.navigate(to: .images, route: .pointsLogs) }
        ))
    }

    @ViewBuilder
    private func musicPlayerSpace(for tab: AppTab) -> some View {
        if musicPlayer.currentTrack != nil {
            let isSelected = navigationCoordinator.selectedTab == tab
            // Keep the original inset ordering relative to page-specific bottom actions.
            // These placeholders own no player, progress observation or artwork task.
            Color.clear
                .frame(height: musicInsetHeight)
                .onGeometryChange(for: CGRect.self) {
                    isSelected ? $0.frame(in: .global) : .zero
                } action: { frame in
                    if navigationCoordinator.selectedTab == tab, !frame.isEmpty { musicInsetFrame = frame }
                }
        }
    }

    @ViewBuilder
    private var musicPlayerInset: some View {
        if musicPlayer.currentTrack != nil {
            MusicMiniPlayerBar(environment: environment, player: musicPlayer) {
                showingMusicQueueDrawer = true
            }
            .padding(.bottom, SetuSpacing.xl)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            DashboardView(environment: environment, player: musicPlayer)
        case .ai:
            AiDrawView(environment: environment)
        case .images:
            RandomImageSwipeView(environment: environment)
        case .music:
            MusicHomeView(environment: environment, player: musicPlayer)
        case .square:
            SquareHubView(environment: environment)
        }
    }

    /// 聚合各 feature 域的 destination 解析器（AppDestination+*.swift）。
    /// 未匹配的域渲染 EmptyView，ZStack 中恰好产生一个有效子视图。
    @ViewBuilder
    func destination(for route: AppRoute) -> some View {
        ZStack {
            accountDestination(for: route)
            contentDestination(for: route)
            aiDestination(for: route)
            musicDestination(for: route)
            adminDestination(for: route)
        }
    }

    private func ensureSessionState() async {
        guard environment.authSession.currentUser != nil else {
            isSessionReady = true
            return
        }
        // 乐观恢复：本地已有会话（Keychain 还原）就立即进入主界面，
        // 后台再确认；仅后端明确拒绝（401/403）才清除会话，弱网不踢人。
        isSessionReady = true
        await environment.authSession.confirmSession()
    }

    private func openPendingPushIfPossible() {
        guard environment.authSession.isSignedIn,
              let destination = pushNotifications.consumePendingDestination() else { return }
        let targetType = (destination.targetType ?? "").uppercased()
        let target: AppTab
        let route: AppRoute
        if let id = destination.targetID,
           targetType == "AI_GENERATION" || destination.type == "AI_GENERATION_COMPLETED" {
            target = .ai
            route = .aiGenerationDetail(id)
        } else if let id = destination.targetID,
                  targetType.contains("GALLERY") || destination.type?.hasPrefix("GALLERY_SUBMISSION_") == true {
            target = .images
            route = .galleryUploadDetail(id)
        } else if let id = destination.targetID,
                  targetType.contains("DELETE") || destination.type?.hasPrefix("IMAGE_DELETE_REQUEST_") == true {
            target = .images
            route = .imageDeleteRequestDetail(id)
        } else {
            target = .home
            route = .notifications
        }
        navigationCoordinator.navigate(to: target, route: route)
    }
}
