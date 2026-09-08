import Foundation
import SetuIOSCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if DEBUG

/// Isolated real-renderer workload for physical scrolling metrics. No client flags or network.
struct SetuP13WordScrollScenario: View {
    private let started = Date()
    @State private var elapsed = 0.0
    private var fixedLine: Bool { ProcessInfo.processInfo.arguments.contains("-ui-testing-p13-fixed-line") }
    private let lines: [LyricLine] = {
        let body: [String: Any] = ["trackId": "netease:track:1", "kind": ProcessInfo.processInfo.arguments.contains("-ui-testing-p13-line-control") ? "line" : "word", "hasTranslation": true,
            "contributors": [], "lines": (0..<120).map { index in
                ["text": "沿着星光慢慢回家", "startMs": index * 4000, "durationMs": 4000,
                 "translation": "Walking home beneath the stars",
                 "words": ["沿着", "星光", "慢慢", "回家"].enumerated().map {
                     ["text": $0.element, "startMs": index * 4000 + $0.offset * 1000, "durationMs": 1000] as [String: Any]
                 }] as [String: Any]
            }]
        let data = try! JSONSerialization.data(withJSONObject: body)
        return LyricParser.parse(try! JSONDecoder().decode(MusicV2Lyric.self, from: data))
    }()
    var body: some View {
        LyricScrollView(lines: lines, currentTime: elapsed, expands: true, isPlaying: !ProcessInfo.processInfo.arguments.contains("-ui-testing-p13-static-word"),
                        sampleTime: { fixedLine ? Date().timeIntervalSince(started).truncatingRemainder(dividingBy: 4) : Date().timeIntervalSince(started) }, onSeek: { elapsed = $0 })
            .accessibilityIdentifier("p13.word-scroll")
            .task {
                while !Task.isCancelled {
                    elapsed = fixedLine ? 0.5 : Date().timeIntervalSince(started)
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
    }
}

/// Dependencies for page-level previews.
///
/// The API session is handled entirely in-process. Fixture payloads deliberately
/// omit remote artwork URLs so opening a preview never depends on DNS, a backend,
/// or a public image host.
@MainActor
struct SetuFeaturePreviewHost<Content: View>: View {
    private let environment: AppEnvironment
    private let player: MusicPlaybackController
    @State private var musicStore: MusicStore
    private let router = RouterPath()
    private let navigation = AppNavigationCoordinator()
    private let pushNotifications: SystemPushCoordinator
    private let content: (AppEnvironment, MusicPlaybackController) -> Content

    init(
        playerState: SetuPreviewPlayerState = .empty,
        draftState: SetuPreviewDraftState = .fixture,
        @ViewBuilder content: @escaping (AppEnvironment, MusicPlaybackController) -> Content
    ) {
        let previewDraft: AiDrawDraft = draftState == .fixture
            ? SetuPreviewFixtures.aiDrawDraft
            : AiDrawDraft()
        AiAssetBrowserCacheStore.activatePreviewStorage()
        AiDrawDraftStore.activatePreviewStorage(with: previewDraft)
        let environment = SetuPreviewEnvironment.make()
        let player = MusicPlaybackController(persistsPlayback: false)
        if playerState == .listening {
            player.configurePreview(
                songs: SetuPreviewAPI.musicSongs,
                currentIndex: 0,
                queueName: "夏夜专注"
            )
        }

        _musicStore = State(initialValue: MusicStore(client: environment.musicClient, userID: environment.authSession.currentUser?.id))
        self.environment = environment
        self.player = player
        pushNotifications = SystemPushCoordinator(environment: environment)
        self.content = content
    }

    var body: some View {
        NavigationStack {
            content(environment, player)
        }
        .environment(router)
        .environment(navigation)
        .environment(pushNotifications)
        .environment(musicStore)
        .tint(SetuColor.brandPink)
    }
}

@MainActor
struct SetuRootUITestScenario: View {
    @State private var context: SetuRootUITestContext?

    var body: some View {
        Group {
            if let context {
                RootAppView(
                    environment: context.environment, pushNotifications: context.push,
                    navigationCoordinator: context.navigation, musicPlayer: context.player
                )
            } else {
                ProgressView()
                    .task {
                        // Own the fixtures for the lifetime of this screen, including sheet presentations.
                        if context == nil { context = SetuRootUITestContext() }
                    }
            }
        }
    }
}

@MainActor
private struct SetuRootUITestContext {
    let environment: AppEnvironment
    let push: SystemPushCoordinator
    let navigation: AppNavigationCoordinator
    let player: MusicPlaybackController

    init() {
        AiAssetBrowserCacheStore.activatePreviewStorage()
        AiDrawDraftStore.activatePreviewStorage(with: SetuPreviewFixtures.aiDrawDraft)
        let environment = SetuPreviewEnvironment.make()
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-welcome-fixture") {
            environment.authSession.resetLocalSession()
        }
        self.environment = environment
        push = SystemPushCoordinator(environment: environment)
        navigation = AppNavigationCoordinator()
        player = MusicPlaybackController(persistsPlayback: false)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-root-player") {
            player.configurePreview(songs: SetuPreviewAPI.musicSongs)
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-root-music-cache") {
            UserDefaults.standard.removeObject(forKey: "music.cache.capacityMB")
            UserDefaults.standard.removeObject(forKey: "music.cache.prefetch")
            navigation.navigate(to: .home, route: .account)
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-root-image-tasks") { navigation.navigate(to: .home, route: .adminPixivCrawl) }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-root-images") { navigation.selectedTab = .images }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-root-ai") { navigation.selectedTab = .ai }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-root-music") { navigation.selectedTab = .music }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-ui-testing-music-discover"), let index = args.firstIndex(of: "-ui-testing-discover-page"), args.indices.contains(index + 1) {
            switch args[index + 1] {
            case "likedTracks": navigation.navigate(to: .music, route: .likedTracks)
            case "favoritePlaylists": navigation.navigate(to: .music, route: .favoritePlaylists)
            case "radioFM": navigation.navigate(to: .music, route: .radioFM)
            case "rankings": navigation.navigate(to: .music, route: .rankings)
            case "newReleases": navigation.navigate(to: .music, route: .newReleases(albums: false))
            case "dailyRecommend": navigation.navigate(to: .music, route: .dailyRecommend)
            default: break
            }
        }
        if args.contains("-ui-testing-music-details"), let index = args.firstIndex(of: "-ui-testing-detail-page"), args.indices.contains(index + 1) {
            let route: AppRoute = switch args[index + 1] {
            case "album": .albumDetail("netease:album:detail")
            case "playlist": .playlistDetailV2("netease:playlist:detail")
            default: .artistDetail("netease:artist:detail")
            }
            navigation.navigate(to: .music, route: route)
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-root-favorites") { navigation.navigate(to: .images, route: .favorites) }
    }

}

