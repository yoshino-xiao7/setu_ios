import Foundation
import XCTest
@testable import SetuIOSCore

final class FavoriteClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        FavoriteClientMockURLProtocol.handler = nil
    }

    func testExistsEndpointMatchesFrontendFavoriteAPI() async throws {
        let capturedRequest = FavoriteClientRequestProbe()
        let session = URLSession(
            configuration: .favoriteClientMock { request in
                Task {
                    await capturedRequest.capture(request)
                }
                return "true"
            }
        )
        let client = FavoriteClient(apiClient: makeAPIClient(session: session))

        let exists = try await client.exists(pid: 123, p: 2)

        XCTAssertTrue(exists)
        let url = await capturedRequest.lastURL
        XCTAssertEqual(url, "https://api.example.com/favorite/exists/123/2")
    }

    func testListAcceptsWrappedListPayload() async throws {
        let capturedRequest = FavoriteClientRequestProbe()
        let session = URLSession(
            configuration: .favoriteClientMock { request in
                Task {
                    await capturedRequest.capture(request)
                }
                return """
                {
                  "code": 200,
                  "data": {
                    "page": 1,
                    "pageSize": 24,
                    "total": 1,
                    "list": [
                      {
                        "favoriteId": 9,
                        "imageId": 10,
                        "pid": 123,
                        "p": 2,
                        "favoritedAt": "2026-07-07T13:40:00Z",
                        "image": null
                      }
                    ]
                  }
                }
                """
            }
        )
        let client = FavoriteClient(apiClient: makeAPIClient(session: session))

        let page = try await client.list(page: 1, size: 24)

        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.items.first?.pid, 123)
        XCTAssertEqual(page.size, 24)
        let url = await capturedRequest.lastURL
        XCTAssertEqual(url, "https://api.example.com/favorite/list?page=1&size=24")
    }

    private func makeAPIClient(session: URLSession) -> APIClient {
        let keychain = FavoriteClientTestKeychain()
        try? keychain.setString("secret", for: "signSecret")
        return APIClient(
            config: AppConfig(
                apiBaseURL: URL(string: "https://api.example.com")!,
                siteBaseURL: URL(string: "https://example.com")!
            ),
            signer: AuthSigner(keychain: keychain),
            session: session
        )
    }
}

private actor FavoriteClientRequestProbe {
    private(set) var lastURL: String?

    func capture(_ request: URLRequest) {
        lastURL = request.url?.absoluteString
    }
}

private final class FavoriteClientTestKeychain: KeychainStoring, @unchecked Sendable {
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

private final class FavoriteClientMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> String)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body = Self.handler?(request) ?? "false"
        let response = HTTPURLResponse(
            url: request.url!,
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

private extension URLSessionConfiguration {
    static func favoriteClientMock(handler: @escaping (URLRequest) -> String) -> URLSessionConfiguration {
        FavoriteClientMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FavoriteClientMockURLProtocol.self]
        return configuration
    }
}
