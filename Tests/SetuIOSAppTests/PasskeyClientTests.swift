import Foundation
import XCTest
@testable import SetuIOSCore

final class PasskeyClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        PasskeyClientMockURLProtocol.handler = nil
    }

    func testListAcceptsEnvelopeDataItemsLikeFrontendPasskeyAPI() async throws {
        let capturedRequest = PasskeyClientRequestProbe()
        let session = URLSession(
            configuration: .passkeyClientMock { request in
                capturedRequest.capture(request)
                return """
                {
                  "code": 200,
                  "data": {
                    "items": [
                      {
                        "id": 5,
                        "nickname": "iPhone",
                        "transports": ["internal"],
                        "lastUsedAt": null,
                        "createdAt": "2026-07-07T11:30:00Z"
                      }
                    ]
                  }
                }
                """
            }
        )
        let client = PasskeyClient(apiClient: makeAPIClient(session: session))

        let passkeys = try await client.list()

        XCTAssertEqual(passkeys.count, 1)
        XCTAssertEqual(passkeys.first?.displayName, "iPhone")
        XCTAssertEqual(passkeys.first?.transports ?? [], ["internal"])
        let url = capturedRequest.lastURL
        XCTAssertEqual(url, "https://api.example.com/user/passkeys")
    }

    func testRegistrationCredentialEncodesEmptyClientExtensionResultsForYubico() throws {
        let credential = PasskeyRegistrationCredential(
            id: "credential-id",
            rawId: "credential-id",
            response: PasskeyAttestationResponse(
                clientDataJSON: "client-data",
                attestationObject: "attestation"
            )
        )

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(credential)) as? [String: Any])

        XCTAssertNotNil(json["clientExtensionResults"] as? [String: Any])
    }

    func testAssertionCredentialEncodesEmptyClientExtensionResultsForYubico() throws {
        let credential = PasskeyAssertionCredential(
            id: "credential-id",
            rawId: "credential-id",
            response: PasskeyAssertionResponse(
                authenticatorData: "authenticator-data",
                clientDataJSON: "client-data",
                signature: "signature",
                userHandle: "user-handle"
            )
        )

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(credential)) as? [String: Any])

        XCTAssertNotNil(json["clientExtensionResults"] as? [String: Any])
    }

    func testAuthenticationOptionsRequestIsPublicAndDoesNotUseStaleSessionSignature() async throws {
        let capturedRequest = PasskeyClientRequestProbe()
        let session = URLSession(
            configuration: .passkeyClientMock { request in
                capturedRequest.capture(request)
                return #"{"challengeId":"challenge-id","publicKey":{"challenge":"challenge","rpId":"cloud.yukiryou.icu"}}"#
            }
        )
        let client = PasskeyClient(apiClient: makeAPIClient(session: session))

        _ = try await client.beginAuthentication()

        let request = capturedRequest.lastRequest
        XCTAssertEqual(request?.url?.absoluteString, "https://api.example.com/auth/passkeys/authentication/options")
        XCTAssertNil(request?.value(forHTTPHeaderField: "X-Signature"))
        XCTAssertNil(request?.value(forHTTPHeaderField: "X-Timestamp"))
        XCTAssertNil(request?.value(forHTTPHeaderField: "X-Nonce"))
    }

    private func makeAPIClient(session: URLSession) -> APIClient {
        let keychain = PasskeyClientTestKeychain()
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

private final class PasskeyClientRequestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?

    var lastRequest: URLRequest? {
        lock.withLock { request }
    }

    var lastURL: String? {
        lastRequest?.url?.absoluteString
    }

    func capture(_ request: URLRequest) {
        lock.withLock {
            self.request = request
        }
    }
}

private final class PasskeyClientTestKeychain: KeychainStoring, @unchecked Sendable {
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

private final class PasskeyClientMockURLProtocol: URLProtocol {
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
    static func passkeyClientMock(handler: @escaping (URLRequest) -> String) -> URLSessionConfiguration {
        PasskeyClientMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PasskeyClientMockURLProtocol.self]
        return configuration
    }
}
