import Foundation

@MainActor
@Observable
public final class AppEnvironment {
    public let config: AppConfig
    public let keychain: KeychainStoring
    public let apiClient: APIClient
    public let mobileAppClient: MobileAppClient
    public let dashboardClient: DashboardClient
    public let apiKeyClient: ApiKeyClient
    public let pointsClient: PointsClient
    public let notificationClient: NotificationClient
    public let statusClient: StatusClient
    public let authSession: AuthSession

    public init(
        config: AppConfig,
        keychain: KeychainStoring,
        apiClient: APIClient,
        mobileAppClient: MobileAppClient,
        dashboardClient: DashboardClient,
        apiKeyClient: ApiKeyClient,
        pointsClient: PointsClient,
        notificationClient: NotificationClient,
        statusClient: StatusClient,
        authSession: AuthSession
    ) {
        self.config = config
        self.keychain = keychain
        self.apiClient = apiClient
        self.mobileAppClient = mobileAppClient
        self.dashboardClient = dashboardClient
        self.apiKeyClient = apiKeyClient
        self.pointsClient = pointsClient
        self.notificationClient = notificationClient
        self.statusClient = statusClient
        self.authSession = authSession
    }

    public static func live() -> AppEnvironment {
        let config = AppConfig.production
        let keychain = KeychainStore(service: "com.xueliang.setu-ios")
        let signer = AuthSigner(keychain: keychain)
        let client = APIClient(config: config, signer: signer)
        let mobileAppClient = MobileAppClient(apiClient: client)
        let dashboardClient = DashboardClient(apiClient: client)
        let apiKeyClient = ApiKeyClient(apiClient: client)
        let pointsClient = PointsClient(apiClient: client)
        let notificationClient = NotificationClient(apiClient: client)
        let statusClient = StatusClient(apiClient: client)
        let session = AuthSession(apiClient: client, keychain: keychain)
        return AppEnvironment(
            config: config,
            keychain: keychain,
            apiClient: client,
            mobileAppClient: mobileAppClient,
            dashboardClient: dashboardClient,
            apiKeyClient: apiKeyClient,
            pointsClient: pointsClient,
            notificationClient: notificationClient,
            statusClient: statusClient,
            authSession: session
        )
    }
}
