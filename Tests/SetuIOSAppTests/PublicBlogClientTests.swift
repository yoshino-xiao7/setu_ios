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
          "r18": 0,
          "width": 1200,
          "height": 800,
          "ext": "jpg",
          "aiType": 0,
          "uploadDate": 1700000000,
          "tags": ["daily"],
          "urls": {
            "regular": "https://example.com/regular.jpg",
            "original": "https://example.com/original.jpg"
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

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
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
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return configuration
    }
}
