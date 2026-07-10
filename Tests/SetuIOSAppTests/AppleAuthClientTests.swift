import Foundation
import XCTest
@testable import SetuIOSCore

final class AppleAuthClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        AppleAuthMockURLProtocol.handler = nil
    }

    func testLoginPostsIdentityTokenAndNonceWithoutRequestSignature() async throws {
        let probe = AppleAuthRequestProbe()
        let session = URLSession(configuration: .appleAuthMock { request in
            let body = request.httpBody ?? request.httpBodyStream.flatMap(Self.readBody)
            Task { await probe.capture(request, body: body) }
            return #"{"userId":7,"role":0,"signSecret":"secret","expireAt":4102444800000}"#
        })
        let client = AppleAuthClient(apiClient: makeAPIClient(session: session))

        let response = try await client.login(identityToken: "apple-token", nonce: "raw-nonce")

        XCTAssertEqual(response.userId, 7)
        let request = await probe.request
        XCTAssertEqual(request?.url?.path, "/auth/apple/login")
        XCTAssertNil(request?.value(forHTTPHeaderField: "X-Signature"))
        let capturedBody = await probe.body
        let body = try XCTUnwrap(capturedBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["identityToken"], "apple-token")
        XCTAssertEqual(json["nonce"], "raw-nonce")
    }

    private func makeAPIClient(session: URLSession) -> APIClient {
        APIClient(
            config: AppConfig(
                apiBaseURL: URL(string: "https://api.example.com")!,
                siteBaseURL: URL(string: "https://example.com")!
            ),
            signer: AuthSigner(keychain: AppleAuthTestKeychain()),
            session: session
        )
    }

    private static func readBody(_ stream: InputStream) -> Data? {
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }
}

private actor AppleAuthRequestProbe {
    private(set) var request: URLRequest?
    private(set) var body: Data?
    func capture(_ request: URLRequest, body: Data?) {
        self.request = request
        self.body = body
    }
}

private final class AppleAuthTestKeychain: KeychainStoring, @unchecked Sendable {
    func string(for key: String) throws -> String? { nil }
    func setString(_ value: String, for key: String) throws {}
    func remove(_ key: String) throws {}
}

private final class AppleAuthMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> String)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = Self.handler?(request) ?? "{}"
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private extension URLSessionConfiguration {
    static func appleAuthMock(handler: @escaping (URLRequest) -> String) -> URLSessionConfiguration {
        AppleAuthMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppleAuthMockURLProtocol.self]
        return configuration
    }
}
