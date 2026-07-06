import Foundation

@MainActor
@Observable
public final class AppEnvironment {
    public let config: AppConfig
    public let keychain: KeychainStoring
    public let apiClient: APIClient
    public let mobileAppClient: MobileAppClient
    public let authSession: AuthSession

    public init(
        config: AppConfig,
        keychain: KeychainStoring,
        apiClient: APIClient,
        mobileAppClient: MobileAppClient,
        authSession: AuthSession
    ) {
        self.config = config
        self.keychain = keychain
        self.apiClient = apiClient
        self.mobileAppClient = mobileAppClient
        self.authSession = authSession
    }

    public static func live() -> AppEnvironment {
        let config = AppConfig.production
        let keychain = KeychainStore(service: "com.xueliang.setu-ios")
        let signer = AuthSigner(keychain: keychain)
        let client = APIClient(config: config, signer: signer)
        let mobileAppClient = MobileAppClient(apiClient: client)
        let session = AuthSession(apiClient: client, keychain: keychain)
        return AppEnvironment(
            config: config,
            keychain: keychain,
            apiClient: client,
            mobileAppClient: mobileAppClient,
            authSession: session
        )
    }
}
