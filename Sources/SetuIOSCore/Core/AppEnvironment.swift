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
    public let passkeyClient: PasskeyClient
    public let collectionClient: CollectionClient
    public let aiGenerationClient: AiGenerationClient
    public let favoriteClient: FavoriteClient
    public let imageDeleteRequestClient: ImageDeleteRequestClient
    public let musicClient: MusicClient
    public let downloadClient: DownloadClient
    public let galleryUploadClient: GalleryUploadClient
    public let adminClient: AdminClient
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
        passkeyClient: PasskeyClient,
        collectionClient: CollectionClient,
        aiGenerationClient: AiGenerationClient,
        favoriteClient: FavoriteClient,
        imageDeleteRequestClient: ImageDeleteRequestClient,
        musicClient: MusicClient,
        downloadClient: DownloadClient,
        galleryUploadClient: GalleryUploadClient,
        adminClient: AdminClient,
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
        self.passkeyClient = passkeyClient
        self.collectionClient = collectionClient
        self.aiGenerationClient = aiGenerationClient
        self.favoriteClient = favoriteClient
        self.imageDeleteRequestClient = imageDeleteRequestClient
        self.musicClient = musicClient
        self.downloadClient = downloadClient
        self.galleryUploadClient = galleryUploadClient
        self.adminClient = adminClient
        self.authSession = authSession
    }

    public static func live() -> AppEnvironment {
        let config = AppConfig.production
        let keychain = KeychainStore(service: "com.xueliang.setu-ios")
        let signer = AuthSigner(keychain: keychain)
        let sessionInvalidationNotifier = SessionInvalidationNotifier()
        let client = APIClient(
            config: config,
            signer: signer,
            session: APIClient.liveSession(),
            sessionInvalidationNotifier: sessionInvalidationNotifier
        )
        let mobileAppClient = MobileAppClient(apiClient: client)
        let dashboardClient = DashboardClient(apiClient: client)
        let apiKeyClient = ApiKeyClient(apiClient: client)
        let pointsClient = PointsClient(apiClient: client)
        let notificationClient = NotificationClient(apiClient: client)
        let statusClient = StatusClient(apiClient: client)
        let userProfileClient = UserProfileClient(apiClient: client)
        let passkeyClient = PasskeyClient(apiClient: client)
        let collectionClient = CollectionClient(apiClient: client)
        let aiGenerationClient = AiGenerationClient(apiClient: client)
        let favoriteClient = FavoriteClient(apiClient: client)
        let imageDeleteRequestClient = ImageDeleteRequestClient(apiClient: client)
        let musicClient = MusicClient(apiClient: client)
        let downloadClient = DownloadClient(apiClient: client)
        let galleryUploadClient = GalleryUploadClient(apiClient: client)
        let adminClient = AdminClient(apiClient: client)
        let session = AuthSession(apiClient: client, keychain: keychain)
        sessionInvalidationNotifier.setHandler { [weak session] in
            await session?.invalidateLocalSession()
        }
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
            passkeyClient: passkeyClient,
            collectionClient: collectionClient,
            aiGenerationClient: aiGenerationClient,
            favoriteClient: favoriteClient,
            imageDeleteRequestClient: imageDeleteRequestClient,
            musicClient: musicClient,
            downloadClient: downloadClient,
            galleryUploadClient: galleryUploadClient,
            adminClient: adminClient,
            authSession: session
        )
    }
}
