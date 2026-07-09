import Foundation
import XCTest
@testable import SetuIOSCore

final class ImageFeedClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        ImageFeedClientMockURLProtocol.handler = nil
    }

    func testFeedPostsMobileFeedRequestAndDecodesPreviewItems() async throws {
        let capturedRequests = ImageFeedClientRequestProbe()
        let session = URLSession(
            configuration: .imageFeedClientMock { request in
                Task {
                    await capturedRequests.capture(request)
                }
                XCTAssertEqual(request.url?.path, "/mobile/images/feed")
                return #"""
                {
                  "feedId": "feed-1",
                  "expiresAt": "2026-07-09T12:00:00Z",
                  "costPerImage": 20,
                  "balance": 80,
                  "items": [
                    {
                      "token": "token-1",
                      "pid": 114514,
                      "p": 0,
                      "uid": 42,
                      "title": "预览图",
                      "author": "画师",
                      "r18": false,
                      "width": 1200,
                      "height": 1800,
                      "tags": ["tag-a"],
                      "ext": "jpg",
                      "aiType": 0,
                      "uploadDate": 1720000000,
                      "thumbnailUrl": "https://img.example.com/thumb.jpg",
                      "previewUrl": "https://img.example.com/preview.jpg"
                    }
                  ]
                }
                """#
            }
        )
        let client = ImageFeedClient(apiClient: makeAPIClient(session: session))

        let response = try await client.feed(
            ImageFeedRequest(
                r18: 2,
                limit: 10,
                keyword: "miku",
                tags: ["vocaloid"],
                excludeAI: true,
                aspectRatio: "0.1-0.85",
                source: nil
            )
        )

        XCTAssertEqual(response.feedId, "feed-1")
        XCTAssertEqual(response.costPerImage, 20)
        XCTAssertEqual(response.balance, 80)
        XCTAssertEqual(response.items.first?.token, "token-1")
        XCTAssertEqual(response.items.first?.previewURLString, "https://img.example.com/preview.jpg")

        let capturedRequest = await capturedRequests.firstRequest()
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url, "https://api.example.com/mobile/images/feed")
        let body = try XCTUnwrap(request.body)
        XCTAssertTrue(body.contains(#""r18":2"#))
        XCTAssertTrue(body.contains(#""limit":10"#))
        XCTAssertTrue(body.contains(#""keyword":"miku""#))
        XCTAssertTrue(body.contains(#""tags":["vocaloid"]"#))
        XCTAssertTrue(body.contains(#""excludeAI":true"#))
        XCTAssertTrue(body.contains(#""aspectRatio":"0.1-0.85""#))
    }

    func testConsumePostsFeedTokenAndDecodesFullImageItem() async throws {
        let capturedRequests = ImageFeedClientRequestProbe()
        let session = URLSession(
            configuration: .imageFeedClientMock { request in
                Task {
                    await capturedRequests.capture(request)
                }
                XCTAssertEqual(request.url?.path, "/mobile/images/feed/consume")
                return #"""
                {
                  "feedId": "feed-1",
                  "token": "token-1",
                  "charged": true,
                  "cost": 20,
                  "balance": 60,
                  "item": {
                    "pid": 114514,
                    "p": 0,
                    "uid": 42,
                    "title": "完整图",
                    "author": "画师",
                    "r18": 0,
                    "width": 1200,
                    "height": 1800,
                    "tags": ["tag-a"],
                    "urls": {
                      "regular": "https://img.example.com/regular.jpg",
                      "original": "https://img.example.com/original.jpg"
                    }
                  }
                }
                """#
            }
        )
        let client = ImageFeedClient(apiClient: makeAPIClient(session: session))

        let response = try await client.consume(feedID: "feed-1", token: "token-1", reason: "open_original")

        XCTAssertTrue(response.charged)
        XCTAssertEqual(response.cost, 20)
        XCTAssertEqual(response.balance, 60)
        XCTAssertEqual(response.item.title, "完整图")
        XCTAssertEqual(response.item.originalURLString, "https://img.example.com/original.jpg")

        let capturedRequest = await capturedRequests.firstRequest()
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url, "https://api.example.com/mobile/images/feed/consume")
        let body = try XCTUnwrap(request.body)
        XCTAssertTrue(body.contains(#""feedId":"feed-1""#))
        XCTAssertTrue(body.contains(#""token":"token-1""#))
        XCTAssertTrue(body.contains(#""reason":"open_original""#))
    }

    func testMobileCapabilitiesDefaultsImageFeedFlagForOlderBackend() throws {
        let data = Data(
            #"""
            {
              "refreshSignatureSupported": true,
              "apnsDeviceRegistrationSupported": true,
              "liveActivityPushTokenSupported": true,
              "liveActivityBroadcastChannelSupported": false,
              "galleryDirectUploadSupported": true,
              "galleryMultipartUploadSupported": true,
              "galleryUploadRecoverySupported": true,
              "musicPlaybackMode": "proxy",
              "musicRangeRequestPolicy": "passthrough"
            }
            """#.utf8
        )

        let capabilities = try JSONDecoder().decode(MobileCapabilities.self, from: data)

        XCTAssertFalse(capabilities.imageFeedPreloadSupported)
    }

    private func makeAPIClient(session: URLSession) -> APIClient {
        let keychain = ImageFeedClientTestKeychain()
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

private actor ImageFeedClientRequestProbe {
    private var requests: [CapturedImageFeedRequest] = []

    func capture(_ request: URLRequest) {
        requests.append(
            CapturedImageFeedRequest(
                method: request.httpMethod,
                url: request.url?.absoluteString,
                body: Self.bodyString(from: request)
            )
        )
    }

    func firstRequest() -> CapturedImageFeedRequest? {
        requests.first
    }

    private static func bodyString(from request: URLRequest) -> String? {
        if let body = request.httpBody {
            return String(data: body, encoding: .utf8)
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return String(data: data, encoding: .utf8)
    }
}

private struct CapturedImageFeedRequest: Sendable {
    let method: String?
    let url: String?
    let body: String?
}

private final class ImageFeedClientTestKeychain: KeychainStoring, @unchecked Sendable {
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

private final class ImageFeedClientMockURLProtocol: URLProtocol {
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
    static func imageFeedClientMock(handler: @escaping (URLRequest) -> String) -> URLSessionConfiguration {
        ImageFeedClientMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageFeedClientMockURLProtocol.self]
        return configuration
    }
}