enum SetuPreviewPlayerState: Equatable {
    case empty
    case listening
}

enum SetuPreviewDraftState: Equatable {
    case empty
    case fixture
}

@MainActor
struct SetuPublicAiWorkUITestScenario: View {
    var body: some View {
        SetuFeaturePreviewHost { environment, _ in
            PublicAiWorkDetailView(
                environment: environment,
                work: PublicAiWorkSnapshot(
                    id: 601,
                    ownerUserID: 71,
                    imageURLString: nil,
                    prompt: "粉色云层下的夏日列车，柔和逆光与安静站台",
                    width: 768,
                    height: 1024,
                    category: "GENERAL",
                    createdAt: "2026-07-10T08:30:00+08:00",
                    likeCount: 128,
                    favoriteCount: 42,
                    likedByMe: true,
                    favoritedByMe: false
                )
            )
        }
    }
}

@MainActor
struct SetuRandomImageUITestScenario: View {
    var body: some View {
        SetuFeaturePreviewHost { environment, _ in
            RandomImageSwipeView(environment: environment)
        }
    }
}

@MainActor
struct SetuAiDraftUITestScenario: View {
    var body: some View {
        SetuFeaturePreviewHost { environment, _ in
            SetuAiDraftUITestHarness(environment: environment)
        }
    }
}

@MainActor
private struct SetuAiDraftUITestHarness: View {
    let environment: AppEnvironment
    @State private var showingEditor = false

    var body: some View {
        Button("打开 AI 创作") {
            showingEditor = true
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("ai.draft.open")
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                AiDrawView(environment: environment)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("离开创作") {
                                showingEditor = false
                            }
                            .accessibilityIdentifier("ai.draft.close")
                        }
                    }
            }
        }
    }
}

@MainActor
struct SetuFavoriteListUITestScenario: View {
    var body: some View {
        SetuFeaturePreviewHost { environment, _ in
            FavoriteListView(environment: environment)
        }
    }
}

@MainActor
struct SetuNotificationPermissionUITestScenario: View {
    var body: some View {
        SetuFeaturePreviewHost { environment, _ in
            SetuNotificationPermissionUITestHarness(environment: environment)
        }
    }
}

@MainActor
struct SetuNotificationsReadAllFailureUITestScenario: View {
    var body: some View {
        SetuFeaturePreviewHost { environment, _ in
            NotificationsView(environment: environment)
        }
    }
}

@MainActor
struct SetuDailyFavoriteFailureUITestScenario: View {
    var body: some View {
        SetuFeaturePreviewHost { environment, _ in
            StaticInfoView(environment: environment, kind: .docs)
        }
    }
}

@MainActor
struct SetuPointsFavoriteFailureUITestScenario: View {
    var body: some View {
        SetuFeaturePreviewHost { environment, _ in
            PointsCallView(environment: environment)
        }
    }
}

@MainActor
struct SetuDashboardUITestScenario: View {
    var body: some View {
        let showsFailures = ProcessInfo.processInfo.arguments.contains("-ui-testing-dashboard-failures")
        SetuFeaturePreviewHost(
            playerState: showsFailures ? .empty : .listening,
            draftState: showsFailures ? .empty : .fixture
        ) { environment, player in
            DashboardView(environment: environment, player: player)
        }
    }
}

@MainActor
struct SetuSecurityFailureUITestScenario: View {
    var body: some View {
        SetuFeaturePreviewHost { environment, _ in
            SecuritySettingsView(environment: environment)
        }
    }
}

@MainActor
struct SetuMusicHomeUITestScenario: View {
    var body: some View {
        SetuFeaturePreviewHost(playerState: .listening) { environment, player in
            MusicHomeView(environment: environment, player: player)
        }
    }
}

@MainActor
struct SetuCollectionSquareUITestScenario: View {
    var body: some View {
        SetuFeaturePreviewHost { environment, _ in
            CollectionSquareView(environment: environment)
        }
    }
}

@MainActor
struct SetuSquareHubUITestScenario: View {
    var body: some View {
        SetuFeaturePreviewHost { environment, _ in
            SquareHubView(environment: environment)
        }
    }
}

@MainActor
struct SetuAiHubUITestScenario: View {
    var body: some View {
        SetuFeaturePreviewHost { environment, _ in
            AiDrawView(environment: environment)
        }
    }
}

@MainActor
struct SetuImageHubUITestScenario: View {
    var body: some View {
        SetuFeaturePreviewHost { environment, _ in
            RandomImageSwipeView(environment: environment)
        }
    }
}

@MainActor
private struct SetuNotificationPermissionUITestHarness: View {
    let environment: AppEnvironment
    @State private var pushNotifications: SystemPushCoordinator

    init(environment: AppEnvironment) {
        self.environment = environment
        let pushNotifications = SystemPushCoordinator(environment: environment)
        pushNotifications.setPreviewAuthorizationStatus(.notDetermined)
        _pushNotifications = State(initialValue: pushNotifications)
    }

    var body: some View {
        NotificationsView(environment: environment)
            .environment(pushNotifications)
            .toolbar {
                ToolbarItem {
                    Button("模拟拒绝通知") {
                        pushNotifications.setPreviewAuthorizationStatus(.denied)
                    }
                    .accessibilityIdentifier("notifications.permission.simulate-denied")
                }
            }
    }
}

