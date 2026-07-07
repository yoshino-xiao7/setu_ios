import Foundation
import XCTest
@testable import SetuIOSCore

final class GalleryUploadClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        GalleryUploadClientMockURLProtocol.handler = nil
    }

    func testCreateBatchSendsIdempotencyKeyHeaderLikeFrontendUploadAPI() async throws {
        let capturedRequest = GalleryUploadClientRequestProbe()
        let session = URLSession(
            configuration: .galleryUploadClientMock { request in
                Task {
                    await capturedRequest.capture(request)
                }
                return """
                {
                  "batchId": 42,
                  "clientRequestId": "ios-request-123",
                  "pidMode": "MULTI_PID_P0",
                  "status": "UPLOADING",
                  "uploadPolicy": {
                    "provider": "mock",
                    "region": "local",
                    "bucket": "gallery",
                    "endpoint": "https://oss.example.com",
                    "prefix": "gallery/",
                    "expiresAt": "2026-07-07T12:00:00Z",
                    "maxSizeBytes": 10485760,
                    "allowedContentTypes": ["image/jpeg"],
                    "uploadUrl": null,
                    "uploadMethod": null,
                    "uploadHeaders": null
                  },
                  "items": [],
                  "credentials": null
                }
                """
            }
        )
        let client = GalleryUploadClient(apiClient: makeAPIClient(session: session))
        let request = GalleryUploadInitRequest(
            clientRequestId: "ios-request-123",
            pidMode: "MULTI_PID_P0",
            defaults: nil,
            items: [
                GalleryUploadInitItem(
                    clientItemId: "item-1",
                    filename: "image.jpg",
                    contentType: "image/jpeg",
                    sizeBytes: 128
                )
            ]
        )

        let response = try await client.createBatch(request)

        XCTAssertEqual(response.batchId, 42)
        let url = await capturedRequest.lastURL
        let idempotencyKey = await capturedRequest.lastIdempotencyKey
        XCTAssertEqual(url, "https://api.example.com/gallery/uploads/batches")
        XCTAssertEqual(idempotencyKey, "ios-request-123")
    }

    private func makeAPIClient(session: URLSession) -> APIClient {
        let keychain = GalleryUploadClientTestKeychain()
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

private actor GalleryUploadClientRequestProbe {
    private(set) var lastURL: String?
    private(set) var lastIdempotencyKey: String?

    func capture(_ request: URLRequest) {
        lastURL = request.url?.absoluteString
        lastIdempotencyKey = request.value(forHTTPHeaderField: "Idempotency-Key")
    }
}

private final class GalleryUploadClientTestKeychain: KeychainStoring, @unchecked Sendable {
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

private final class GalleryUploadClientMockURLProtocol: URLProtocol {
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
    static func galleryUploadClientMock(handler: @escaping (URLRequest) -> String) -> URLSessionConfiguration {
        GalleryUploadClientMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GalleryUploadClientMockURLProtocol.self]
        return configuration
    }
}
