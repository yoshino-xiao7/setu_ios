import Foundation
import XCTest
@testable import SetuIOSCore

final class CollectionClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        CollectionClientMockURLProtocol.handler = nil
    }

    func testItemsAcceptWrappedRecordsPayload() async throws {
        let capturedRequest = CollectionClientRequestProbe()
        let session = URLSession(
            configuration: .collectionClientMock { request in
                Task {
                    await capturedRequest.capture(request)
                }
                return """
                {
                  "code": 200,
                  "data": {
                    "page": 2,
                    "pageSize": 24,
                    "count": 1,
                    "records": [
                      {
                        "itemId": 88,
                        "pid": 123,
                        "p": 2,
                        "addedAt": "2026-07-07T13:50:00Z",
                        "image": null
                      }
                    ]
                  }
                }
                """
            }
        )
        let client = CollectionClient(apiClient: makeAPIClient(session: session))

        let page = try await client.items(collectionID: 7, page: 2, size: 24)

        XCTAssertEqual(page.page, 2)
        XCTAssertEqual(page.size, 24)
        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.items.first?.pid, 123)
        let url = await capturedRequest.lastURL
        XCTAssertEqual(url, "https://api.example.com/collections/7/items?page=2&size=24")
    }

    func testPublicUserProfileDecodesDiscoverableIdentitySummary() async throws {
        let capturedRequest = CollectionClientRequestProbe()
        let session = URLSession(
            configuration: .collectionClientMock { request in
                Task {
                    await capturedRequest.capture(request)
                }
                return """
                {"id":7,"nickname":"雪夜画师","avatarUrl":"https://cdn.example.com/avatars/7.png","publicCollectionCount":3,"publicAiWorkCount":5}
                """
            }
        )
        let client = CollectionClient(apiClient: makeAPIClient(session: session))

        let profile = try await client.publicUserProfile(userID: 7)

        XCTAssertEqual(profile.id, 7)
        XCTAssertEqual(profile.nickname, "雪夜画师")
        XCTAssertEqual(profile.publicCollectionCount, 3)
        XCTAssertEqual(profile.publicAiWorkCount, 5)
        let url = await capturedRequest.lastURL
        XCTAssertEqual(url, "https://api.example.com/square/users/7")
    }

    func testSquareCanRequestOnlyOneOwnersPublicCollections() async throws {
        let capturedRequest = CollectionClientRequestProbe()
        let session = URLSession(
            configuration: .collectionClientMock { request in
                Task {
                    await capturedRequest.capture(request)
                }
                return """
                {"total":0,"page":1,"pageSize":20,"list":[]}
                """
            }
        )
        let client = CollectionClient(apiClient: makeAPIClient(session: session))

        _ = try await client.square(page: 1, size: 20, sort: "new", ownerID: 7)

        let url = await capturedRequest.lastURL
        XCTAssertEqual(url, "https://api.example.com/square/collections?page=1&size=20&sort=new&ownerId=7")
    }

    private func makeAPIClient(session: URLSession) -> APIClient {
        let keychain = CollectionClientTestKeychain()
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

private actor CollectionClientRequestProbe {
    private(set) var lastURL: String?

    func capture(_ request: URLRequest) {
        lastURL = request.url?.absoluteString
    }
}

private final class CollectionClientTestKeychain: KeychainStoring, @unchecked Sendable {
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

private final class CollectionClientMockURLProtocol: URLProtocol {
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
    static func collectionClientMock(handler: @escaping (URLRequest) -> String) -> URLSessionConfiguration {
        CollectionClientMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CollectionClientMockURLProtocol.self]
        return configuration
    }
}
