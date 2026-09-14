import Foundation
import XCTest
@testable import SetuIOSCore

final class AdminCloudVideoClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        AdminCloudVideoMockURLProtocol.handler = nil
    }

    func testCreateUploadSessionPostsTitle() async throws {
        let probe = AdminCloudVideoRequestProbe()
        let client = makeClient { request in
            probe.capture(request)
            return #"{"id":11,"bunnyVideoId":"guid","libraryId":99,"tusEndpoint":"https://video.bunnycdn.com/tusupload","authorizationSignature":"sig","authorizationExpire":1700000000,"title":"新片","status":"uploading"}"#
        }

        let session = try await client.createUploadSession(title: "新片")

        XCTAssertEqual(session.id, 11)
        XCTAssertEqual(session.bunnyVideoId, "guid")
        XCTAssertEqual(probe.lastURL, "https://api.example.com/admin/cloud-video/upload-sessions")
        XCTAssertEqual(probe.lastMethod, "POST")
        XCTAssertTrue(probe.lastBody?.contains("新片") == true)
    }

    func testRefreshTicketPostsExistingId() async throws {
        let probe = AdminCloudVideoRequestProbe()
        let client = makeClient { request in
            probe.capture(request)
            return #"{"id":11,"bunnyVideoId":"guid","libraryId":99,"tusEndpoint":"https://video.bunnycdn.com/tusupload","authorizationSignature":"sig2","authorizationExpire":1800000000,"title":"新片","status":"uploading"}"#
        }

        let session = try await client.refreshTusTicket(id: 11)

        XCTAssertEqual(session.authorizationSignature, "sig2")
        XCTAssertEqual(probe.lastURL, "https://api.example.com/admin/cloud-video/11/tus-ticket")
        XCTAssertEqual(probe.lastMethod, "POST")
    }

    func testListUsesAdminPageQuery() async throws {
        let probe = AdminCloudVideoRequestProbe()
        let client = makeClient { request in
            probe.capture(request)
            return #"{"total":1,"page":1,"pageSize":20,"list":[{"id":8,"title":"第一集","status":"ready","visibility":"draft","rating":"all_ages"}]}"#
        }

        let page = try await client.list(status: "ready", keywords: "第一", rating: "all_ages", page: 1, pageSize: 20)

        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.list.first?.title, "第一集")
        let url = probe.lastURL ?? ""
        XCTAssertTrue(url.contains("/admin/cloud-video?"))
        XCTAssertTrue(url.contains("status=ready"))
        XCTAssertTrue(url.contains("page=1"))
    }

    private func makeClient(handler: @escaping (URLRequest) -> String) -> AdminCloudVideoClient {
        AdminCloudVideoMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AdminCloudVideoMockURLProtocol.self]
        let keychain = AdminCloudVideoTestKeychain()
        try? keychain.setString("secret", for: "signSecret")
        return AdminCloudVideoClient(
            apiClient: APIClient(
                config: AppConfig(
                    apiBaseURL: URL(string: "https://api.example.com")!,
                    siteBaseURL: URL(string: "https://example.com")!
                ),
                signer: AuthSigner(keychain: keychain),
                session: URLSession(configuration: configuration)
            )
        )
    }
}

private final class AdminCloudVideoRequestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var url: String?
    private var method: String?
    private var body: String?

    var lastURL: String? { lock.withLock { url } }
    var lastMethod: String? { lock.withLock { method } }
    var lastBody: String? { lock.withLock { body } }

    func capture(_ request: URLRequest) {
        lock.withLock {
            url = request.url?.absoluteString
            method = request.httpMethod
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            body = data.isEmpty ? nil : String(data: data, encoding: .utf8)
        }
    }
}

private final class AdminCloudVideoTestKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func string(for key: String) throws -> String? { lock.withLock { values[key] } }
    func setString(_ value: String, for key: String) throws { lock.withLock { values[key] = value } }
    func remove(_ key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
}

private final class AdminCloudVideoMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> String)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.handler?(request) ?? "{}"
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.com")!,
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
