import Foundation
import XCTest
@testable import SetuIOSCore

final class CloudVideoClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        CloudVideoClientMockURLProtocol.handler = nil
    }

    func testListUsesOffsetAndLimit() async throws {
        let probe = CloudVideoRequestProbe()
        let client = makeClient { request in
            probe.capture(request)
            return #"{"items":[{"id":8,"title":"第一集","coverUrl":"https://cdn.example/thumb.jpg","durationSeconds":95}],"total":1,"offset":0,"limit":24}"#
        }

        let page = try await client.list(offset: 0, limit: 24)

        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.items.first?.title, "第一集")
        XCTAssertEqual(probe.lastURL, "https://api.example.com/user/cloud-video?offset=0&limit=24")
        XCTAssertEqual(probe.lastMethod, "GET")
    }

    func testSearchEncodesKeywords() async throws {
        let probe = CloudVideoRequestProbe()
        let client = makeClient { request in
            probe.capture(request)
            return #"{"items":[],"total":0,"offset":0,"limit":24}"#
        }

        _ = try await client.search(keywords: "夏日 海边", offset: 0, limit: 24)

        let url = probe.lastURL ?? ""
        XCTAssertTrue(url.contains("/user/cloud-video/search?"))
        XCTAssertTrue(url.contains("keywords="))
        XCTAssertTrue(url.contains("offset=0"))
    }

    func testCatalogWithoutKeywordsUsesList() async throws {
        let probe = CloudVideoRequestProbe()
        let client = makeClient { request in
            probe.capture(request)
            return #"{"items":[],"total":0,"offset":24,"limit":24}"#
        }

        _ = try await client.catalog(keywords: "  ", offset: 24, limit: 24)

        XCTAssertEqual(probe.lastURL, "https://api.example.com/user/cloud-video?offset=24&limit=24")
    }

    func testPlaybackDecodesHlsTicket() async throws {
        let client = makeClient { _ in
            #"{"id":8,"title":"第一集","hlsUrl":"https://vz.example/bcdn_token=abc/guid/playlist.m3u8","posterUrl":"https://vz.example/guid/thumbnail.jpg","expireAt":1700000000}"#
        }

        let ticket = try await client.playback(id: 8)

        XCTAssertEqual(ticket.id, 8)
        XCTAssertEqual(ticket.hlsUrl.contains("playlist.m3u8"), true)
        XCTAssertEqual(ticket.expireAt, 1_700_000_000)
    }

    private func makeClient(handler: @escaping (URLRequest) -> String) -> CloudVideoClient {
        CloudVideoClientMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CloudVideoClientMockURLProtocol.self]
        let keychain = CloudVideoClientTestKeychain()
        try? keychain.setString("secret", for: "signSecret")
        return CloudVideoClient(
            apiClient: APIClient(
                config: AppConfig(
                    apiBaseURL: URL(string: "https://api.example.com")!,
                    siteBaseURL: URL(string: "https://example.com")!
                ),
                signer: AuthSigner(keychain: keychain),
                session: URLSession(configuration: configuration)
            )
        )
    }
}

private final class CloudVideoRequestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var url: String?
    private var method: String?

    var lastURL: String? { lock.withLock { url } }
    var lastMethod: String? { lock.withLock { method } }

    func capture(_ request: URLRequest) {
        lock.withLock {
            url = request.url?.absoluteString
            method = request.httpMethod
        }
    }
}

private final class CloudVideoClientTestKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func string(for key: String) throws -> String? {
        lock.withLock { values[key] }
    }

    func setString(_ value: String, for key: String) throws {
        lock.withLock { values[key] = value }
    }

    func remove(_ key: String) throws {
        _ = lock.withLock { values.removeValue(forKey: key) }
    }
}

private final class CloudVideoClientMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> String)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.handler?(request) ?? "{}"
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
