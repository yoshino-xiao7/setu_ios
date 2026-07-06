import Foundation

public struct AppConfig: Sendable {
    public var apiBaseURL: URL

    public init(apiBaseURL: URL) {
        self.apiBaseURL = apiBaseURL
    }

    public static let production = AppConfig(
        apiBaseURL: URL(string: "https://api.example.com")!
    )
}
