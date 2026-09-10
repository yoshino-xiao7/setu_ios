import CryptoKit
import Foundation
#if canImport(CommonCrypto)
import CommonCrypto
#endif

public struct JmCatalogClient: Sendable {
    public static let defaultAPIHosts = [
        URL(string: "https://www.cdnhjk.net")!,
        URL(string: "https://www.cdngwc.cc")!,
        URL(string: "https://www.cdngwc.net")!,
        URL(string: "https://www.cdngwc.club")!,
        URL(string: "https://www.cdnmhwscc.vip")!,
    ]

    public static let defaultImageHosts = [
        URL(string: "https://cdn-msp.jmapiproxy1.cc")!,
        URL(string: "https://cdn-msp.jmapiproxy2.cc")!,
        URL(string: "https://cdn-msp.jmapinodeudzn.net")!,
    ]

    private let session: URLSession
    private let apiHosts: [URL]
    private let imageHosts: [URL]
    private let now: @Sendable () -> Date

    public init(
        session: URLSession = .shared,
        apiHosts: [URL] = JmCatalogClient.defaultAPIHosts,
        imageHosts: [URL] = JmCatalogClient.defaultImageHosts,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.session = session
        self.apiHosts = apiHosts
        self.imageHosts = imageHosts
        self.now = now
    }

