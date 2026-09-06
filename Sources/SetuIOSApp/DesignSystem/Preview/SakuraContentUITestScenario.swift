#if DEBUG
import Foundation
import SetuIOSCore
import SwiftUI

/// Real pages, opt-in private transport, and explicit applicable state semantics.
@MainActor
struct SakuraContentUITestScenario: View {
    @State private var index: Int = {
        guard let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-sakura-content-start"),
              ProcessInfo.processInfo.arguments.indices.contains(i + 1),
              let n = Int(ProcessInfo.processInfo.arguments[i + 1]) else { return 0 }
        return n
    }()
    static let matrix: [(page: String, states: [String])] = [
        ("AiHistoryView", ["loading", "empty", "failed", "loaded"]),
        ("AiSquareView", ["loading", "empty", "failed", "loaded"]),
        ("AiAssetBrowserView", ["loading", "empty", "failed", "loaded"]),
        ("FavoriteListView", ["loading", "empty", "failed", "loaded"]),
        ("CollectionListView", ["loading", "empty", "failed", "loaded"]),
        ("CollectionDetailView", ["loading", "empty-items", "metadata-failed", "items-failed", "loaded"]),
        ("CollectionSquareView", ["loading", "empty", "failed", "loaded"]),
        ("PublicCollectionDetailView", ["loading", "empty-items", "metadata-failed", "items-failed", "loaded"]),
        ("PublicUserProfileView", ["loading", "empty-public-content", "failed", "loaded"]),
        ("GalleryUploadBatchesView", ["loading", "empty", "failed", "loaded"]),
        ("GalleryUploadDetailView", ["loading", "empty-items", "failed", "loaded"]),
        ("ImageDeleteRequestsView", ["loading", "empty", "failed", "loaded"]),
        ("ImageDeleteRequestDetailView", ["loading", "failed", "loaded"]),
        ("AiDeleteRequestsView", ["loading", "empty", "failed", "loaded"]),
        ("PointsLogsView", ["loading", "empty", "failed", "loaded"]),
        ("ApiKeyListView", ["loading", "empty", "failed", "loaded"]),
        ("PointsCallView", ["loading", "zero-balance", "failed", "loaded", "results-loading", "results-empty", "results-failed", "results-loaded"]),
        ("AiGenerationDetailView", ["loading", "failed", "loaded"]),
        ("PublicAiWorkDetailView", ["snapshot-pending", "snapshot-failed", "unavailable", "loaded"]),
        ("MusicPlaylistDetailView", ["loading", "empty-items", "failed", "loaded"]),
        ("MusicHistoryView", ["loading", "empty", "failed", "loaded"]),
        ("MusicSearchView", ["loading", "empty", "failed", "loaded"]),
        ("MusicPlaylistsView", ["loading", "empty", "failed", "loaded"]),
        ("PlaylistSelectionSheet", ["loading", "empty", "failed", "loaded"]),
        ("MusicMvSheet", ["loading", "no-mv", "failed", "detail-media-unavailable"]),
        ("CollectionEditorSheet", ["create-empty", "edit-filled"]),
        ("AccountView", ["loading", "unbound", "failed", "loaded", "auth-landing", "auth-login", "auth-register", "auth-recovery", "auth-password-reset"]),
        ("ProfileView", ["loading", "failed", "loaded"]),
        ("SecuritySettingsView", ["loading", "unbound", "failed", "loaded"]),
        ("PasskeyListView", ["loading", "empty", "failed", "loaded"]),
        ("QqBindingView", ["loading", "unbound", "failed", "loaded"]),
        ("NotificationsView", ["loading", "empty", "failed", "loaded"]),
        ("SystemStatusView", ["loading", "failed", "loaded"]),
        ("StaticInfoView", ["loading", "empty", "failed", "loaded", "about", "privacy", "terms"]),
    ]
    static var selections: [(page: String, state: String)] {
        matrix.flatMap { row in row.states.map { (row.page, $0) } }
    }
    var body: some View {
        let selections = Self.selections
        let selection = selections[min(max(index, 0), selections.count - 1)]
        SakuraContentPageHost(page: selection.page, state: selection.state)
            .id(index)
            .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("UICTContentSizeCategoryAccessibilityXXXL") ? .accessibility5 :
                             ProcessInfo.processInfo.arguments.contains("UICTContentSizeCategoryAccessibilityM") ? .accessibility1 : .large)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Text("\(selection.page) / \(selection.state)").font(.caption2)
                        .accessibilityIdentifier("sakura.content.current")
                    Spacer()
                    Button { index = (index + 1) % selections.count } label: {
                        Text("下一项")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                        .accessibilityIdentifier("sakura.content.next")
                }
                .dynamicTypeSize(.large)
                .padding(.horizontal, 12)
                .background(.regularMaterial)
            }
    }
}

