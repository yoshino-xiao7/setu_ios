import Foundation
import XCTest
@testable import SetuIOSCore

final class NotificationClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        NotificationClientMockURLProtocol.handler = nil
    }

    func testNotificationsAcceptFrontendCompatiblePayloadShapes() async throws {
        let capturedRequests = NotificationClientRequestProbe()
        let session = URLSession(
            configuration: .notificationClientMock { request in
                Task {
                    await capturedRequests.capture(request)
                }
                switch request.url?.path {
                case "/notifications/unread-count":
                    return "3"
                case "/notifications":
                    return """
                    {
                      "total": 1,
                      "page": 1,
                      "pageSize": 20,
                      "list": [
                        {
                          "id": 11,
                          "type": "AI_GENERATION_COMPLETED",
                          "title": "完成",
                          "content": "图片已生成",
                          "targetType": "AI_GENERATION",
                          "targetId": 9001,
                          "read": false,
                          "readAt": null,
                          "createdAt": "2026-07-07T13:30:00Z"
                        }
                      ]
                    }
                    """
                case "/notifications/11/read", "/notifications/read-all":
                    return "ok"
                default:
                    return "{}"
                }
            }
        )
        let client = NotificationClient(apiClient: makeAPIClient(session: session))

        let unreadCount = try await client.unreadCount()
        let page = try await client.list()
        try await client.markRead(id: 11)
        try await client.markAllRead()

        XCTAssertEqual(unreadCount, 3)
        XCTAssertEqual(page.list.first?.targetId, "9001")
        let urls = await capturedRequests.urls
        XCTAssertTrue(urls.contains("https://api.example.com/notifications/unread-count"))
        XCTAssertTrue(urls.contains("https://api.example.com/notifications?page=1&pageSize=20&unreadOnly=false"))
        XCTAssertTrue(urls.contains("https://api.example.com/notifications/11/read"))
        XCTAssertTrue(urls.contains("https://api.example.com/notifications/read-all"))
    }

    private func makeAPIClient(session: URLSession) -> APIClient {
        let keychain = NotificationClientTestKeychain()
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

private actor NotificationClientRequestProbe {
    private(set) var urls: [String] = []

    func capture(_ request: URLRequest) {
        urls.append(request.url?.absoluteString ?? "")
    }
}

private final class NotificationClientTestKeychain: KeychainStoring, @unchecked Sendable {
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

private final class NotificationClientMockURLProtocol: URLProtocol {
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
    static func notificationClientMock(handler: @escaping (URLRequest) -> String) -> URLSessionConfiguration {
        NotificationClientMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NotificationClientMockURLProtocol.self]
        return configuration
    }
}
