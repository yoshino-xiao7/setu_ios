import Foundation
import XCTest
@testable import SetuIOSCore

final class PublicBlogClientTests: XCTestCase {
    func testDailySetuAcceptsSingleImagePayload() async throws {
        let client = makeClient(body: imagePayload(pid: 1001))

        let item = try await client.dailySetu()

        XCTAssertEqual(item?.pid, 1001)
    }

    func testDailySetuAcceptsArrayPayload() async throws {
        let client = makeClient(body: "[\(imagePayload(pid: 1002))]")

        let item = try await client.dailySetu()

        XCTAssertEqual(item?.pid, 1002)
    }

    func testDailySetuAcceptsEnvelopePayload() async throws {
        let client = makeClient(body: #"{"data":[\#(imagePayload(pid: 1003))]}"#)

        let item = try await client.dailySetu()

        XCTAssertEqual(item?.pid, 1003)
    }

    func testDailySetuSendsBlogSourceHeaders() async throws {
        let client = makeClient(body: imagePayload(pid: 1004))

        _ = try await client.dailySetu()

        let request = MockURLProtocol.lastRequest
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Origin"), "https://example.com")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Referer"), "https://example.com/docs")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "User-Agent"), "SetuIOSApp/1.0 iOS")
    }

    func testSearchMusicUsesPublicBlogEndpointAndSourceHeaders() async throws {
        let client = makeClient(body: musicSearchPayload())

        let result = try await client.searchMusic(keywords: " 夜に駆ける ", limit: 99, offset: -5, type: 0)

        XCTAssertEqual(result.result.songs.first?.id, 1409311773)
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/blog/music/search")
        XCTAssertEqual(request.url?.query?.contains("keywords=%E5%A4%9C%E3%81%AB%E9%A7%86%E3%81%91%E3%82%8B"), true)
        XCTAssertEqual(request.url?.query?.contains("limit=50"), true)
        XCTAssertEqual(request.url?.query?.contains("offset=0"), true)
        XCTAssertEqual(request.url?.query?.contains("type=1"), true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://example.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://example.com/docs")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "SetuIOSApp/1.0 iOS")
    }

    private func makeClient(body: String) -> PublicBlogClient {
        let session = URLSession(configuration: .publicBlogMock(body: body))
        let apiClient = APIClient(
            config: AppConfig(apiBaseURL: URL(string: "https://api.example.com")!, siteBaseURL: URL(string: "https://example.com")!),
            signer: AuthSigner(keychain: InMemoryKeychain()),
            session: session
        )
        return PublicBlogClient(apiClient: apiClient)
    }

    private func imagePayload(pid: Int) -> String {
        """
        {
          "pid": \(pid),
          "p": 0,
          "uid": 7,
          "title": "Daily",
          "author": "Yuki",
          "r18": false,
          "width": 1200,
          "height": 800,
          "ext": "jpg",
          "aiType": 0,
          "uploadDate": 1700000000,
          "tags": ["daily"],
          "urls": {
            "regular": "https://example.com/regular.jpg",
            "original": "https://example.com/original.jpg",
            "small": null
          }
        }
        """
    }

    private func musicSearchPayload() -> String {
        """
        {
          "result": {
            "songs": [
              {
                "id": 1409311773,
                "name": "夜に駆ける",
                "ar": [{ "id": 33927412, "name": "YOASOBI" }],
                "al": {
                  "id": 83898690,
                  "name": "夜に駆ける",
                  "picUrl": "https://example.com/cover.jpg"
                },
                "dt": 261013,
                "mv": 10907191
              }
            ],
            "songCount": 1
          }
        }
        """
    }
}

private final class InMemoryKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func string(for key: String) throws -> String? {
        lock.withLock { values[key] }
    }

    func setString(_ value: String, for key: String) throws {
        lock.withLock {
            values[key] = value
        }
    }

    func remove(_ key: String) throws {
        _ = lock.withLock {
            values.removeValue(forKey: key)
        }
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLSessionConfiguration {
    static func publicBlogMock(body: String) -> URLSessionConfiguration {
        MockURLProtocol.body = Data(body.utf8)
        MockURLProtocol.lastRequest = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return configuration
    }
}
