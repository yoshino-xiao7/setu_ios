import Foundation
import XCTest
@testable import SetuIOSCore

/// Measures the unchanged shared network layer instead of assuming two full model decodes.
final class MusicNetworkAuditTests: XCTestCase {
    func testDecodeAttemptsAndKeychainReadsForActualResponseShapes() async throws {
        let decoder = AuditDecoder()
        let keychain = AuditKeychain()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuditURLProtocol.self]
        let base = try XCTUnwrap(URL(string: "https://network-audit.test"))
        let api = APIClient(config: AppConfig(apiBaseURL: base, siteBaseURL: base), signer: AuthSigner(keychain: keychain),
                            session: URLSession(configuration: configuration), decoder: decoder)
        let music = MusicClient(apiClient: api)
        let search = try await music.search(keywords: "fixture")
        XCTAssertEqual(search.result.songs.first?.id, 1)
        XCTAssertEqual(decoder.count, 2)
        XCTAssertEqual(keychain.readCount, 2)
        decoder.reset()
        let url = try await music.url(songID: 1)
        XCTAssertEqual(url.data?.first?.id, 1)
        XCTAssertEqual(decoder.count, 2)
        XCTAssertEqual(keychain.readCount, 4)
        decoder.reset()
        let playlists = try await music.playlists()
        XCTAssertEqual(playlists.first?.id, 1)
        XCTAssertEqual(decoder.count, 2)
        decoder.reset()
        let wrapped: UserMusicPlaylist = try await api.get("/envelope")
        XCTAssertEqual(wrapped.id, 2)
        XCTAssertEqual(decoder.count, 1)
        XCTAssertEqual(keychain.readCount, 8)
        decoder.reset()
        let readsBeforeV2 = keychain.readCount
        _ = try await MusicV2Client(apiClient: api).home()
        XCTAssertEqual(keychain.readCount, readsBeforeV2, "SID-only v2 requests must not read the signing key")
        print("Network audit: raw search/URL/playlists = 2 decode attempts; envelope = 1; signed request = 2 Keychain reads")
    }
}

private final class AuditDecoder: JSONDecoder, @unchecked Sendable {
    private let lock = NSLock()
    private var attempts = 0
    var count: Int { lock.withLock { attempts } }
    func reset() { lock.withLock { attempts = 0 } }
    override func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        lock.withLock { attempts += 1 }
        return try super.decode(type, from: data)
    }
}
private final class AuditKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    var readCount: Int { lock.withLock { reads } }
    func string(for key: String) throws -> String? { lock.withLock { reads += 1 }; return "test-only-secret" }
    func setString(_ value: String, for key: String) throws {}
    func remove(_ key: String) throws {}
}
private final class AuditURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let body: String
        switch url.path {
        case "/user/music/search": body = #"{"result":{"songs":[{"id":1,"name":"fixture"}],"songCount":1}}"#
        case "/user/music/url": body = #"{"data":[{"id":1,"url":"https://audio.test/1.mp3"}]}"#
        case "/user/playlists": body = #"[{"id":1,"name":"fixture"}]"#
        case "/user/music/v2/home": body = #"{"sections":[],"generatedAt":"2026-09-03T08:00:00Z"}"#
        default: body = #"{"code":200,"data":{"id":2,"name":"wrapped"}}"#
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
