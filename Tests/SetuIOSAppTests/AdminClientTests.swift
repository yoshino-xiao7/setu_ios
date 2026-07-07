import Foundation
import XCTest
@testable import SetuIOSCore

final class AdminClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        AdminClientMockURLProtocol.handler = nil
    }

    func testImageInfoEndpointMatchesFrontendAdminAPI() async throws {
        let capturedRequest = AdminClientRequestProbe()
        let session = URLSession(
            configuration: .adminClientMock { request in
                Task {
                    await capturedRequest.capture(request)
                }
                return """
                {
                  "pid": 123,
                  "p": 2,
                  "uid": 456,
                  "title": "测试图片",
                  "author": "画师",
                  "r18": 0,
                  "width": 1200,
                  "height": 1600,
                  "ext": "jpg",
                  "aiType": 1,
                  "uploadDate": 1783425600000,
                  "urlOriginal": "https://img.example.com/original.jpg",
                  "tags": ["tag-a", "tag-b"]
                }
                """
            }
        )
        let client = AdminClient(apiClient: makeAPIClient(session: session))

        let image = try await client.imageInfo(pid: 123, p: 2)

        XCTAssertEqual(image.title, "测试图片")
        XCTAssertEqual(image.tags ?? [], ["tag-a", "tag-b"])
        let url = await capturedRequest.lastURL
        XCTAssertEqual(url, "https://api.example.com/admin/image/info?pid=123&p=2")
    }

    private func makeAPIClient(session: URLSession) -> APIClient {
        let keychain = AdminClientTestKeychain()
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

private actor AdminClientRequestProbe {
    private(set) var lastURL: String?

    func capture(_ request: URLRequest) {
        lastURL = request.url?.absoluteString
    }
}

private final class AdminClientTestKeychain: KeychainStoring, @unchecked Sendable {
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

private final class AdminClientMockURLProtocol: URLProtocol {
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
    static func adminClientMock(handler: @escaping (URLRequest) -> String) -> URLSessionConfiguration {
        AdminClientMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AdminClientMockURLProtocol.self]
        return configuration
    }
}
