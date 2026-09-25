import Foundation

@MainActor
@Observable
public final class NeteaseMusicSession {
    private let apiClient: NeteaseMusicApiClient
    private let keychain: KeychainStoring
    private let cookieKey = "netease_cookie"
    private let profileKey = "netease_profile"

    public var cookie: String?
    public var profile: NeteaseUserProfile?
    public var playlists: [NeteaseUserPlaylist] = []
    public var isLoadingPlaylists: Bool = false
    public var lastError: String?

    public init(apiClient: NeteaseMusicApiClient, keychain: KeychainStoring) {
        self.apiClient = apiClient
        self.keychain = keychain
        restoreSession()
    }

    public var isLoggedIn: Bool {
        guard let cookie, !cookie.isEmpty else { return false }
        return profile != nil
    }

    public var isVIP: Bool {
        profile?.isVIP == true
    }

    // MARK: Session Persistence

    public func restoreSession() {
        do {
            if let savedCookie = try keychain.string(for: cookieKey), !savedCookie.isEmpty {
                self.cookie = savedCookie
                if let profileData = UserDefaults.standard.data(forKey: profileKey),
                   let savedProfile = try? JSONDecoder().decode(NeteaseUserProfile.self, from: profileData) {
                    self.profile = savedProfile
                }
                Task {
                    await refreshProfileAndPlaylists()
                }
            }
        } catch {
            lastError = "恢复网易云登录态失败：\(error.localizedDescription)"
        }
    }

    public func loginWithCookie(_ newCookie: String) async {
        do {
            try keychain.setString(newCookie, for: cookieKey)
            self.cookie = newCookie
            await refreshProfileAndPlaylists()
        } catch {
            lastError = "保存登录凭证失败"
        }
    }

    public func refreshProfileAndPlaylists() async {
        guard let cookie, !cookie.isEmpty else { return }
        do {
            if let newProfile = try await apiClient.fetchLoginStatus(cookie: cookie) {
                self.profile = newProfile
                if let encoded = try? JSONEncoder().encode(newProfile) {
                    UserDefaults.standard.set(encoded, forKey: profileKey)
                }
                await loadPlaylists()
            }
        } catch {
            // Soft failure, keep existing profile
        }
    }

    public func loadPlaylists() async {
        guard let cookie, let profile else { return }
        isLoadingPlaylists = true
        defer { isLoadingPlaylists = false }
        do {
            playlists = try await apiClient.fetchUserPlaylists(uid: profile.userId, cookie: cookie)
        } catch {
            // Keep existing
        }
    }

    public func logout() {
        if let cookie {
            Task {
                try? await apiClient.logout(cookie: cookie)
            }
        }
        self.cookie = nil
        self.profile = nil
        self.playlists = []
        try? keychain.remove(cookieKey)
        UserDefaults.standard.removeObject(forKey: profileKey)
    }

    public func contributeToken(using submitHandler: (String, String) async throws -> Void) async throws {
        guard let cookie, let profile else {
            throw UserFacingError(message: "尚未登录网易云账号")
        }
        try await submitHandler(cookie, profile.nickname)
    }

    public func contributeToken(using musicClient: MusicClient) async throws -> String {
        guard let cookie, let profile else {
            throw UserFacingError(message: "尚未登录网易云账号")
        }
        let response = try await musicClient.contributeNeteaseToken(cookie: cookie, nickname: profile.nickname)
        return response.message
    }
}
