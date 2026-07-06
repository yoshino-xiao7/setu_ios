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
}
