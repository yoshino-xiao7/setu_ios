import Foundation
import XCTest
@testable import SetuIOSCore

final class ArtworkClientTests: XCTestCase {
    override func tearDown() { ArtworkTestProtocol.handler = nil; super.tearDown() }
    func testProtectedMediaUsesHMACAndReturnsUnmodifiedBytes() async throws {
        let data = Data([0x89,0x50,0x4e,0x47,0,255,128])
        ArtworkTestProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/user/images/media/ticket")
            let time = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Timestamp"))
            let nonce = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Nonce"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Signature"), AuthSigner.hmac(message: "\(time):\(nonce):GET:/user/images/media/ticket", secret: "fixture-secret"))
            return data
        }
        let result = try await client().media("/user/images/media/ticket?scope=gallery")
        XCTAssertEqual(result, data)
    }
    func testEncodedGalleryPathSignsTheExactWireURI() async throws {
        ArtworkTestProtocol.handler = { request in
            let wirePath = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: true)?.percentEncodedPath)
            XCTAssertEqual(wirePath, "/user/images/media/ticket%2Done")
            let time = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Timestamp"))
            let nonce = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Nonce"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Signature"), AuthSigner.hmac(message: "\(time):\(nonce):GET:\(wirePath)", secret: "fixture-secret"))
            return Data([1])
        }
        _ = try await client().media("/user/images/media/ticket%2Done?scope=gallery")
    }
    func testMediaRejectsExternalURLBeforeSendingRequest() async {
        ArtworkTestProtocol.handler = { _ in XCTFail("External URL must not be requested"); return Data() }
        do { _ = try await client().media("https://untrusted.invalid/image.jpg"); XCTFail("Expected invalid URL") }
        catch { }
    }
    private func client() -> ArtworkClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ArtworkTestProtocol.self]
        let api = APIClient(config: AppConfig(apiBaseURL: URL(string: "https://api.example.com")!, siteBaseURL: URL(string: "https://example.com")!), signer: AuthSigner(keychain: ArtworkTestKeychain()), session: URLSession(configuration: config))
        return ArtworkClient(apiClient: api)
    }
}
private final class ArtworkTestKeychain: KeychainStoring, @unchecked Sendable {
    func string(for key: String) throws -> String? { key == "signSecret" ? "fixture-secret" : nil }
    func setString(_ value: String, for key: String) throws { }
    func remove(_ key: String) throws { }
}
private final class ArtworkTestProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let body = try Self.handler?(request) ?? Data()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"image/png"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
