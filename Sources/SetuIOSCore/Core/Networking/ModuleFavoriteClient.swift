import Foundation

public struct ModuleFavoriteClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func list(module: ModuleFavoriteModule, page: Int = 1, size: Int = 24) async throws -> ModuleFavoritePage {
        try await apiClient.get("/module-favorites?module=\(module.rawValue)&page=\(page)&size=\(size)")
    }

    public func add(_ snapshot: ModuleFavoriteSnapshot) async throws -> ModuleFavoriteItem {
        try await apiClient.post("/module-favorites", body: snapshot)
    }

    public func remove(module: ModuleFavoriteModule, externalId: String) async throws {
        let encoded = try encodedPath(externalId)
        let _: String = try await apiClient.requestWithoutBody(
            "/module-favorites/\(module.rawValue)/\(encoded)",
            method: "DELETE"
        )
    }

    public func exists(module: ModuleFavoriteModule, externalId: String) async throws -> Bool {
        let encoded = try encodedPath(externalId)
        return try await apiClient.get("/module-favorites/\(module.rawValue)/exists/\(encoded)")
    }

    public func existsBatch(module: ModuleFavoriteModule, externalIds: [String]) async throws -> [String: Bool] {
        guard !externalIds.isEmpty else { return [:] }
        var seen = Set<String>()
        let ids = externalIds.filter { seen.insert($0).inserted }
        var result: [String: Bool] = [:]
        for start in stride(from: 0, to: ids.count, by: 100) {
            try Task.checkCancellation()
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            let response: ModuleFavoriteExistsBatchResponse = try await apiClient.post(
                "/module-favorites/exists-batch",
                body: ModuleFavoriteExistsBatchRequest(module: module, externalIds: batch)
            )
            result.merge(response.exists) { _, new in new }
        }
        return result
    }

    private func encodedPath(_ value: String) throws -> String {
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id != ".", id != "..", id.utf16.count <= 128,
              !id.contains("/"), !id.contains("\\"),
              !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw APIError.invalidURL("外部标识无效")
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw APIError.invalidURL("外部标识无效")
        }
        return encoded
    }
}