@MainActor
private struct SakuraContentPageHost: View {
    let page: String
    let state: String
    @State private var context: SakuraContentContext?
    var body: some View {
        Group {
            if let context { context.screen(page: page, state: state) }
            else { ProgressView().task { if context == nil { context = SakuraContentContext(page: page, state: state) } } }
        }
    }
}

@MainActor
private struct SakuraContentContext {
    let environment: AppEnvironment
    let player: MusicPlaybackController
    let store: MusicStore
    let router = RouterPath()
    let navigation = AppNavigationCoordinator()
    let push: SystemPushCoordinator
    let evidence: String
    init(page: String, state: String) {
        AiAssetBrowserCacheStore.activatePreviewStorage()
        AiDrawDraftStore.activatePreviewStorage(with: AiDrawDraft())
        do {
            evidence = try SakuraContentFixtures.validateAll()
            environment = try SakuraContentEnvironment.make(state: state, page: page)
        } catch { preconditionFailure("Content fixture failed validation: \(error)") }
        let preferences = UserDefaults(suiteName: "icu.yukiryou.setu.sakura-content-player.\(UUID().uuidString)")!
        player = MusicPlaybackController(persistsPlayback: false, preferences: preferences)
        store = MusicStore(client: environment.musicClient, userID: environment.authSession.currentUser?.id)
        push = SystemPushCoordinator(environment: environment)
        push.setPreviewAuthorizationStatus(.denied)
    }
    func screen(page: String, state: String) -> some View {
        Group {
            if ["PlaylistSelectionSheet", "CollectionEditorSheet", "MusicMvSheet"].contains(page) {
                content(page: page, state: state)
            } else {
                NavigationStack { content(page: page, state: state) }
            }
        }
        .environment(router).environment(navigation).environment(push).environment(store)
        .tint(SetuColor.brandPink)
        .overlay(alignment: .topLeading) {
            Color.clear.frame(width: 1, height: 1).accessibilityElement()
                .accessibilityLabel(evidence).accessibilityIdentifier("sakura.content.dtoEvidence")
        }
    }
    @ViewBuilder private func content(page: String, state: String) -> some View {
        switch page {
        case "AiHistoryView": AiHistoryView(environment: environment)
        case "AiSquareView": AiSquareView(environment: environment)
        case "AiAssetBrowserView": AiAssetBrowserView(environment: environment)
        case "FavoriteListView": FavoriteListView(environment: environment)
        case "CollectionListView": CollectionListView(environment: environment)
        case "CollectionDetailView": CollectionDetailView(environment: environment, collectionID: 1)
        case "CollectionSquareView": CollectionSquareView(environment: environment)
        case "PublicCollectionDetailView": PublicCollectionDetailView(environment: environment, collectionID: 1)
        case "PublicUserProfileView": PublicUserProfileView(environment: environment, userID: 42)
        case "GalleryUploadBatchesView": GalleryUploadBatchesView(environment: environment)
        case "GalleryUploadDetailView": GalleryUploadDetailView(environment: environment, batchID: 1)
        case "ImageDeleteRequestsView": ImageDeleteRequestsView(environment: environment)
        case "ImageDeleteRequestDetailView": ImageDeleteRequestDetailView(environment: environment, requestID: 1)
        case "AiDeleteRequestsView": AiDeleteRequestsView(environment: environment)
        case "PointsLogsView": PointsLogsView(environment: environment)
        case "ApiKeyListView": ApiKeyListView(environment: environment)
        case "PointsCallView": PointsCallView(environment: environment)
        case "AiGenerationDetailView": AiGenerationDetailView(environment: environment, jobID: 9700501)
        case "PublicAiWorkDetailView": PublicAiWorkDetailView(environment: environment, work: PublicAiWorkSnapshot(id: 9700501, ownerUserID: 42, imageURLString: nil, prompt: "樱潮初始作品快照", width: 768, height: 1024, category: "GENERAL", createdAt: nil, likeCount: 0, favoriteCount: 0, likedByMe: false, favoritedByMe: false))
        case "MusicPlaylistDetailView": MusicPlaylistDetailView(environment: environment, player: player, playlistID: 7401)
        case "MusicHistoryView": MusicHistoryView(environment: environment, player: player)
        case "MusicSearchView": MusicSearchView(environment: environment, player: player, initialQuery: "夏夜")
        case "MusicPlaylistsView": MusicPlaylistsView(environment: environment, player: player)
        case "PlaylistSelectionSheet": PlaylistSelectionSheet(presentation: .song, requests: [AddSongToPlaylistRequest(song: MusicSong(id: 7101, name: "夏夜微风"))], onAdded: { _ in }) { Text("夏夜微风") }
        case "MusicMvSheet": MusicMvSheet(environment: environment, player: player, song: MusicSong(id: 7101, name: "夏夜微风", mv: state == "no-mv" ? 0 : 99))
        case "CollectionEditorSheet": CollectionEditorSheet(environment: environment, context: state == "create-empty" ? .create : .edit(SakuraContentFixtures.decode(CollectionInfo.self, path: "/collections/1")), onSaved: {})
        case "AccountView": AccountView(environment: environment, initialAuthPage: state == "auth-login" ? .login : state == "auth-register" ? .register : state == "auth-recovery" ? .recovery : state == "auth-password-reset" ? .passwordReset : .landing)
        case "ProfileView": ProfileView(environment: environment)
        case "SecuritySettingsView": SecuritySettingsView(environment: environment)
        case "PasskeyListView": PasskeyListView(environment: environment)
        case "QqBindingView": QqBindingView(environment: environment)
        case "NotificationsView": NotificationsView(environment: environment)
        case "SystemStatusView": SystemStatusView(environment: environment)
        case "StaticInfoView": StaticInfoView(environment: environment, kind: state == "about" ? .about : state == "privacy" ? .privacy : state == "terms" ? .terms : .docs)
        default: Text("未知验收页面")
        }
    }
}

