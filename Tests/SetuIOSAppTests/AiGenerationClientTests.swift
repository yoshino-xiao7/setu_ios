import Foundation
import XCTest
@testable import SetuIOSCore

final class AiGenerationClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        AiGenerationClientMockURLProtocol.handler = nil
    }

    func testUserDeleteRequestsEndpointMatchesFrontendAPI() async throws {
        let capturedRequests = AiGenerationClientRequestProbe()
        let session = URLSession(
            configuration: .aiGenerationClientMock { request in
                Task {
                    await capturedRequests.capture(request)
                }
                return """
                {"total":1,"page":2,"pageSize":10,"list":[{"id":7,"jobId":99,"userId":3,"reason":"清理图片","status":"WAITING"}]}
                """
            }
        )
        let client = AiGenerationClient(apiClient: makeAPIClient(session: session))

        let result = try await client.deleteRequests(status: "WAITING", page: 2, pageSize: 10)

        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.list.first?.id, 7)
        XCTAssertEqual(result.list.first?.statusTitle, "待审核")

        let urls = await capturedRequests.urls
        XCTAssertEqual(urls, ["https://api.example.com/ai/delete-requests?page=2&pageSize=10&status=WAITING"])
    }

    private func makeAPIClient(session: URLSession) -> APIClient {
        let keychain = AiGenerationClientTestKeychain()
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

private actor AiGenerationClientRequestProbe {
    private(set) var urls: [String] = []

    func capture(_ request: URLRequest) {
        urls.append(request.url?.absoluteString ?? "")
    }
}

private final class AiGenerationClientTestKeychain: KeychainStoring, @unchecked Sendable {
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

private final class AiGenerationClientMockURLProtocol: URLProtocol {
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
    static func aiGenerationClientMock(handler: @escaping (URLRequest) -> String) -> URLSessionConfiguration {
        AiGenerationClientMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AiGenerationClientMockURLProtocol.self]
        return configuration
    }
}
