import Foundation
import XCTest
@testable import SetuIOSCore

final class DashboardClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        DashboardClientMockURLProtocol.handler = nil
    }

    func testApiKeyCountAcceptsWrappedRowsLikeFrontendApiKeyList() async throws {
        let capturedRequest = DashboardClientRequestProbe()
        let session = URLSession(
            configuration: .dashboardClientMock { request in
                Task {
                    await capturedRequest.capture(request)
                }
                return """
                {
                  "code": 200,
                  "data": {
                    "rows": [
                      {
                        "id": 1,
                        "name": "mobile-a",
                        "status": 1,
                        "dailyQuota": 1000,
                        "totalQuota": null,
                        "callsToday": 1,
                        "totalCalls": 10,
                        "createdAt": "2026-07-07T11:40:00Z"
                      },
                      {
                        "id": 2,
                        "name": "mobile-b",
                        "status": 0,
                        "dailyQuota": 1000,
                        "totalQuota": 5000,
                        "callsToday": 2,
                        "totalCalls": 20,
                        "createdAt": "2026-07-07T11:41:00Z"
                      }
                    ]
                  }
                }
                """
            }
        )
        let client = DashboardClient(apiClient: makeAPIClient(session: session))

        let count = try await client.fetchApiKeyCount()

        XCTAssertEqual(count, 2)
        let url = await capturedRequest.lastURL
        XCTAssertEqual(url, "https://api.example.com/api-key/list")
    }

    private func makeAPIClient(session: URLSession) -> APIClient {
        let keychain = DashboardClientTestKeychain()
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

private actor DashboardClientRequestProbe {
    private(set) var lastURL: String?

    func capture(_ request: URLRequest) {
        lastURL = request.url?.absoluteString
    }
}

private final class DashboardClientTestKeychain: KeychainStoring, @unchecked Sendable {
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

private final class DashboardClientMockURLProtocol: URLProtocol {
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
    static func dashboardClientMock(handler: @escaping (URLRequest) -> String) -> URLSessionConfiguration {
        DashboardClientMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DashboardClientMockURLProtocol.self]
        return configuration
    }
}
