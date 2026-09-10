import Foundation

@MainActor
@Observable
public final class AppEnvironment {
    public let config: AppConfig
    public let keychain: KeychainStoring
    public let apiClient: APIClient
    public let mobileAppClient: MobileAppClient
    public let publicBlogClient: PublicBlogClient
    public let dashboardClient: DashboardClient
    public let apiKeyClient: ApiKeyClient
    public let pointsClient: PointsClient
    private let suppliedPixivClient: (any PixivOnlineServing)?
    private var localPixivClient: (owner: String, client: PixivLocalClient)?
    public var artworkClient: ArtworkClient {
        if let suppliedPixivClient { return ArtworkClient(apiClient: apiClient, online: suppliedPixivClient) }
        guard let id = authSession.currentUser?.id else { return ArtworkClient(apiClient: apiClient) }
        let owner = String(id)
        if localPixivClient?.owner != owner { localPixivClient = (owner, PixivLocalClient(owner: owner, keychain: keychain, imageHost: { .current })) }
        return ArtworkClient(apiClient: apiClient, online: localPixivClient?.client)
    }
    public let imageFeedClient: ImageFeedClient
    public let notificationClient: NotificationClient
    public let statusClient: StatusClient
    public let userProfileClient: UserProfileClient
    public let passkeyClient: PasskeyClient
    public let appleAuthClient: AppleAuthClient
    public let collectionClient: CollectionClient
    public let aiGenerationClient: AiGenerationClient
    public let favoriteClient: FavoriteClient
    public let moduleFavoriteClient: ModuleFavoriteClient
    public let asmrCatalogClient: AsmrCatalogClient
    public let jmCatalogClient: JmCatalogClient
    public let imageDeleteRequestClient: ImageDeleteRequestClient
    public let musicClient: MusicClient
    public let musicV2Client: MusicV2Client
    public let downloadClient: DownloadClient
    public let galleryUploadClient: GalleryUploadClient
    public let adminClient: AdminClient
    public let authSession: AuthSession

    public init(
        config: AppConfig,
        keychain: KeychainStoring,
        apiClient: APIClient,
        mobileAppClient: MobileAppClient,
        publicBlogClient: PublicBlogClient,
        dashboardClient: DashboardClient,
        apiKeyClient: ApiKeyClient,
        pointsClient: PointsClient,
        imageFeedClient: ImageFeedClient,
        notificationClient: NotificationClient,
        statusClient: StatusClient,
        userProfileClient: UserProfileClient,
        passkeyClient: PasskeyClient,
        appleAuthClient: AppleAuthClient,
        collectionClient: CollectionClient,
        aiGenerationClient: AiGenerationClient,
        favoriteClient: FavoriteClient,
        moduleFavoriteClient: ModuleFavoriteClient? = nil,
        asmrCatalogClient: AsmrCatalogClient = AsmrCatalogClient(),
        jmCatalogClient: JmCatalogClient = JmCatalogClient(),
        imageDeleteRequestClient: ImageDeleteRequestClient,
        musicClient: MusicClient,
        musicV2Client: MusicV2Client,
        downloadClient: DownloadClient,
        galleryUploadClient: GalleryUploadClient,
        adminClient: AdminClient,
        authSession: AuthSession,
        pixivOnlineClient: (any PixivOnlineServing)? = nil
    ) {
        self.config = config
        self.keychain = keychain
        self.apiClient = apiClient
        self.mobileAppClient = mobileAppClient
        self.publicBlogClient = publicBlogClient
        self.dashboardClient = dashboardClient
        self.apiKeyClient = apiKeyClient
        self.pointsClient = pointsClient
        self.imageFeedClient = imageFeedClient
        self.notificationClient = notificationClient
        self.statusClient = statusClient
        self.userProfileClient = userProfileClient
        self.passkeyClient = passkeyClient
        self.appleAuthClient = appleAuthClient
        self.collectionClient = collectionClient
        self.aiGenerationClient = aiGenerationClient
        self.favoriteClient = favoriteClient
        self.moduleFavoriteClient = moduleFavoriteClient ?? ModuleFavoriteClient(apiClient: apiClient)
        self.asmrCatalogClient = asmrCatalogClient
        self.jmCatalogClient = jmCatalogClient
        self.imageDeleteRequestClient = imageDeleteRequestClient
        self.musicClient = musicClient
        self.musicV2Client = musicV2Client
        self.downloadClient = downloadClient
        self.galleryUploadClient = galleryUploadClient
        self.adminClient = adminClient
        self.authSession = authSession
        self.suppliedPixivClient = pixivOnlineClient
    }

