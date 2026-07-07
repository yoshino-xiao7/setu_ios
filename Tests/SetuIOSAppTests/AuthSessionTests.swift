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

    func testLoginClearsLocalStateWhenSessionConfirmationReturnsUnauthorized() async throws {
        let keychain = InMemoryKeychain()
        let session = makeSession(
            keychain: keychain,
            urlSession: URLSession(
                configuration: .mock { request in
                    switch request.url?.path {
                    case "/auth/login":
                        return MockHTTPResponse(
                            statusCode: 200,
                            body: """
                            {"data":{"role":0,"email":"user@example.com","userId":3,"signSecret":"secret","expireAt":4102444800000}}
                            """
                        )
                    case "/user/info":
                        return MockHTTPResponse(statusCode: 401, body: #"{"message":"Unauthorized"}"#)
                    default:
                        return MockHTTPResponse(statusCode: 404, body: "{}")
                    }
                }
            )
        )

        await session.login(email: "user@example.com", password: "password", captchaCode: "ABCD", captchaUuid: "uuid")

        XCTAssertFalse(session.isSignedIn)
        XCTAssertNil(session.currentUser)
        XCTAssertNil(try keychain.string(for: "signSecret"))
        XCTAssertEqual(session.lastError, "登录会话确认失败，请重新登录")
    }

    func testLoginPersistsProfileAfterSessionConfirmationSucceeds() async throws {
        let keychain = InMemoryKeychain()
        let session = makeSession(
            keychain: keychain,
            urlSession: URLSession(
                configuration: .mock { request in
                    switch request.url?.path {
                    case "/auth/login":
                        return MockHTTPResponse(
                            statusCode: 200,
                            body: """
                            {"data":{"role":0,"email":"user@example.com","userId":3,"signSecret":"secret","expireAt":4102444800000}}
                            """
                        )
                    case "/user/info":
                        return MockHTTPResponse(
                            statusCode: 200,
                            body: """
                            {"data":{"id":3,"email":"user@example.com","nickname":"Yuki","avatarUrl":null,"role":0,"createdAt":"2026-07-07T00:00:00","lastLoginIp":"127.0.0.1"}}
                            """
                        )
                    default:
                        return MockHTTPResponse(statusCode: 404, body: "{}")
                    }
                }
            )
        )

        await session.login(email: "user@example.com", password: "password", captchaCode: "ABCD", captchaUuid: "uuid")

        XCTAssertTrue(session.isSignedIn)
        XCTAssertEqual(session.currentUser?.nickname, "Yuki")
        XCTAssertEqual(try keychain.string(for: "signSecret"), "secret")
    }

    private func makeSession(keychain: InMemoryKeychain, urlSession: URLSession = .shared) -> AuthSession {
        let signer = AuthSigner(keychain: keychain)
        let client = APIClient(
            config: AppConfig(apiBaseURL: URL(string: "https://api.example.com")!, siteBaseURL: URL(string: "https://example.com")!),
            signer: signer,
            session: urlSession
        )
        return AuthSession(apiClient: client, keychain: keychain)
    }
}

final class APIClientUnauthorizedTests: XCTestCase {
    func testLiveSessionConfigurationUsesSharedCookies() {
        let configuration = APIClient.liveSessionConfiguration()

        XCTAssertTrue(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.httpCookieAcceptPolicy, .always)
        XCTAssertTrue(configuration.httpCookieStorage === HTTPCookieStorage.shared)
    }

    func testRequestsExplicitlyAllowCookieHandling() async throws {
        let keychain = InMemoryKeychain()
        let capturedRequest = RequestProbe()
        let session = URLSession(
            configuration: .mock { request in
                Task {
                    await capturedRequest.capture(request)
                }
                return MockHTTPResponse(statusCode: 200, body: "{}")
            }
        )
        let client = APIClient(
            config: AppConfig(apiBaseURL: URL(string: "https://api.example.com")!, siteBaseURL: URL(string: "https://example.com")!),
            signer: AuthSigner(keychain: keychain),
            session: session
        )

        let _: EmptyResponse = try await client.get("/auth/captcha", signed: false)

        let handlesCookies = await capturedRequest.lastRequest?.httpShouldHandleCookies
        XCTAssertEqual(handlesCookies, true)
    }

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

private actor RequestProbe {
    private(set) var lastRequest: URLRequest?

    func capture(_ request: URLRequest) {
        lastRequest = request
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
    nonisolated(unsafe) static var handler: ((URLRequest) -> MockHTTPResponse)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let result = Self.handler?(request) ?? MockHTTPResponse(statusCode: Self.statusCode, body: Self.body)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: result.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct MockHTTPResponse {
    let statusCode: Int
    let body: Data

    init(statusCode: Int, body: String) {
        self.statusCode = statusCode
        self.body = Data(body.utf8)
    }

    init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

private extension URLSessionConfiguration {
    static func mock(statusCode: Int, body: String) -> URLSessionConfiguration {
        MockURLProtocol.statusCode = statusCode
        MockURLProtocol.body = Data(body.utf8)
        MockURLProtocol.handler = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return configuration
    }

    static func mock(handler: @escaping (URLRequest) -> MockHTTPResponse) -> URLSessionConfiguration {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return configuration
    }
}
