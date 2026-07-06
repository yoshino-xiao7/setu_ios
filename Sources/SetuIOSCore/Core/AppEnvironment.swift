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
    public let userProfileClient: UserProfileClient
    public let collectionClient: CollectionClient
    public let aiGenerationClient: AiGenerationClient
    public let favoriteClient: FavoriteClient
    public let imageDeleteRequestClient: ImageDeleteRequestClient
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
        userProfileClient: UserProfileClient,
        collectionClient: CollectionClient,
        aiGenerationClient: AiGenerationClient,
        favoriteClient: FavoriteClient,
        imageDeleteRequestClient: ImageDeleteRequestClient,
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
        self.userProfileClient = userProfileClient
        self.collectionClient = collectionClient
        self.aiGenerationClient = aiGenerationClient
        self.favoriteClient = favoriteClient
        self.imageDeleteRequestClient = imageDeleteRequestClient
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
        let userProfileClient = UserProfileClient(apiClient: client)
        let collectionClient = CollectionClient(apiClient: client)
        let aiGenerationClient = AiGenerationClient(apiClient: client)
        let favoriteClient = FavoriteClient(apiClient: client)
        let imageDeleteRequestClient = ImageDeleteRequestClient(apiClient: client)
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
            userProfileClient: userProfileClient,
            collectionClient: collectionClient,
            aiGenerationClient: aiGenerationClient,
            favoriteClient: favoriteClient,
            imageDeleteRequestClient: imageDeleteRequestClient,
            authSession: session
        )
    }
}
