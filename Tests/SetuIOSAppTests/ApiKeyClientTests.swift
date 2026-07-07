import Foundation
import XCTest
@testable import SetuIOSCore

final class ApiKeyClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        ApiKeyClientMockURLProtocol.handler = nil
    }

    func testListAcceptsEnvelopeDataListLikeFrontendApiKeyAPI() async throws {
        let capturedRequest = ApiKeyClientRequestProbe()
        let session = URLSession(
            configuration: .apiKeyClientMock { request in
                Task {
                    await capturedRequest.capture(request)
                }
                return """
                {
                  "code": 200,
                  "data": {
                    "list": [
                      {
                        "id": 7,
                        "name": "mobile",
                        "status": 1,
                        "dailyQuota": 1000,
                        "totalQuota": null,
                        "callsToday": 12,
                        "totalCalls": 345,
                        "createdAt": "2026-07-07T11:00:00Z"
                      }
                    ]
                  }
                }
                """
            }
        )
        let client = ApiKeyClient(apiClient: makeAPIClient(session: session))

        let keys = try await client.list()

        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys.first?.name, "mobile")
        XCTAssertEqual(keys.first?.isEnabled, true)
        let url = await capturedRequest.lastURL
        XCTAssertEqual(url, "https://api.example.com/api-key/list")
    }

    private func makeAPIClient(session: URLSession) -> APIClient {
        let keychain = ApiKeyClientTestKeychain()
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

private actor ApiKeyClientRequestProbe {
    private(set) var lastURL: String?

    func capture(_ request: URLRequest) {
        lastURL = request.url?.absoluteString
    }
}

private final class ApiKeyClientTestKeychain: KeychainStoring, @unchecked Sendable {
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

private final class ApiKeyClientMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> String)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body = Self.handler?(request) ?? "{}"
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
    static func apiKeyClientMock(handler: @escaping (URLRequest) -> String) -> URLSessionConfiguration {
        ApiKeyClientMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ApiKeyClientMockURLProtocol.self]
        return configuration
    }
}
