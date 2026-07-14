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

    func testSquareDecodesMinimalPublicWorkProjection() async throws {
        let session = URLSession(
            configuration: .aiGenerationClientMock { _ in
                """
                {"total":1,"page":1,"pageSize":16,"list":[{"id":82,"userId":7,"promptCn":"雨夜街角","width":768,"height":1024,"publicCategory":"GENERAL","imageUrl":"https://cdn.example.com/public/82.png","createdAt":"2026-07-10T12:00:00"}]}
                """
            }
        )
        let client = AiGenerationClient(apiClient: makeAPIClient(session: session))

        let result = try await client.square(category: "GENERAL", page: 1, pageSize: 16)

        XCTAssertEqual(result.list.first?.id, 82)
        XCTAssertEqual(result.list.first?.userId, 7)
        XCTAssertEqual(result.list.first?.promptCn, "雨夜街角")
        XCTAssertEqual(result.list.first?.publicCategory, "GENERAL")
        XCTAssertEqual(result.list.first?.imageUrl, "https://cdn.example.com/public/82.png")
    }

    func testServiceStatusUsesProductLanguageInsteadOfBackendMessage() throws {
        let offline = try JSONDecoder().decode(
            AiServiceStatusResponse.self,
            from: Data(#"{"status":"OFFLINE","online":false,"openNow":true,"available":false,"message":"worker-7 heartbeat timeout"}"#.utf8)
        )
        let closed = try JSONDecoder().decode(
            AiServiceStatusResponse.self,
            from: Data(#"{"status":"CLOSED","online":true,"openNow":false,"available":false,"message":"cron window rejected"}"#.utf8)
        )
        let busy = try JSONDecoder().decode(
            AiServiceStatusResponse.self,
            from: Data(#"{"status":"BUSY","online":true,"openNow":true,"available":false,"message":"no worker slot"}"#.utf8)
        )

        XCTAssertEqual(offline.userFacingUnavailableMessage, "创作服务暂时离线，请稍后再试")
        XCTAssertEqual(closed.userFacingUnavailableMessage, "当前不在开放时间，请稍后再来")
        XCTAssertEqual(busy.userFacingUnavailableMessage, "当前暂无可用创作资源，请稍后重试")
        XCTAssertFalse(offline.userFacingUnavailableMessage.contains("worker"))
        XCTAssertFalse(closed.userFacingUnavailableMessage.contains("cron"))
    }

    func testSquareDetailUsesPublicDetailEndpoint() async throws {
        let capturedRequests = AiGenerationClientRequestProbe()
        let session = URLSession(
            configuration: .aiGenerationClientMock { request in
                Task {
                    await capturedRequests.capture(request)
                }
                return """
                {"id":82,"userId":7,"promptCn":"雨夜街角","width":768,"height":1024,"publicCategory":"GENERAL","imageUrl":"https://cdn.example.com/public/82.png","createdAt":"2026-07-10T12:00:00"}
                """
            }
        )
        let client = AiGenerationClient(apiClient: makeAPIClient(session: session))

        let work = try await client.squareDetail(id: 82)

        XCTAssertEqual(work.id, 82)
        XCTAssertEqual(work.promptCn, "雨夜街角")
        XCTAssertEqual(work.imageUrl, "https://cdn.example.com/public/82.png")
        let urls = await capturedRequests.urls
        XCTAssertEqual(urls, ["https://api.example.com/ai/square/82"])
    }

    func testSquareCanRequestOnlyOneOwnersPublicWorks() async throws {
        let capturedRequests = AiGenerationClientRequestProbe()
        let session = URLSession(
            configuration: .aiGenerationClientMock { request in
                Task {
                    await capturedRequests.capture(request)
                }
                return """
                {"total":0,"page":1,"pageSize":20,"list":[]}
                """
            }
        )
        let client = AiGenerationClient(apiClient: makeAPIClient(session: session))

        _ = try await client.square(page: 1, pageSize: 20, ownerID: 7)

        let urls = await capturedRequests.urls
        XCTAssertEqual(urls, ["https://api.example.com/ai/square?page=1&pageSize=20&ownerId=7"])
    }

    func testSettingSquareLikeUsesIdempotentPutAndReturnsUpdatedState() async throws {
        let capturedRequests = AiGenerationClientRequestProbe()
        let session = URLSession(
            configuration: .aiGenerationClientMock { request in
                Task {
                    await capturedRequests.capture(request)
                }
                return """
                {"id":82,"userId":8,"promptCn":"雨夜街角","width":768,"height":1024,"publicCategory":"GENERAL","imageUrl":"https://cdn.example.com/public/82.png","likeCount":4,"favoriteCount":2,"likedByMe":true,"favoritedByMe":false}
                """
            }
        )
        let client = AiGenerationClient(apiClient: makeAPIClient(session: session))

        let work = try await client.setSquareLiked(id: 82, liked: true)

        XCTAssertEqual(work.likeCount, 4)
        XCTAssertTrue(work.likedByMe)
        let requests = await capturedRequests.requests
        XCTAssertEqual(requests, ["PUT https://api.example.com/ai/square/82/like"])
    }

    func testRemovingSquareFavoriteUsesIdempotentDelete() async throws {
        let capturedRequests = AiGenerationClientRequestProbe()
        let session = URLSession(
            configuration: .aiGenerationClientMock { request in
                Task {
                    await capturedRequests.capture(request)
                }
                return """
                {"id":82,"userId":8,"promptCn":"雨夜街角","width":768,"height":1024,"publicCategory":"GENERAL","imageUrl":"https://cdn.example.com/public/82.png","likeCount":4,"favoriteCount":1,"likedByMe":true,"favoritedByMe":false}
                """
            }
        )
        let client = AiGenerationClient(apiClient: makeAPIClient(session: session))

        let work = try await client.setSquareFavorited(id: 82, favorited: false)

        XCTAssertEqual(work.favoriteCount, 1)
        XCTAssertFalse(work.favoritedByMe)
        let requests = await capturedRequests.requests
        XCTAssertEqual(requests, ["DELETE https://api.example.com/ai/square/82/favorite"])
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
    private(set) var requests: [String] = []

    func capture(_ request: URLRequest) {
        urls.append(request.url?.absoluteString ?? "")
        requests.append("\(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
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