    public static func live() -> AppEnvironment {
        let config = AppConfig.resolved()
        let keychain = KeychainStore(service: "com.xueliang.setu-ios")
        let signer = AuthSigner(keychain: keychain)
        let sessionInvalidationNotifier = SessionInvalidationNotifier()
        let signatureRefreshNotifier = SignatureRefreshNotifier()
        let client = APIClient(
            config: config,
            signer: signer,
            session: APIClient.liveSession(),
            sessionInvalidationNotifier: sessionInvalidationNotifier,
            signatureRefreshNotifier: signatureRefreshNotifier
        )
        let mobileAppClient = MobileAppClient(apiClient: client)
        let publicBlogClient = PublicBlogClient(apiClient: client)
        let dashboardClient = DashboardClient(apiClient: client)
        let apiKeyClient = ApiKeyClient(apiClient: client)
        let pointsClient = PointsClient(apiClient: client)
        let imageFeedClient = ImageFeedClient(apiClient: client)
        let notificationClient = NotificationClient(apiClient: client)
        let statusClient = StatusClient(apiClient: client)
        let userProfileClient = UserProfileClient(apiClient: client)
        let passkeyClient = PasskeyClient(apiClient: client)
        let appleAuthClient = AppleAuthClient(apiClient: client)
        let collectionClient = CollectionClient(apiClient: client)
        let aiGenerationClient = AiGenerationClient(apiClient: client)
        let favoriteClient = FavoriteClient(apiClient: client)
        let imageDeleteRequestClient = ImageDeleteRequestClient(apiClient: client)
        let musicClient = MusicClient(apiClient: client)
        let musicV2Client = MusicV2Client(apiClient: client)
        let downloadClient = DownloadClient(apiClient: client)
        let galleryUploadClient = GalleryUploadClient(apiClient: client)
        let adminClient = AdminClient(apiClient: client)
        let session = AuthSession(apiClient: client, keychain: keychain)
        sessionInvalidationNotifier.setHandler { [weak session] in
            await session?.invalidateLocalSession()
        }
        signatureRefreshNotifier.setHandler { [weak session] in
            await session?.refreshSignature() ?? false
        }
        return AppEnvironment(
            config: config,
            keychain: keychain,
            apiClient: client,
            mobileAppClient: mobileAppClient,
            publicBlogClient: publicBlogClient,
            dashboardClient: dashboardClient,
            apiKeyClient: apiKeyClient,
            pointsClient: pointsClient,
            imageFeedClient: imageFeedClient,
            notificationClient: notificationClient,
            statusClient: statusClient,
            userProfileClient: userProfileClient,
            passkeyClient: passkeyClient,
            appleAuthClient: appleAuthClient,
            collectionClient: collectionClient,
            aiGenerationClient: aiGenerationClient,
            favoriteClient: favoriteClient,
            moduleFavoriteClient: ModuleFavoriteClient(apiClient: client),
            asmrCatalogClient: AsmrCatalogClient(),
            jmCatalogClient: JmCatalogClient(),
            imageDeleteRequestClient: imageDeleteRequestClient,
            musicClient: musicClient,
            musicV2Client: musicV2Client,
            downloadClient: downloadClient,
            galleryUploadClient: galleryUploadClient,
            adminClient: adminClient,
            authSession: session
        )
    }

    public func logout() async {
        if let deviceID = try? keychain.string(for: "pushDeviceId"), !deviceID.isEmpty {
            try? await mobileAppClient.disableDevice(deviceId: deviceID)
        }
        await authSession.logout()
    }
}
