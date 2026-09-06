#if DEBUG
import Foundation
import SetuIOSCore
import SwiftUI

/// Explicit opt-in UI-test gallery. Every selection creates an isolated session
/// and mounts the actual production page; no production view state is injected.
@MainActor
struct SakuraAdminUITestScenario: View {
    @State private var index = 0
    private let states = ["loading", "empty", "failed", "loaded"]
    private let pages = ["Overview", "Users", "Blacklist", "MusicTokens", "OperationLogs", "PixivCrawl", "ImageAudit", "GallerySubmissions", "ImageDeleteRequests", "ImageInfo", "AiGenerations", "AiReviews", "AiDeleteRequests", "AiWorkers"]

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let position = arguments.firstIndex(of: "-sakura-admin-start-page")
        let start = position.flatMap { $0 + 1 < arguments.count ? Int(arguments[$0 + 1]) : nil } ?? 0
        _index = State(initialValue: min(max(start, 0), 13) * 4)
    }

    var body: some View {
        let page = pages[index / states.count]
        let state = states[index % states.count]
        SakuraAdminPageHost(page: page, state: state)
            .id(index)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Text("\(page) / \(state)").font(.caption2)
                        .accessibilityIdentifier("sakura.admin.current")
                    Spacer()
                    Button { index = (index + 1) % (pages.count * states.count) } label: {
                        Text("下一项")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                        .accessibilityIdentifier("sakura.admin.next")
                }
                .dynamicTypeSize(.large) // Keep test controls at 44pt; the page still uses the requested size.
                .padding(.horizontal, 12)
                .background(.regularMaterial)
            }
    }
}

@MainActor
private struct SakuraAdminPageHost: View {
    let page: String
    let state: String
    private let environment: AppEnvironment
    private let validation: String
    private let router = RouterPath()

    init(page: String, state: String) {
        self.page = page
        self.state = state
        do {
            validation = try SakuraAdminFixtures.validateAll()
            environment = try SakuraAdminEnvironment.make(state: state)
        } catch {
            preconditionFailure("Admin fixture validation failed: \(error)")
        }
    }

    var body: some View {
        NavigationStack {
            content
        }
        .environment(router)
        .tint(SetuColor.brandPink)
        .overlay(alignment: .topLeading) {
            // Machine-readable manifest, kept out of the visible page layout.
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel(validation)
                .accessibilityIdentifier("sakura.admin.dtoEvidence")
        }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case "Overview": AdminOverviewView(environment: environment)
        case "Users": AdminUsersView(environment: environment)
        case "Blacklist": AdminBlacklistView(environment: environment)
        case "MusicTokens": AdminMusicTokensView(environment: environment)
        case "OperationLogs": AdminOperationLogsView(environment: environment)
        case "PixivCrawl": AdminPixivCrawlView(environment: environment)
        case "ImageAudit": AdminImageAuditView(environment: environment)
        case "GallerySubmissions": AdminGallerySubmissionsView(environment: environment)
        case "ImageDeleteRequests": AdminImageDeleteRequestsView(environment: environment)
        case "ImageInfo": AdminImageInfoView(environment: environment, initialPID: state == "empty" ? nil : 901)
        case "AiGenerations": AdminAiGenerationsView(environment: environment)
        case "AiReviews": AdminAiReviewsView(environment: environment)
        case "AiDeleteRequests": AdminAiDeleteRequestsView(environment: environment)
        case "AiWorkers": AdminAiWorkersView(environment: environment)
        default: Text("未知验收页面")
        }
    }
}

@MainActor
private enum SakuraAdminEnvironment {
    static func make(state: String) throws -> AppEnvironment {
        precondition(ProcessInfo.processInfo.arguments.contains("-ui-testing-sakura-admin"))
        let keychain = SakuraAdminKeychain()
        let config = AppConfig(apiBaseURL: URL(string: "https://\(state).sakura-admin.invalid/")!,
                               siteBaseURL: URL(string: "https://sakura-admin.invalid/")!)
        let signer = AuthSigner(keychain: keychain)
        try signer.persistSignSecret("sakura-admin-fixture-only")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SakuraAdminURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 3600
        configuration.timeoutIntervalForResource = 3600
        let apiClient = APIClient(config: config, signer: signer, session: URLSession(configuration: configuration))
        let authSession = AuthSession(apiClient: apiClient, keychain: keychain)
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(
            #"{"id":42,"email":"qa@example.invalid","nickname":"樱潮验收管理员","role":1,"createdAt":"2026-09-01T08:30:00+08:00"}"#.utf8))
        try authSession.applyUserProfile(profile)
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

private final class SakuraAdminKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    func string(for key: String) throws -> String? { lock.withLock { values[key] } }
    func setString(_ value: String, for key: String) throws { lock.withLock { values[key] = value } }
    func remove(_ key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
}

private final class SakuraAdminURLProtocol: URLProtocol {
    // Intercept every request made by this private session, including accidental
    // external URLs. Never forward to another session or perform network I/O.
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.httpMethod == "GET",
              let url = request.url, url.host?.hasSuffix(".sakura-admin.invalid") == true,
              let entry = SakuraAdminFixtures.entries.first(where: { $0.path == url.path }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let state = url.host?.components(separatedBy: ".").first
        if state == "loading" { return } // Suspended only in this DEBUG transport.
        if state == "failed" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let data = Data((state == "empty" ? entry.empty : entry.loaded).utf8)
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
