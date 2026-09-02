import Foundation

public struct AppConfig: Sendable {
    public var apiBaseURL: URL
    public var siteBaseURL: URL

    public init(apiBaseURL: URL, siteBaseURL: URL) {
        self.apiBaseURL = apiBaseURL
        self.siteBaseURL = siteBaseURL
    }

    public static let production = AppConfig(
        apiBaseURL: URL(string: "https://api.yukiryou.icu")!,
        siteBaseURL: URL(string: "https://cloud.yukiryou.icu")!
    )

    /// 调试 / 本地联调环境：允许通过启动参数或 UserDefaults 覆盖 base URL，
    /// 无需改动编译产物。仅 DEBUG 生效，例如：
    ///   -SETU_API_BASE_URL http://127.0.0.1:9898
    public static func resolved() -> AppConfig {
        #if DEBUG
        let overrides = UserDefaults.standard
        if let api = overrides.string(forKey: "SETU_API_BASE_URL"), let apiURL = URL(string: api) {
            let site = overrides.string(forKey: "SETU_SITE_BASE_URL")
                .flatMap(URL.init(string:)) ?? apiURL
            return AppConfig(apiBaseURL: apiURL, siteBaseURL: site)
        }
        #endif
        return .production
    }
}