@MainActor
enum SetuPreviewEnvironment {
    static func make() -> AppEnvironment {
        let keychain = SetuPreviewKeychain()
        var detailFlags = MusicFeatureFlags()
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-music-details") {
            detailFlags.artistDetailEnabled = true
            detailFlags.albumDetailEnabled = true
            detailFlags.usesV2PlaylistDetail = true
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-music-discover") {
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-radio-fm") { detailFlags.radioFMEnabled = true }
            detailFlags.usesV2Home = true; detailFlags.rankingsEnabled = true; detailFlags.newReleasesEnabled = true
            detailFlags.artistDetailEnabled = true; detailFlags.albumDetailEnabled = true; detailFlags.usesV2PlaylistDetail = true
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-music-library") {
            detailFlags.likedTracksEnabled = true; detailFlags.favoritePlaylistsEnabled = true
        }
        let config = AppConfig(
            apiBaseURL: URL(string: "https://preview.setu.invalid/")!,
            siteBaseURL: URL(string: "https://preview-site.setu.invalid/")!,
            musicFeatureFlags: detailFlags
        )
        let signer = AuthSigner(keychain: keychain)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [SetuPreviewURLProtocol.self]
        sessionConfiguration.urlCache = nil
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let invalidation = SessionInvalidationNotifier()
        let apiClient = APIClient(
            config: config,
            signer: signer,
            session: URLSession(configuration: sessionConfiguration),
            sessionInvalidationNotifier: invalidation
        )
        let authSession = AuthSession(apiClient: apiClient, keychain: keychain)
        invalidation.setHandler { [weak authSession] in await authSession?.invalidateLocalSession() }
        try? signer.persistSignSecret("preview-only-signing-secret")
        if let profile = previewProfile() {
            try? authSession.applyUserProfile(profile)
        }
        let publicClient: PublicBlogClient
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-public-example-live") {
            publicClient = PublicBlogClient(apiClient: APIClient(
                config: .production,
                signer: AuthSigner(keychain: SetuPreviewKeychain()),
                session: URLSession(configuration: .ephemeral)
            ))
        } else {
            publicClient = PublicBlogClient(apiClient: apiClient)
        }

        return AppEnvironment(
            config: config,
            keychain: keychain,
            apiClient: apiClient,
            mobileAppClient: MobileAppClient(apiClient: apiClient),
            publicBlogClient: publicClient,
            dashboardClient: DashboardClient(apiClient: apiClient),
            apiKeyClient: ApiKeyClient(apiClient: apiClient),
            pointsClient: PointsClient(apiClient: apiClient),
            imageFeedClient: ImageFeedClient(apiClient: apiClient),
            notificationClient: NotificationClient(apiClient: apiClient),
            statusClient: StatusClient(apiClient: apiClient),
            userProfileClient: UserProfileClient(apiClient: apiClient),
            passkeyClient: PasskeyClient(apiClient: apiClient),
            appleAuthClient: AppleAuthClient(apiClient: apiClient),
            collectionClient: CollectionClient(apiClient: apiClient),
            aiGenerationClient: AiGenerationClient(apiClient: apiClient),
            favoriteClient: FavoriteClient(apiClient: apiClient),
            imageDeleteRequestClient: ImageDeleteRequestClient(apiClient: apiClient),
            musicClient: MusicClient(apiClient: apiClient),
            musicV2Client: MusicV2Client(apiClient: apiClient),
            downloadClient: DownloadClient(apiClient: apiClient),
            galleryUploadClient: GalleryUploadClient(apiClient: apiClient),
            adminClient: AdminClient(apiClient: apiClient),
            authSession: authSession,
            pixivOnlineClient: PreviewPixivOnlineClient(api: apiClient)
        )
    }

    private static func previewProfile() -> UserProfile? {
        let role = ProcessInfo.processInfo.arguments.contains("-ui-testing-artwork-admin") ? 1 : 0
        let data = Data("""
        {"id":42,"email":"preview@xueliang.local","nickname":"小雪","avatarUrl":null,"role":\(role),"createdAt":"2026-01-01T00:00:00+08:00","lastLoginIp":null}
        """.utf8)
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }
}

