import Foundation

public struct AsmrCatalogClient: Sendable {
    public static let defaultBaseURLs = [
        URL(string: "https://api.asmr.one")!,
        URL(string: "https://api.asmr-200.com")!,
        URL(string: "https://api.asmr-300.com")!,
    ]

    private let session: URLSession
    private let baseURLs: [URL]

    public init(session: URLSession = .shared, baseURLs: [URL] = AsmrCatalogClient.defaultBaseURLs) {
        self.session = session
        self.baseURLs = baseURLs
    }

    public func works(page: Int = 1, pageSize: Int = 20, keyword: String? = nil) async throws -> AsmrWorkPage {
        if let keyword, !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try await search(keyword: keyword, page: page, pageSize: pageSize)
        }
        return try await get("/api/works", query: [
            URLQueryItem(name: "order", value: "release"),
            URLQueryItem(name: "sort", value: "desc"),
            URLQueryItem(name: "page", value: String(max(page, 1))),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "subtitle", value: "0"),
        ])
    }

    public func work(id: String) async throws -> AsmrWork {
        try await get("/api/workInfo/\(try encodedPath(id))")
    }

    public func tracks(workID: String) async throws -> [AsmrTrack] {
        let nodes: [AsmrTrackNode] = try await get("/api/tracks/\(try encodedPath(workID))", query: [URLQueryItem(name: "v", value: "2")])
        return nodes.flatMap { $0.flattenedAudio() }
    }

    private func encodedPath(_ value: String) throws -> String {
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !id.contains("/"), !id.contains("\\") else {
            throw APIError.invalidURL("作品标识无效")
        }
        return id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    }

    private func search(keyword: String, page: Int, pageSize: Int) async throws -> AsmrWorkPage {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? keyword
        return try await get(
            "/api/search/\(encoded)",
            query: [
                URLQueryItem(name: "page", value: String(max(page, 1))),
                URLQueryItem(name: "pageSize", value: String(pageSize)),
                URLQueryItem(name: "subtitle", value: "0"),
            ]
        )
    }

    private func get<Value: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Value {
        var lastError: Error = APIError.invalidResponse
        for base in baseURLs {
            do {
                return try await get(path, query: query, base: base)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func get<Value: Decodable>(_ path: String, query: [URLQueryItem], base: URL) async throws -> Value {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL(path)
        }
        components.path = path.hasPrefix("/") ? path : "/" + path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL(path) }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://www.asmr.one", forHTTPHeaderField: "Origin")
        request.setValue("https://www.asmr.one/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }
}
