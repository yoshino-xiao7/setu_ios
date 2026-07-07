import Foundation
import XCTest
@testable import SetuIOSCore

@MainActor
final class AuthSessionTests: XCTestCase {
    func testStartsSignedOutWithoutPersistedUser() {
        let keychain = InMemoryKeychain()
        let session = makeSession(keychain: keychain)

        XCTAssertFalse(session.isSignedIn)
        XCTAssertNil(session.currentUser)
    }

    func testPersistsAndRestoresCurrentUser() throws {
        let keychain = InMemoryKeychain()
        let session = makeSession(keychain: keychain)

        try session.applyLoginResponse(
            LoginResponse(
                token: nil,
                role: .admin,
                email: "admin@example.com",
                userId: 7,
                avatarUrl: "https://example.com/avatar.png",
                signSecret: "secret",
                expireAt: Int64(Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000),
                lastLoginIp: "127.0.0.1"
            )
        )

        let restored = makeSession(keychain: keychain)

        XCTAssertTrue(restored.isSignedIn)
        XCTAssertEqual(restored.currentUser?.id, 7)
        XCTAssertEqual(restored.currentUser?.email, "admin@example.com")
        XCTAssertEqual(restored.currentUser?.role, .admin)
    }

    func testExpiredPersistedSessionIsClearedOnStartup() throws {
        let keychain = InMemoryKeychain()
        let session = makeSession(keychain: keychain)

        try session.applyLoginResponse(
            LoginResponse(
                token: nil,
                role: .user,
                email: "user@example.com",
                userId: 3,
                avatarUrl: nil,
                signSecret: "secret",
                expireAt: Int64(Date().addingTimeInterval(-60).timeIntervalSince1970 * 1000),
                lastLoginIp: nil
            )
        )

        let restored = makeSession(keychain: keychain)

        XCTAssertFalse(restored.isSignedIn)
        XCTAssertNil(restored.currentUser)
        XCTAssertNil(try keychain.string(for: "signSecret"))
    }

    private func makeSession(keychain: InMemoryKeychain) -> AuthSession {
        let signer = AuthSigner(keychain: keychain)
        let client = APIClient(
            config: AppConfig(apiBaseURL: URL(string: "https://api.example.com")!, siteBaseURL: URL(string: "https://example.com")!),
            signer: signer
        )
        return AuthSession(apiClient: client, keychain: keychain)
    }
}

final class APIClientUnauthorizedTests: XCTestCase {
    func testUnauthorizedResponseNotifiesSessionInvalidation() async throws {
        let keychain = InMemoryKeychain()
        try keychain.setString("secret", for: "signSecret")
        let notifier = SessionInvalidationNotifier()
        let invalidated = InvalidationProbe()
        notifier.setHandler {
            await invalidated.markInvalidated()
        }
        let session = URLSession(configuration: .mock(statusCode: 401, body: #"{"message":"Unauthorized"}"#))
        let client = APIClient(
            config: AppConfig(apiBaseURL: URL(string: "https://api.example.com")!, siteBaseURL: URL(string: "https://example.com")!),
            signer: AuthSigner(keychain: keychain),
            session: session,
            sessionInvalidationNotifier: notifier
        )

        do {
            let _: EmptyResponse = try await client.get("/user/info")
            XCTFail("Expected HTTP 401")
        } catch APIError.httpStatus(401) {
            let wasInvalidated = await invalidated.wasInvalidated
            XCTAssertTrue(wasInvalidated)
        }
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

private actor InvalidationProbe {
    private var invalidated = false

    var wasInvalidated: Bool {
        invalidated
    }

    func markInvalidated() {
        invalidated = true
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var statusCode = 200
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
            statusCode: Self.statusCode,
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
    static func mock(statusCode: Int, body: String) -> URLSessionConfiguration {
        MockURLProtocol.statusCode = statusCode
        MockURLProtocol.body = Data(body.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return configuration
    }
}