@MainActor
private enum SakuraContentEnvironment {
    static func make(state: String, page: String) throws -> AppEnvironment {
        precondition(ProcessInfo.processInfo.arguments.contains("-ui-testing-sakura-content"))
        let keychain = SakuraContentKeychain()
        let config = AppConfig(apiBaseURL: URL(string: "https://\(state).\(page.lowercased()).sakura-content.invalid/")!,
                               siteBaseURL: URL(string: "https://sakura-content.invalid/")!)
        let signer = AuthSigner(keychain: keychain)
        try signer.persistSignSecret("sakura-content-fixture-only")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SakuraContentURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 3600
        configuration.timeoutIntervalForResource = 3600
        let apiClient = APIClient(config: config, signer: signer, session: URLSession(configuration: configuration))
        let authSession = AuthSession(apiClient: apiClient, keychain: keychain)
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(
            #"{"id":42,"email":"qa@example.invalid","nickname":"樱潮测试用户","role":0,"createdAt":"2026-09-01T08:30:00+08:00"}"#.utf8))
        if !state.hasPrefix("auth-") { try authSession.applyUserProfile(profile) }
        return AppEnvironment(
            config: config,
            keychain: keychain,
            apiClient: apiClient,
            mobileAppClient: MobileAppClient(apiClient: apiClient),
            publicBlogClient: PublicBlogClient(apiClient: apiClient),
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
            authSession: authSession
        )
    }
}

private final class SakuraContentKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    func string(for key: String) throws -> String? { lock.withLock { values[key] } }
    func setString(_ value: String, for key: String) throws { lock.withLock { values[key] = value } }
    func remove(_ key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
}

private final class SakuraContentURLProtocol: URLProtocol {
    // Intercept every request made by this private session, including accidental
    // external URLs. Never forward to another session or perform network I/O.
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.httpMethod == "GET",
              let url = request.url, url.host?.hasSuffix(".sakura-content.invalid") == true,
              let entry = SakuraContentFixtures.entries.first(where: { $0.path == url.path }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let state = url.host?.components(separatedBy: ".").first
        if state == "loading" || state == "snapshot-pending" || (state == "results-loading" && url.path == "/setu/v2") { return } // Suspended only in this DEBUG transport.
        let isItemPath = url.path.hasSuffix("/items")
        let failedItem = state == "items-failed" && isItemPath
        let failedMetadata = state == "metadata-failed" && !isItemPath
        if state == "failed" || state == "snapshot-failed" || (state == "results-failed" && url.path == "/setu/v2") || failedItem || failedMetadata {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        if state == "unavailable" {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"message":"作品已下架"}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let empty = ["empty", "empty-items", "empty-public-content", "unbound", "zero-balance"].contains(state ?? "") || (state == "results-empty" && url.path == "/setu/v2")
        let data = Data((empty ? entry.empty : entry.loaded).utf8)
        do { try entry.validate(data) } catch {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