    public func albums(page: Int = 1, keyword: String? = nil) async throws -> JmAlbumPage {
        if let keyword, !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try await searchAlbums(page: page, keyword: keyword)
        }
        do {
            let envelope: JmListEnvelope = try await request(
                "/categories/filter",
                query: [
                    URLQueryItem(name: "page", value: String(max(page, 1))),
                    URLQueryItem(name: "order", value: ""),
                    URLQueryItem(name: "c", value: "0"),
                    URLQueryItem(name: "o", value: "mr"),
                ]
            )
            if !envelope.albums.isEmpty || envelope.total != nil {
                return JmAlbumPage(page: page, total: envelope.total ?? envelope.albums.count, albums: decorate(envelope.albums))
            }
        } catch {
            // Older app hosts still expose /latest; keep it as a fallback.
        }
        let envelope: JmListEnvelope = try await request(
            "/latest",
            query: [URLQueryItem(name: "page", value: String(max(page, 1)))]
        )
        return JmAlbumPage(page: page, total: envelope.total ?? envelope.albums.count, albums: decorate(envelope.albums))
    }

    private func searchAlbums(page: Int, keyword: String) async throws -> JmAlbumPage {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if let albumID = Self.albumID(from: query) {
            if page > 1 {
                return JmAlbumPage(page: page, total: 1, albums: [])
            }
            do {
                let album = try await album(id: albumID)
                return JmAlbumPage(page: page, total: 1, albums: decorate([album]))
            } catch {
                // Fall through to keyword search when the id is not a real album.
            }
        }
        let envelope: JmListEnvelope = try await request(
            "/search",
            query: [
                URLQueryItem(name: "main_tag", value: "0"),
                URLQueryItem(name: "search_query", value: query),
                URLQueryItem(name: "page", value: String(max(page, 1))),
                URLQueryItem(name: "o", value: "mr"),
                URLQueryItem(name: "t", value: "a"),
            ]
        )
        if let redirectID = envelope.redirectAID, !redirectID.isEmpty {
            let album = try await album(id: redirectID)
            return JmAlbumPage(page: page, total: 1, albums: decorate([album]))
        }
        return JmAlbumPage(page: page, total: envelope.total ?? envelope.albums.count, albums: decorate(envelope.albums))
    }

    public func album(id: String) async throws -> JmAlbum {
        let album: JmAlbum = try await request("/album", query: [URLQueryItem(name: "id", value: id)])
        return decorate([album]).first ?? album
    }

    public func pages(chapterID: String) async throws -> [JmPageImage] {
        let envelope: JmChapterEnvelope = try await request("/chapter", query: [URLQueryItem(name: "id", value: chapterID)])
        let albumID = Int(envelope.id ?? chapterID) ?? 0
        let scrambleID = envelope.scrambleID ?? 220980
        let host = imageHosts.first ?? URL(string: "https://cdn-msp.jmapiproxy1.cc")!
        return (envelope.images ?? []).enumerated().compactMap { index, file in
            let name = file.contains("/") ? (file.split(separator: "/").last.map(String.init) ?? file) : file
            guard let url = URL(string: "\(host.absoluteString)/media/photos/\(chapterID)/\(name)") else { return nil }
            return JmPageImage(id: "\(chapterID)-\(index)", url: url, albumID: albumID, scrambleID: scrambleID)
        }
    }

    private func decorate(_ albums: [JmAlbum]) -> [JmAlbum] {
        albums.map { album in
            let cover = resolvedCoverURL(for: album)
            guard cover != album.coverURL else { return album }
            return JmAlbum(
                id: album.id,
                title: album.title,
                author: album.author,
                coverURL: cover,
                tags: album.tags,
                description: album.description,
                likes: album.likes,
                chapters: album.chapters
            )
        }
    }

    private func resolvedCoverURL(for album: JmAlbum) -> String? {
        let raw = album.coverURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return raw }
        guard let host = imageHosts.first else { return raw.isEmpty ? nil : raw }
        if raw.hasPrefix("/") { return host.absoluteString + raw }
        return "\(host.absoluteString)/media/albums/\(album.id).jpg"
    }

    static func albumID(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber) { return trimmed }
        guard trimmed.count >= 3 else { return nil }
        let prefix = trimmed.prefix(2).uppercased()
        guard prefix == "JM" else { return nil }
        let digits = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        return (!digits.isEmpty && digits.allSatisfy(\.isNumber)) ? digits : nil
    }

    private func request<Value: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> Value {
        var lastError: Error = APIError.invalidResponse
        for host in apiHosts {
            do {
                return try await request(path, query: query, host: host)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func request<Value: Decodable>(_ path: String, query: [URLQueryItem], host: URL) async throws -> Value {
        guard var components = URLComponents(url: host, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL(path)
        }
        components.path = path.hasPrefix("/") ? path : "/" + path
        components.queryItems = query
        guard let url = components.url else { throw APIError.invalidURL(path) }

        let timestamp = String(Int(now().timeIntervalSince1970))
        let token = JmAppToken.token(timestamp: timestamp)
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(JmAppToken.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(token, forHTTPHeaderField: "token")
        request.setValue(JmAppToken.tokenParam(timestamp: timestamp), forHTTPHeaderField: "tokenparam")
        request.setValue(JmAppToken.appVersion, forHTTPHeaderField: "version")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        let payload = try JmAppToken.decodePayload(data, timestamp: timestamp)
        if let value = try? JSONDecoder().decode(Value.self, from: payload) {
            return value
        }
        if let envelope = try? JSONDecoder().decode(JmDataEnvelope<Value>.self, from: payload) {
            return envelope.data
        }
        throw APIError.invalidResponse
    }
}

struct JmDataEnvelope<Value: Decodable>: Decodable {
    let data: Value
}

public enum JmAppToken {
    static let secret = "185Hcomic3PAPP7R"
    static let legacySecret = "18comicAPPContent"
    public static let appVersion = "2.1.6"
    public static let userAgent = "Mozilla/5.0 (Linux; Android 9; V1938CT Build/PQ3A.190705.11211812; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 Safari/537.36"

    public static func token(timestamp: String) -> String {
        md5Hex(timestamp + secret)
    }

    public static func isImageCDN(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("jmapiproxy") || host.contains("jmapinode") || host.hasPrefix("cdn-msp")
    }

    public static func applyImageHeaders(to request: inout URLRequest) {
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("com.JMComic3.app", forHTTPHeaderField: "X-Requested-With")
        request.setValue("https://www.cdnhjk.net/", forHTTPHeaderField: "Referer")
        request.setValue("zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
    }

    public static func imageRequest(url: URL, cachePolicy: URLRequest.CachePolicy = .returnCacheDataElseLoad) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        applyImageHeaders(to: &request)
        return request
    }

    static func tokenParam(timestamp: String) -> String {
        "\(timestamp),\(appVersion)"
    }

    static func decodePayload(_ data: Data, timestamp: String) throws -> Data {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let encoded = object["data"] as? String, !encoded.isEmpty {
                if let decrypted = decryptCiphertext(encoded, timestamp: timestamp) {
                    return decrypted
                }
                throw APIError.invalidResponse
            }
            if let nested = object["data"], JSONSerialization.isValidJSONObject(nested),
               let nestedData = try? JSONSerialization.data(withJSONObject: nested) {
                return nestedData
            }
            return data
        }
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            return data
        }
        if text.first == "{" || text.first == "[" {
            return Data(text.utf8)
        }
        return decryptCiphertext(text, timestamp: timestamp) ?? data
    }

    private static func decryptCiphertext(_ text: String, timestamp: String) -> Data? {
        guard let decoded = Data(base64Encoded: text) else { return nil }
        for secret in [secret, legacySecret] {
            let digest = md5Hex(timestamp + secret)
            for key in [digest, String(digest.prefix(16))] {
                if let plain = aesEcbDecrypt(decoded, key: key),
                   (try? JSONSerialization.jsonObject(with: plain)) != nil {
                    return plain
                }
            }
        }
        return nil
    }

    static func md5Hex(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func aesEcbDecrypt(_ data: Data, key: String) -> Data? {
        #if canImport(CommonCrypto)
        let keyData = Data(key.utf8)
        let inputCount = data.count
        let keyCount = keyData.count
        var output = Data(count: inputCount + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { inputBytes in
                keyData.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBytes.baseAddress,
                        keyCount,
                        nil,
                        inputBytes.baseAddress,
                        inputCount,
                        outputBytes.baseAddress,
                        outputCapacity,
                        &outputLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        output.removeSubrange(outputLength..<output.count)
        return output
        #else
        return nil
        #endif
    }
}
