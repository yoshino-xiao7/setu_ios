import Foundation

public struct PointsClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func balance() async throws -> PointsBalance {
        try await apiClient.get("/points/me")
    }

    public func logs(page: Int = 1, size: Int = 20) async throws -> PointsLogPage {
        try await apiClient.get("/points/logs?page=\(page)&size=\(size)")
    }

    public func callSetu(request: PointsCallRequest) async throws -> [SetuImageItem] {
        try await apiClient.get(request.path)
    }
}

public struct PointsCallRequest: Sendable {
    public let r18: Int
    public let num: Int
    public let keyword: String
    public let tags: [String]
    public let size: String
    public let excludeAI: Bool

    public init(r18: Int, num: Int, keyword: String, tags: [String], size: String, excludeAI: Bool) {
        self.r18 = r18
        self.num = num
        self.keyword = keyword
        self.tags = tags
        self.size = size
        self.excludeAI = excludeAI
    }

    var path: String {
        var components = URLComponents()
        components.path = "/setu/v2"
        var queryItems = [
            URLQueryItem(name: "r18", value: String(r18)),
            URLQueryItem(name: "num", value: String(num)),
            URLQueryItem(name: "size", value: size)
        ]
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKeyword.isEmpty {
            queryItems.append(URLQueryItem(name: "keyword", value: trimmedKeyword))
        }
        if excludeAI {
            queryItems.append(URLQueryItem(name: "excludeAI", value: "true"))
        }
        queryItems.append(contentsOf: tags.map { URLQueryItem(name: "tag", value: $0) })
        components.queryItems = queryItems
        return components.string ?? "/setu/v2"
    }
}