private final class SetuPreviewKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]

    init(seed: [String: String] = [:]) {
        values = seed
    }

    func string(for key: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func setString(_ value: String, for key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func remove(_ key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}

private final class SetuPreviewURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "preview.setu.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        // Deterministic slow detail for the image continuity regression scenario.
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-artwork-continuity"),
           url.path.range(of: #"/user/(pixiv|images)/works/[^/]+$"#, options: .regularExpression) != nil {
            Thread.sleep(forTimeInterval: 3)
        }
        let fixture = SetuPreviewAPI.fixture(for: request)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: fixture.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json; charset=utf-8"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: fixture.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private enum SetuPreviewAPI {
    struct Fixture {
        let statusCode: Int
        let data: Data
    }

    static let musicSongs: [MusicSong] = [
        MusicSong(
            id: 7101,
            name: "夏夜微风",
            artists: [MusicArtist(id: 1, name: "雪涼乐队")],
            album: MusicAlbum(id: 11, name: "粉色云层"),
            duration: 238_000
        ),
        MusicSong(
            id: 7102,
            name: "沿着星光回家",
            artists: [MusicArtist(id: 2, name: "林间回声")],
            album: MusicAlbum(id: 12, name: "夜航"),
            duration: 205_000
        ),
        MusicSong(
            id: 7103,
            name: "Quiet Focus / 深度工作",
            artists: [MusicArtist(id: 3, name: "Luna Studio")],
            album: MusicAlbum(id: 13, name: "Soft Hours"),
            duration: 264_000
        ),
    ]

    private static let stateLock = NSLock()
    private static var favoriteKeys: Set<String> = []
    private static var loggedInAfterExpiry = false

    static func fixture(for request: URLRequest) -> Fixture {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let path = request.url?.path else {
            return json("{\"message\":\"无效的预览请求\"}", statusCode: 400)
        }

        if ProcessInfo.processInfo.arguments.contains("-ui-testing-music-library"), path.contains("/library") {
            let (status, data) = MusicLibraryPreviewFixtures.response(request)
            return Fixture(statusCode: status, data: data)
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-music-discover"), path.hasPrefix("/user/music/v2/") {
            let (status, data) = MusicDiscoverPreviewFixtures.response(path: path, query: request.url?.query)
            return Fixture(statusCode: status, data: data)
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-music-details"), path.hasPrefix("/user/music/v2/") {
            let (status, data) = MusicDetailPreviewFixtures.response(path: path, query: request.url?.query)
            return Fixture(statusCode: status, data: data)
        }
        if path == "/user/info", ProcessInfo.processInfo.arguments.contains("-ui-testing-artwork-admin") {
            return json("{\"id\":42,\"email\":\"preview@xueliang.local\",\"nickname\":\"小雪\",\"role\":1,\"createdAt\":\"2026-09-02T10:00:00\"}")
        }
        if path == "/admin/pixiv/crawl/illust", ProcessInfo.processInfo.arguments.contains("-ui-testing-artwork-admin") {
            return json("{\"task_id\":\"fixture-import-task\",\"status\":\"pending\"}")
        }
        if path.hasPrefix("/admin/pixiv"), ProcessInfo.processInfo.arguments.contains("-ui-testing-artwork-admin") {
            let task = "{\"task_id\":\"fixture-import-task\",\"mode\":\"ids\",\"status\":\"completed\",\"results\":[{\"pid\":1,\"expected_pages\":1,\"present_pages\":[0],\"missing_pages\":[],\"verified\":true,\"gallery_verified\":true},{\"pid\":2,\"expected_pages\":1,\"present_pages\":[],\"missing_pages\":[0],\"verified\":false,\"gallery_verified\":false,\"message\":\"上游图片暂不可用\"}]}"
            if path == "/admin/pixiv/tasks" { return json("{\"total\":1,\"tasks\":[\(task)]}") }
            if path.hasPrefix("/admin/pixiv/tasks/") { return json(task) }
            if path == "/admin/pixiv/health" { return json("{\"status\":\"ok\"}") }
        }
        if path.hasPrefix("/user/pixiv") || path.hasPrefix("/user/images") {
            if path.hasPrefix("/user/images/media/") {
                #if canImport(UIKit)
                return Fixture(statusCode: 200, data: UIImage(named: "AuthBackground")?.pngData() ?? Data())
                #else
                return Fixture(statusCode: 404, data: Data())
                #endif
            }
            if path == "/user/pixiv/account" {
                return json("{\"bound\":true,\"accountId\":\"77\",\"name\":\"小雪\",\"version\":\"fixture\"}")
            }
            let media = "/user/images/media/00000000-0000-4000-8000-000000000001?scope=gallery"
            let source = path.hasPrefix("/user/images") ? "gallery" : "pixiv"
            let artist: [String: Any] = ["id": "77", "name": "小雪", "avatarUrl": media, "followed": false]
            func work(_ id: Int) -> [String: Any] {
                let pages = (0..<(id == 1 ? 2 : 1)).map { page in
                    ["index": page, "pid": String(id), "width": 800, "height": id % 2 == 0 ? 700 : 1000,
                     "thumbnailUrl": media, "previewUrl": media, "originalUrl": media, "bookmarked": false] as [String: Any]
                }
                return ["source": source, "id": String(id), "pid": String(id), "title": "画集 \(id)", "artist": artist,
                        "kind": "illust", "pageCount": pages.count, "pages": pages, "tags": ["原创", "插画", "星穹铁道", "春天", "长标签也应该按实际文字宽度自动换行"],
                        "caption": "图片模块视觉样例，使用本站已有素材。", "bookmarked": false, "restricted": false, "aiGenerated": false]
            }
            let value: Any
            if request.httpMethod != "GET" { value = ["ok": true] }
            else if path.hasSuffix("/artists") { value = [artist] }
            else if path.hasSuffix("/spotlights") { value = [["id": "1", "title": "原创插画特辑", "thumbnailUrl": media, "url": "https://www.pixivision.net/zh/a/1"]] }
            else if path.hasSuffix("/works") { value = ["items": (1...8).map(work), "nextCursor": NSNull()] }
            else { value = work(Int(path.split(separator: "/").last ?? "1") ?? 1) }
            return Fixture(statusCode: 200, data: (try? JSONSerialization.data(withJSONObject: value)) ?? Data())
        }

        if ProcessInfo.processInfo.arguments.contains("-ui-testing-dashboard-failures"),
           dashboardFailurePaths.contains(path) {
            return json("{\"message\":\"预览中的模拟服务故障\"}", statusCode: 503)
        }

        if ProcessInfo.processInfo.arguments.contains("-ui-testing-security-failure"),
           path == "/user/apple" {
            return json("{\"message\":\"预览中的模拟服务故障\"}", statusCode: 503)
        }

        if ProcessInfo.processInfo.arguments.contains("-ui-testing-notifications-read-all-failure") {
            if path == "/notifications/read-all" {
                return json("{\"message\":\"预览中的模拟服务故障\"}", statusCode: 503)
            }
            if path == "/notifications" {
                return json(notificationPage)
            }
        }

        if ProcessInfo.processInfo.arguments.contains("-ui-testing-notifications-count-failure") {
            if path == "/notifications/unread-count" {
                return json("{\"message\":\"预览中的模拟服务故障\"}", statusCode: 503)
            }
            if path == "/notifications" {
                return json(notificationPage)
            }
        }

        if ProcessInfo.processInfo.arguments.contains("-ui-testing-notifications-read-all-stale") {
            if path == "/notifications/read-all" {
                return json("\"ok\"")
            }
            if path == "/notifications" {
                return json(notificationPage)
            }
        }

        if ProcessInfo.processInfo.arguments.contains("-ui-testing-notifications-read-all-empty-page-stale") {
            if path == "/notifications/read-all" {
                return json("\"ok\"")
            }
            if path == "/notifications" {
                return json(notificationReadPage)
            }
        }

        if ProcessInfo.processInfo.arguments.contains("-ui-testing-daily-favorite-failure"),
           path.hasPrefix("/favorite/exists/") {
            return json("{\"message\":\"预览中的模拟服务故障\"}", statusCode: 503)
        }

        if ProcessInfo.processInfo.arguments.contains("-ui-testing-points-favorite-failure"),
           path.hasPrefix("/favorite/exists/") {
            return json("{\"message\":\"预览中的模拟服务故障\"}", statusCode: 503)
        }

        if ProcessInfo.processInfo.arguments.contains("-ui-testing-random-image-favorite-failure"),
           path.hasPrefix("/favorite/exists/") {
            return json("{\"message\":\"预览中的模拟服务故障\"}", statusCode: 503)
        }

        if ProcessInfo.processInfo.arguments.contains("-ui-testing-public-ai-work-detail-404"),
           path.hasPrefix("/ai/square/") {
            return json("{\"message\":\"Not Found\"}", statusCode: 404)
        }

        if ProcessInfo.processInfo.arguments.contains("-ui-testing-feed-failure"), path == "/mobile/images/feed" {
            return json("{\"message\":\"模拟网络故障\"}", statusCode: 503)
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-welcome-failure"), path == "/blog/setu" {
            return json("{\"message\":\"模拟公开图片不可用\"}", statusCode: 503)
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-root-translate-401"),
           !loggedInAfterExpiry, path == "/ai/prompt/translate" {
            return json("{\"message\":\"登录已过期\"}", statusCode: 401)
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-root-401"),
           !loggedInAfterExpiry,
           path == "/user/info" || path == "/ai/status" || path == "/mobile/images/feed" || path == "/favorite/list" || path.hasPrefix("/user/music/") {
            return json("{\"message\":\"登录已过期\"}", statusCode: 401)
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-root-feed-expiry"), path == "/mobile/images/feed/consume" {
            return json("{\"code\":\"IMAGE_FEED_TOKEN_EXPIRED\",\"message\":\"预览过期\"}", statusCode: 404)
        }
        if path.hasPrefix("/favorite/"), request.httpMethod == "POST" || request.httpMethod == "DELETE" {
            if request.httpMethod == "POST" { favoriteKeys.insert(path) } else { favoriteKeys.remove(path) }
            return json("\"ok\"")
        }
        switch path {
        case "/auth/captcha":
            return json("{\"uuid\":\"fixture-captcha\",\"img\":\"\"}")
        case "/auth/login":
            loggedInAfterExpiry = true
            return json("{\"role\":0,\"email\":\"preview@xueliang.local\",\"userId\":42,\"signSecret\":\"fixture\",\"expireAt\":4102444800000}")
        case "/user/info":
            return json("{\"id\":42,\"email\":\"preview@xueliang.local\",\"nickname\":\"小雪\",\"role\":0,\"createdAt\":\"2026-09-02T10:00:00\"}")
        case "/collections/mine":
            return json("[{\"id\":1,\"userId\":42,\"name\":\"默认收藏\",\"visibility\":\"PRIVATE\",\"isDefault\":true},{\"id\":2,\"userId\":42,\"name\":\"灵感\",\"visibility\":\"PRIVATE\",\"isDefault\":false}]")
        case "/notifications/unread-count" where ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-ui-testing-root") }):
            return json("{\"count\":0}")
        case "/ai/prompt/translate":
            return json("{\"status\":\"COMPLETED\",\"positive\":\"silver hair, rainy street\",\"negative\":\"blur\"}")
        case "/ai/generations" where request.httpMethod == "POST":
            return json(aiJob(id: 501, prompt: "银发少女站在雨夜街角，霓虹灯倒映在路面，电影感柔光", status: "COMPLETED", reviewStatus: "PENDING", category: nil, createdAt: "2026-09-02T10:00:00+08:00"))
        case "/ai/generations/501":
            return json(aiJob(id: 501, prompt: "银发少女站在雨夜街角，霓虹灯倒映在路面，电影感柔光", status: "COMPLETED", reviewStatus: "PENDING", category: nil, createdAt: "2026-09-02T10:00:00+08:00"))
        case "/usage/overview":
            return json("""
            {"totalCalls":128,"todayCalls":4,"lastCalledAt":"2026-07-10T10:20:00+08:00"}
            """)
        case "/usage/logs":
            return json("""
            {"total":1,"list":[{"id":1,"timestamp":"2026-07-10T10:20:00+08:00","endpoint":"图片发现","status":200,"ip":"127.0.0.1"}]}
            """)
        case "/api-key/list":
            return json("{\"items\":[]}")
        case "/blog/setu":
            return json(dailyImage)
        case "/points/me":
            return json("{\"points\":86}")
        case "/setu/v2":
            return json("[\(dailyImage)]")
        case "/status/overview":
            return json("""
            {"status":{"status":"UP","availability":99.98,"avgLatencyMs":82,"callsToday":214},"health":{"status":"UP","healthy":true,"code":"OK","checkedAt":"2026-07-10T10:30:00+08:00"}}
            """)
        case "/notifications/unread-count":
            return json("{\"count\":2}")
        case "/notifications":
            return json("{\"total\":0,\"page\":1,\"pageSize\":20,\"list\":[]}")
        case "/favorite/list":
            return json(favoritePage)
        case "/ai/generations":
            return json(aiMinePage)
        case "/ai/square":
            return json(aiSquarePage)
        case let value where value.hasPrefix("/ai/square/"):
            return json(aiJob(
                id: 601,
                prompt: "粉色云层下的夏日列车",
                status: "COMPLETED",
                reviewStatus: "APPROVED",
                category: "GENERAL",
                createdAt: "2026-07-10T08:30:00+08:00"
            ))
        case "/ai/status":
            return json("""
            {"status":"AVAILABLE","online":true,"openNow":true,"available":true,"message":"创作服务运行正常","workerCount":2,"activeWorkerCount":2,"queuedCount":0,"runningCount":1,"uploadingCount":0,"estimatedWaitSeconds":25}
            """)
        case "/ai/capabilities":
            return json(aiCapabilities)
        case "/mobile/images/feed":
            return json(imageLayoutFeed ?? imageFeed)
        case let value where value.hasPrefix("/favorite/exists/"):
            return json(favoriteKeys.contains(value.replacingOccurrences(of: "/favorite/exists/", with: "/favorite/")) ? "true" : "false")
        case "/square/collections":
            return json(collectionSquarePage)
        case let value where value.hasPrefix("/square/users/"):
            return json("""
            {"id":71,"nickname":"小岛日记","avatarUrl":null,"publicCollectionCount":4,"publicAiWorkCount":4}
            """)
        case "/user/music/search/hot":
            return json(musicHotSearch)
        case "/user/music/search" where ProcessInfo.processInfo.arguments.contains("-ui-testing-music-search-pages"):
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let keyword = query.first { $0.name == "keywords" }?.value ?? "测试"
            let offset = Int(query.first { $0.name == "offset" }?.value ?? "0") ?? 0
            let limit = Int(query.first { $0.name == "limit" }?.value ?? "10") ?? 10
            let songs: [[String: Any]] = (offset..<min(offset + limit, 100)).map { index in
                ["id": 8000 + index, "name": "\(keyword) 歌曲 \(index + 1)",
                 "artists": [["id": 1, "name": "分页歌手"]], "album": ["id": 1, "name": "分页专辑"]]
            }
            let data = try! JSONSerialization.data(withJSONObject: ["result": ["songs": songs, "songCount": 100]])
            return json(String(decoding: data, as: UTF8.self))
        case "/user/music/search" where ProcessInfo.processInfo.arguments.contains("-ui-testing-music-mv"):
            return json("{\"result\":{\"songs\":\(musicSongsJSON.replacingOccurrences(of: "\"mv\":0", with: "\"mv\":99")),\"songCount\":3}}")
        case "/user/music/search":
            return json("{\"result\":{\"songs\":\(musicSongsJSON),\"songCount\":3}}")
        case "/user/music/url" where ProcessInfo.processInfo.arguments.contains("-ui-testing-lyrics-playback"):
            #if os(iOS)
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-airplay-hardware") { AirPlayFixtureCounters.requested() }
            #endif
            guard let requestURL = request.url, let audioURL = lyricPlaybackURL else {
                return json(#"{"message":"本地音频夹具不可用"}"#, statusCode: 500)
            }
            let query = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let ids = (query.first { $0.name == "id" }?.value ?? "").split(separator: ",").compactMap { Int($0) }
            let level = query.first { $0.name == "level" }?.value ?? "exhigh"
            let items: [[String: Any]] = ids.map { ["id": $0, "url": audioURL.absoluteString, "level": level, "expi": 600, "playability": "FULL", "fullPlayable": true] }
            do {
                let data = try JSONSerialization.data(withJSONObject: ["data": items])
                return Fixture(statusCode: 200, data: data)
            } catch {
                return json(#"{"message":"本地音频夹具编码失败"}"#, statusCode: 500)
            }
        case "/user/music/url" where ProcessInfo.processInfo.arguments.contains("-ui-testing-quality-unavailable"):
            return json("{\"message\":\"该音质暂不可用\"}", statusCode: 503)
        case "/user/music/personalized":
            return json(musicRecommendedPlaylists)
        case "/user/music/personalized/newsong":
            return json("{\"result\":\(musicSongsJSON)}")
        case "/user/music/recommend/songs":
            return json("{\"data\":{\"dailySongs\":\(musicSongsJSON)}}")
        case "/user/music/history":
            return json(musicHistory)
        case "/user/music/history/count":
            return json("2")
        case "/user/playlists/7401":
            return json("""
            {"id":7401,"name":"我的专注时刻","songCount":1,"playMode":"sequence","songs":[{"id":8101,"songId":7301,"songName":"夏夜微风","artistName":"预览歌手"}]}
            """)
        case "/user/playlists":
            return json(musicPlaylists)
        case "/user/music/mv/detail":
            MusicPerformanceProbe.shared.mvDetailRequested()
            return json(#"{"data":{"id":99,"name":"预览 MV","brs":[{"br":480},{"br":720}]}}"#)
        case "/user/music/mv/url":
            return json(#"{"data":null}"#)
        case "/user/music/lyric" where ProcessInfo.processInfo.arguments.contains("-ui-testing-airplay-hardware"):
            let text = (0..<900).map { String(format: "[%02d:%02d.00]隔空播放验收歌词 %d", $0 / 60, $0 % 60, $0) }.joined(separator: "\n")
            let data = try! JSONSerialization.data(withJSONObject: ["lrc": ["lyric": text], "tlyric": NSNull()])
            return Fixture(statusCode: 200, data: data)
        case "/user/music/lyric":
            return json("{\"lrc\":{\"lyric\":\"[00:00.00] 夏夜微风\\n[00:12.00] 沿着星光慢慢回家\"},\"tlyric\":null}")
        default:
            return json("{\"message\":\"此页面操作未配置离线预览\"}", statusCode: 404)
        }
    }

    /// A real silent PCM file for the opt-in lyrics success-path test. Ordinary preview errors stay unchanged.
    private static let lyricPlaybackURL: URL? = {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let seconds = ProcessInfo.processInfo.arguments.contains("-ui-testing-airplay-hardware") ? 900 : 180
        let bytes = 8_000 * 2 * seconds
        data.append(Data("RIFF".utf8)); append(UInt32(36 + bytes)); data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(UInt32(8_000))
        append(UInt32(16_000)); append(UInt16(2)); append(UInt16(16))
        data.append(Data("data".utf8)); append(UInt32(bytes))
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-airplay-hardware") {
            // A quiet generated melody, exclusively for real-output hardware acceptance.
            let notes = [220.0, 261.63, 329.63, 293.66, 261.63, 220.0, 196.0, 220.0]
            for sample in 0..<(bytes / 2) {
                let t = Double(sample) / 8000
                let frequency = notes[Int(t * 2) % notes.count]
                let envelope = min(1, (t * 2).truncatingRemainder(dividingBy: 1) * 20)
                append(Int16(sin(2 * .pi * frequency * t) * 900 * envelope))
            }
        } else { data.append(Data(repeating: 0, count: bytes)) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("setu-lyrics-playback.wav")
        do { try data.write(to: url, options: .atomic); return url }
        catch { return nil }
    }()

    private static func json(_ value: String, statusCode: Int = 200) -> Fixture {
        Fixture(statusCode: statusCode, data: Data(value.utf8))
    }

    private static let dashboardFailurePaths: Set<String> = [
        "/favorite/list",
        "/ai/generations",
        "/ai/square",
        "/notifications/unread-count",
        "/points/me",
    ]

    private static let notificationPage = """
    {
      "total":2,
      "page":1,
      "pageSize":20,
      "list":[
        {"id":41,"type":"AI_GENERATION_COMPLETED","title":"作品已经生成","content":"你的雨夜街角作品已经生成完成。","targetType":"AI_GENERATION","targetId":501,"read":false,"readAt":null,"createdAt":"2026-07-10T10:30:00+08:00"},
        {"id":42,"type":"GALLERY_SUBMISSION_APPROVED","title":"投稿审核通过","content":"你的图库投稿已经通过审核。","targetType":"GALLERY_SUBMISSION_BATCH","targetId":301,"read":false,"readAt":null,"createdAt":"2026-07-10T09:20:00+08:00"}
      ]
    }
    """

    private static let notificationReadPage = """
    {
      "total":2,
      "page":1,
      "pageSize":20,
      "list":[
        {"id":41,"type":"AI_GENERATION_COMPLETED","title":"作品已经生成","content":"你的雨夜街角作品已经生成完成。","targetType":"AI_GENERATION","targetId":501,"read":true,"readAt":"2026-07-10T10:31:00+08:00","createdAt":"2026-07-10T10:30:00+08:00"},
        {"id":42,"type":"GALLERY_SUBMISSION_APPROVED","title":"投稿审核通过","content":"你的图库投稿已经通过审核。","targetType":"GALLERY_SUBMISSION_BATCH","targetId":301,"read":true,"readAt":"2026-07-10T09:21:00+08:00","createdAt":"2026-07-10T09:20:00+08:00"}
      ]
    }
    """

    private static let dailyImage = """
    {
      "pid":5101,
      "p":0,
      "uid":61,
      "title":"清晨云海",
      "author":"浅川",
      "r18":false,
      "width":1200,
      "height":800,
      "ext":"jpg",
      "aiType":0,
      "uploadDate":1783699200,
      "tags":["云海","清晨"],
      "urls":{"regular":null,"original":null,"small":null}
    }
    """

    private static let favoritePage = """
    {
      "page":1,
      "size":4,
      "total":2,
      "items":[
        {"favoriteId":901,"imageId":301,"pid":3001,"p":0,"favoritedAt":"2026-07-09T20:10:00+08:00","image":{"id":301,"pid":3001,"p":0,"uid":31,"title":"晚霞落在海面","author":"青木","r18":0,"width":1200,"height":1600,"tags":["晚霞","海边"],"urlOriginal":null,"urlRegular":null,"urlSmall":null}},
        {"favoriteId":902,"imageId":302,"pid":3002,"p":0,"favoritedAt":"2026-07-08T18:40:00+08:00","image":{"id":302,"pid":3002,"p":0,"uid":32,"title":"雨夜车站","author":"白露","r18":0,"width":1400,"height":1050,"tags":["雨夜","城市"],"urlOriginal":null,"urlRegular":null,"urlSmall":null}}
      ]
    }
    """

    private static let aiMinePage = """
    {"total":1,"page":1,"pageSize":5,"list":[
      \(aiJob(id: 501, prompt: "雨夜街角的银发少女", status: "RUNNING", reviewStatus: "PENDING", category: nil, createdAt: "2026-07-10T09:50:00+08:00"))
    ]}
    """

    private static let aiSquarePage = """
    {"total":4,"page":1,"pageSize":16,"list":[
      \(aiJob(id: 601, prompt: "粉色云层下的夏日列车", status: "COMPLETED", reviewStatus: "APPROVED", category: "GENERAL", createdAt: "2026-07-10T08:30:00+08:00")),
      \(aiJob(id: 602, prompt: "湖畔木屋与清晨薄雾", status: "COMPLETED", reviewStatus: "APPROVED", category: "GENERAL", createdAt: "2026-07-09T21:20:00+08:00")),
      \(aiJob(id: 603, prompt: "未来城市的温柔霓虹", status: "COMPLETED", reviewStatus: "APPROVED", category: "GENERAL", createdAt: "2026-07-09T19:10:00+08:00")),
      \(aiJob(id: 604, prompt: "森林深处的玻璃花房", status: "COMPLETED", reviewStatus: "APPROVED", category: "GENERAL", createdAt: "2026-07-08T16:45:00+08:00"))
    ]}
    """

    private static func aiJob(
        id: Int,
        prompt: String,
        status: String,
        reviewStatus: String,
        category: String?,
        createdAt: String
    ) -> String {
        let encodedCategory = category.map { "\"\($0)\"" } ?? "null"
        return """
        {"id":\(id),"userId":71,"source":"IOS","promptCn":"\(prompt)","promptPositive":null,"promptNegative":null,"styleNotes":null,"width":768,"height":1024,"steps":28,"cfg":7.0,"status":"\(status)","reviewStatus":"\(reviewStatus)","publicCategory":\(encodedCategory),"publicVisible":true,"imageUrl":null,"imageWidth":768,"imageHeight":1024,"likeCount":128,"favoriteCount":42,"likedByMe":true,"favoritedByMe":false,"pointsCost":20,"pointsCharged":true,"createdAt":"\(createdAt)","updatedAt":"\(createdAt)"}
        """
    }

    private static let aiCapabilities = """
    {
      "checkpoints":[{"workerId":"preview-worker","type":"CHECKPOINT","name":"soft-pink-v1.safetensors","displayName":"柔光插画"}],
      "loras":[{"workerId":"preview-worker","type":"LORA","name":"cinematic-light.safetensors","displayName":"电影感光影"}],
      "vaes":[],
      "characters":[{"workerId":"preview-worker","type":"CHARACTER","name":"silver-hair-girl","displayName":"银发少女"}],
      "promptPresets":[],
      "workers":[{"workerId":"preview-worker","nodeName":"离线预览节点","status":"ONLINE","message":"可用"}]
    }
    """

    /// Opt-in local artwork for simulator layout checks; regular fixtures stay unchanged.
    private static var imageLayoutFeed: String? {
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing-image-layout"),
              let base = ProcessInfo.processInfo.environment["SETU_IMAGE_LAYOUT_FIXTURE_BASE_URL"],
              var payload = try? JSONSerialization.jsonObject(with: Data(imageFeed.utf8)) as? [String: Any],
              var items = payload["items"] as? [[String: Any]] else { return nil }
        for index in items.indices {
            items[index]["previewUrl"] = "\(base)/\(index).png"
        }
        items[0]["tags"] = ["星空", "湖面", "插画", "粉色晚霞", "夏日的温柔瞬间", "原创作品"]
        items[2]["width"] = 1000
        items[2]["height"] = 4000
        items[2]["title"] = "沿着山间的小路走到星空尽头，记录旅途中的每一个温柔瞬间"
        items[2]["tags"] = []
        payload["items"] = items
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static let imageFeed = """
    {
      "feedId":"preview-feed-001",
      "expiresAt":"2099-12-31T23:59:59+08:00",
      "costPerImage":20,
      "balance":86,
      "items":[
        {"token":"preview-image-1","pid":4101,"p":0,"uid":51,"title":"星光落在湖面","author":"云岚","r18":false,"width":1200,"height":1600,"tags":["星空","湖面"],"thumbnailUrl":null,"previewUrl":null},
        {"token":"preview-image-2","pid":4102,"p":0,"uid":52,"title":"夏日列车与向日葵","author":"朝雾","r18":false,"width":1600,"height":1200,"tags":["夏日","列车"],"thumbnailUrl":null,"previewUrl":null},
        {"token":"preview-image-3","pid":4103,"p":0,"uid":53,"title":"雨后街道","author":"青空","r18":false,"width":1200,"height":1200,"tags":["城市","雨后"],"thumbnailUrl":null,"previewUrl":null},
        {"token":"preview-image-4","pid":4104,"p":0,"uid":54,"title":"森林里的小屋","author":"木棉","r18":false,"width":1200,"height":1600,"tags":["森林","小屋"],"thumbnailUrl":null,"previewUrl":null}
      ]
    }
    """

    private static let collectionSquarePage = """
    {"total":4,"page":1,"pageSize":20,"list":[
      {"id":801,"userId":71,"name":"夏日与海风","description":"收集晴空、海边和缓慢移动的云。","visibility":1,"isDefault":false,"coverUrl":null,"ownerNickname":"小岛日记","itemCount":24,"shareViewCount":1280,"likeCount":96,"favoriteCount":42,"likedByMe":true,"favoritedByMe":false,"tags":["夏日","海边"]},
      {"id":802,"userId":72,"name":"雨夜电影感","description":"适合深夜慢慢看的城市光影。","visibility":1,"isDefault":false,"coverUrl":null,"ownerNickname":"微光收集者","itemCount":18,"shareViewCount":860,"likeCount":71,"favoriteCount":35,"likedByMe":false,"favoritedByMe":true,"tags":["雨夜","城市"]},
      {"id":803,"userId":73,"name":"柔软的粉色云层","description":"低饱和天空与温柔配色。","visibility":1,"isDefault":false,"coverUrl":null,"ownerNickname":"云朵便利店","itemCount":31,"shareViewCount":1560,"likeCount":132,"favoriteCount":68,"likedByMe":false,"favoritedByMe":false,"tags":["天空","粉色"]},
      {"id":804,"userId":74,"name":"林间散步指南","description":"森林、薄雾和安静的小路。","visibility":1,"isDefault":false,"coverUrl":null,"ownerNickname":"白桦","itemCount":15,"shareViewCount":640,"likeCount":54,"favoriteCount":27,"likedByMe":false,"favoritedByMe":false,"tags":["森林","自然"]}
    ]}
    """

    private static let musicHotSearch = """
    {"code":200,"result":{"hots":[
      {"first":"夏夜微风","second":100,"iconType":1},
      {"first":"深度工作","second":96,"iconType":1},
      {"first":"雨天咖啡店","second":92,"iconType":1},
      {"first":"City Pop","second":88,"iconType":0},
      {"first":"轻音乐","second":84,"iconType":0}
    ]}}
    """

    private static let musicRecommendedPlaylists = """
    {"result":[
      {"id":7201,"name":"粉色云层下的通勤歌单","picUrl":null,"playCount":12840,"description":"轻快但不打扰的工作节奏"},
      {"id":7202,"name":"雨夜与暖灯","picUrl":null,"playCount":9360,"description":"适合安静阅读的夜晚"},
      {"id":7203,"name":"周末慢慢醒来","picUrl":null,"playCount":7810,"description":"从一杯咖啡开始"}
    ]}
    """

    private static let musicSongsJSON = """
    [
      {"id":7101,"name":"夏夜微风","artists":[{"id":1,"name":"雪涼乐队"}],"album":{"id":11,"name":"粉色云层","picUrl":null},"duration":238000,"mv":0},
      {"id":7102,"name":"沿着星光回家","artists":[{"id":2,"name":"林间回声"}],"album":{"id":12,"name":"夜航","picUrl":null},"duration":205000,"mv":0},
      {"id":7103,"name":"Quiet Focus / 深度工作","artists":[{"id":3,"name":"Luna Studio"}],"album":{"id":13,"name":"Soft Hours","picUrl":null},"duration":264000,"mv":0}
    ]
    """

    private static let musicHistory = """
    [
      {"id":7301,"userId":42,"songId":7101,"songName":"夏夜微风","artistName":"雪涼乐队","albumName":"粉色云层","coverUrl":null,"duration":238000,"playTime":"2026-07-10T09:40:00+08:00"},
      {"id":7302,"userId":42,"songId":7102,"songName":"沿着星光回家","artistName":"林间回声","albumName":"夜航","coverUrl":null,"duration":205000,"playTime":"2026-07-09T22:10:00+08:00"}
    ]
    """

    private static let musicPlaylists = """
    [
      {"id":7401,"userId":42,"name":"我的专注时刻","description":"工作与阅读","coverUrl":null,"isPublic":0,"playMode":"sequence","songCount":18,"playCount":46,"createdAt":"2026-06-20T12:00:00+08:00","updatedAt":"2026-07-10T09:00:00+08:00"},
      {"id":7402,"userId":42,"name":"夜晚散步","description":"轻松、安静、有一点风","coverUrl":null,"isPublic":0,"playMode":"loop","songCount":12,"playCount":31,"createdAt":"2026-06-25T12:00:00+08:00","updatedAt":"2026-07-09T21:00:00+08:00"}
    ]
    """
}

private extension SetuPreviewFixtures {
    static let aiDrawDraft = AiDrawDraft(
        promptCn: "银发少女站在雨夜街角，霓虹灯倒映在路面，电影感柔光",
        width: 768,
        height: 1024,
        steps: 28,
        cfg: 7,
        negativePrompt: AiDrawDefaults.defaultNegativePrompt,
        updatedAt: Date(timeIntervalSince1970: 1_783_675_800)
    )
}

#endif
