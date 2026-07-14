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

    func testMobileSessionDiagnosticsDoesNotExposeSecretValues() throws {
        let keychain = InMemoryKeychain()
        let session = makeSession(keychain: keychain)
        try keychain.setString("secret-value", for: "signSecret")
        let cookie = HTTPCookie(properties: [
            .domain: "api.example.com",
            .path: "/",
            .name: "SID",
            .value: "sid-secret-value",
            .secure: "TRUE",
        ])!
        HTTPCookieStorage.shared.setCookie(cookie)
        defer { HTTPCookieStorage.shared.deleteCookie(cookie) }

        let diagnostics = session.mobileSessionDiagnostics()

        XCTAssertEqual(diagnostics.apiHost, "api.example.com")
        XCTAssertTrue(diagnostics.hasSIDCookie)
        XCTAssertTrue(diagnostics.hasSignSecret)
        XCTAssertGreaterThanOrEqual(diagnostics.cookieCount, 1)
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

    func testInvalidateLocalSessionClearsSIDCookie() throws {
        let keychain = InMemoryKeychain()
        let session = makeSession(keychain: keychain)
        let cookie = HTTPCookie(properties: [
            .domain: "api.example.com",
            .path: "/",
            .name: "SID",
            .value: "stale-session",
            .secure: "TRUE",
        ])!
        HTTPCookieStorage.shared.setCookie(cookie)

        session.invalidateLocalSession()

        let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://api.example.com")!) ?? []
        XCTAssertFalse(cookies.contains { $0.name == "SID" })
    }

    func testResetLocalSessionClearsLocalCredentialsAndCookiesWithoutError() throws {
        let keychain = InMemoryKeychain()
        let session = makeSession(keychain: keychain)
        try keychain.setString("secret", for: "signSecret")
        let cookie = HTTPCookie(properties: [
            .domain: "api.example.com",
            .path: "/",
            .name: "SID",
            .value: "stale-session",
            .secure: "TRUE",
        ])!
        HTTPCookieStorage.shared.setCookie(cookie)
        session.lastError = "旧错误"

        session.resetLocalSession()

        let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://api.example.com")!) ?? []
        XCTAssertNil(try keychain.string(for: "signSecret"))
        XCTAssertFalse(cookies.contains { $0.name == "SID" })
        XCTAssertNil(session.currentUser)
        XCTAssertNil(session.expireAt)
        XCTAssertNil(session.lastError)
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

    func testLoginErrorDoesNotExposeHTTPOrDiagnosticIdentifiers() async {
        let session = makeSession(
            keychain: InMemoryKeychain(),
            urlSession: URLSession(
                configuration: .mock { _ in
                    MockHTTPResponse(
                        statusCode: 401,
                        body: #"{"message":"signature invalid","traceId":"trace-secret"}"#,
                        headers: ["X-Request-Id": "request-secret"]
                    )
                }
            )
        )

        await session.login(email: "user@example.com", password: "wrong", captchaCode: "ABCD", captchaUuid: "uuid")

        XCTAssertEqual(session.lastError, "邮箱、密码或验证码不正确，请重新输入")
        XCTAssertFalse(session.lastError?.contains("HTTP") == true)
        XCTAssertFalse(session.lastError?.contains("request-secret") == true)
        XCTAssertFalse(session.lastError?.contains("trace-secret") == true)
    }

    func testApplyUserProfileUpdatesAndPersistsCurrentUser() throws {
        let keychain = InMemoryKeychain()
        let session = makeSession(keychain: keychain)
        try session.applyLoginResponse(
            LoginResponse(
                token: nil,
                role: .user,
                email: "profile@example.com",
                userId: 9,
                avatarUrl: nil,
                signSecret: "secret",
                expireAt: Int64(Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000),
                lastLoginIp: nil
            )
        )

        try session.applyUserProfile(
            UserProfile(
                id: 9,
                email: "profile@example.com",
                nickname: "新昵称",
                avatarUrl: "https://example.com/new-avatar.jpg",
                role: .user,
                createdAt: "2026-07-07T00:00:00",
                lastLoginIp: "127.0.0.2"
            )
        )

        let restored = makeSession(keychain: keychain)

        XCTAssertEqual(session.currentUser?.nickname, "新昵称")
        XCTAssertEqual(session.currentUser?.avatarUrl, "https://example.com/new-avatar.jpg")
        XCTAssertEqual(restored.currentUser?.nickname, "新昵称")
        XCTAssertEqual(restored.currentUser?.avatarUrl, "https://example.com/new-avatar.jpg")
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

    func testRequestsIncludeTraceableRequestID() async throws {
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

        let requestID = await capturedRequest.lastRequest?.value(forHTTPHeaderField: "X-Request-Id")
        XCTAssertNotNil(UUID(uuidString: requestID ?? ""))
    }

    func testSignedRequestRefreshesMissingSignatureBeforeSending() async throws {
        let keychain = InMemoryKeychain()
        let capturedRequest = RequestProbe()
        let refreshNotifier = SignatureRefreshNotifier()
        refreshNotifier.setHandler {
            try? keychain.setString("refreshed-secret", for: "signSecret")
            return true
        }
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
            session: session,
            signatureRefreshNotifier: refreshNotifier
        )

        let _: EmptyResponse = try await client.get("/user/info")

        let signature = await capturedRequest.lastRequest?.value(forHTTPHeaderField: "X-Signature")
        let timestamp = await capturedRequest.lastRequest?.value(forHTTPHeaderField: "X-Timestamp")
        let nonce = await capturedRequest.lastRequest?.value(forHTTPHeaderField: "X-Nonce")
        XCTAssertFalse(signature?.isEmpty ?? true)
        XCTAssertFalse(timestamp?.isEmpty ?? true)
        XCTAssertFalse(nonce?.isEmpty ?? true)
    }

    func testSignedRequestRefreshesAndRetriesSignatureErrorBeforeInvalidating() async throws {
        let keychain = InMemoryKeychain()
        try keychain.setString("stale-secret", for: "signSecret")
        let capturedRequests = RequestListProbe()
        let invalidated = InvalidationProbe()
        let invalidationNotifier = SessionInvalidationNotifier()
        invalidationNotifier.setHandler {
            await invalidated.markInvalidated()
        }
        let refreshNotifier = SignatureRefreshNotifier()
        refreshNotifier.setHandler {
            try? keychain.setString("fresh-secret", for: "signSecret")
            return true
        }
        let session = URLSession(
            configuration: .mock { request in
                Task {
                    await capturedRequests.capture(request)
                }
                if request.value(forHTTPHeaderField: "X-Signature") == AuthSigner.hmac(
                    message: "\(request.value(forHTTPHeaderField: "X-Timestamp") ?? ""):\(request.value(forHTTPHeaderField: "X-Nonce") ?? ""):GET:/user/info",
                    secret: "fresh-secret"
                ) {
                    return MockHTTPResponse(statusCode: 200, body: "{}")
                }
                return MockHTTPResponse(statusCode: 401, body: #"{"message":"signature invalid"}"#)
            }
        )
        let client = APIClient(
            config: AppConfig(apiBaseURL: URL(string: "https://api.example.com")!, siteBaseURL: URL(string: "https://example.com")!),
            signer: AuthSigner(keychain: keychain),
            session: session,
            sessionInvalidationNotifier: invalidationNotifier,
            signatureRefreshNotifier: refreshNotifier
        )

        let _: EmptyResponse = try await client.get("/user/info")

        let requests = await capturedRequests.requests
        let wasInvalidated = await invalidated.wasInvalidated
        XCTAssertEqual(requests.count, 2)
        XCTAssertFalse(wasInvalidated)
    }

    func testSignedRequestInvalidatesWhenSignatureErrorCannotRefresh() async throws {
        let keychain = InMemoryKeychain()
        try keychain.setString("stale-secret", for: "signSecret")
        let invalidated = InvalidationProbe()
        let invalidationNotifier = SessionInvalidationNotifier()
        invalidationNotifier.setHandler {
            await invalidated.markInvalidated()
        }
        let refreshNotifier = SignatureRefreshNotifier()
        refreshNotifier.setHandler {
            false
        }
        let session = URLSession(configuration: .mock(statusCode: 403, body: #"{"msg":"signature invalid"}"#))
        let client = APIClient(
            config: AppConfig(apiBaseURL: URL(string: "https://api.example.com")!, siteBaseURL: URL(string: "https://example.com")!),
            signer: AuthSigner(keychain: keychain),
            session: session,
            sessionInvalidationNotifier: invalidationNotifier,
            signatureRefreshNotifier: refreshNotifier
        )

        do {
            let _: EmptyResponse = try await client.get("/user/info")
            XCTFail("Expected HTTP 403")
        } catch APIError.httpStatus(403, _, _, _) {
            let wasInvalidated = await invalidated.wasInvalidated
            XCTAssertTrue(wasInvalidated)
        }
    }

    func testSignedRequestInvalidatesWhenRetriedSignatureErrorStillFails() async throws {
        let keychain = InMemoryKeychain()
        try keychain.setString("stale-secret", for: "signSecret")
        let capturedRequests = RequestListProbe()
        let invalidated = InvalidationProbe()
        let invalidationNotifier = SessionInvalidationNotifier()
        invalidationNotifier.setHandler {
            await invalidated.markInvalidated()
        }
        let refreshNotifier = SignatureRefreshNotifier()
        refreshNotifier.setHandler {
            try? keychain.setString("fresh-secret", for: "signSecret")
            return true
        }
        let session = URLSession(
            configuration: .mock { request in
                Task {
                    await capturedRequests.capture(request)
                }
                return MockHTTPResponse(statusCode: 403, body: #"{"msg":"signature invalid"}"#)
            }
        )
        let client = APIClient(
            config: AppConfig(apiBaseURL: URL(string: "https://api.example.com")!, siteBaseURL: URL(string: "https://example.com")!),
            signer: AuthSigner(keychain: keychain),
            session: session,
            sessionInvalidationNotifier: invalidationNotifier,
            signatureRefreshNotifier: refreshNotifier
        )

        do {
            let _: EmptyResponse = try await client.get("/user/info")
            XCTFail("Expected HTTP 403")
        } catch APIError.httpStatus(403, _, _, _) {
            let requests = await capturedRequests.requests
            let wasInvalidated = await invalidated.wasInvalidated
            XCTAssertEqual(requests.count, 2)
            XCTAssertTrue(wasInvalidated)
        }
    }

    func testMultipartRequestRefreshesAndRetriesSignatureErrorBeforeInvalidating() async throws {
        let keychain = InMemoryKeychain()
        try keychain.setString("stale-secret", for: "signSecret")
        let capturedRequests = RequestListProbe()
        let invalidated = InvalidationProbe()
        let invalidationNotifier = SessionInvalidationNotifier()
        invalidationNotifier.setHandler {
            await invalidated.markInvalidated()
        }
        let refreshNotifier = SignatureRefreshNotifier()
        refreshNotifier.setHandler {
            try? keychain.setString("fresh-secret", for: "signSecret")
            return true
        }
        let session = URLSession(
            configuration: .mock { request in
                Task {
                    await capturedRequests.capture(request)
                }
                if request.value(forHTTPHeaderField: "X-Signature") == AuthSigner.hmac(
                    message: "\(request.value(forHTTPHeaderField: "X-Timestamp") ?? ""):\(request.value(forHTTPHeaderField: "X-Nonce") ?? ""):POST:/user/profile/avatar-file",
                    secret: "fresh-secret"
                ) {
                    return MockHTTPResponse(statusCode: 200, body: #"{"avatarUrl":"https://example.com/avatar.jpg"}"#)
                }
                return MockHTTPResponse(statusCode: 401, body: #"{"message":"signature invalid"}"#)
            }
        )
        let client = APIClient(
            config: AppConfig(apiBaseURL: URL(string: "https://api.example.com")!, siteBaseURL: URL(string: "https://example.com")!),
            signer: AuthSigner(keychain: keychain),
            session: session,
            sessionInvalidationNotifier: invalidationNotifier,
            signatureRefreshNotifier: refreshNotifier
        )

        let response: AvatarUploadResponse = try await client.postMultipart(
            "/user/profile/avatar-file",
            fileFieldName: "file",
            fileName: "avatar.jpg",
            mimeType: "image/jpeg",
            fileData: Data([1, 2, 3])
        )

        let requests = await capturedRequests.requests
        let wasInvalidated = await invalidated.wasInvalidated
        XCTAssertEqual(response.avatarUrl, "https://example.com/avatar.jpg")
        XCTAssertEqual(requests.count, 2)
        XCTAssertFalse(wasInvalidated)
    }

    func testMultipartRequestInvalidatesWhenRetriedSignatureErrorStillFails() async throws {
        let keychain = InMemoryKeychain()
        try keychain.setString("stale-secret", for: "signSecret")
        let capturedRequests = RequestListProbe()
        let invalidated = InvalidationProbe()
        let invalidationNotifier = SessionInvalidationNotifier()
        invalidationNotifier.setHandler {
            await invalidated.markInvalidated()
        }
        let refreshNotifier = SignatureRefreshNotifier()
        refreshNotifier.setHandler {
            try? keychain.setString("fresh-secret", for: "signSecret")
            return true
        }
        let session = URLSession(
            configuration: .mock { request in
                Task {
                    await capturedRequests.capture(request)
                }
                return MockHTTPResponse(statusCode: 403, body: #"{"msg":"signature invalid"}"#)
            }
        )
        let client = APIClient(
            config: AppConfig(apiBaseURL: URL(string: "https://api.example.com")!, siteBaseURL: URL(string: "https://example.com")!),
            signer: AuthSigner(keychain: keychain),
            session: session,
            sessionInvalidationNotifier: invalidationNotifier,
            signatureRefreshNotifier: refreshNotifier
        )

        do {
            let _: AvatarUploadResponse = try await client.postMultipart(
                "/user/profile/avatar-file",
                fileFieldName: "file",
                fileName: "avatar.jpg",
                mimeType: "image/jpeg",
                fileData: Data([1, 2, 3])
            )
            XCTFail("Expected HTTP 403")
        } catch APIError.httpStatus(403, _, _, _) {
            let requests = await capturedRequests.requests
            let wasInvalidated = await invalidated.wasInvalidated
            XCTAssertEqual(requests.count, 2)
            XCTAssertTrue(wasInvalidated)
        }
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
        } catch APIError.httpStatus(401, _, _, _) {
            let wasInvalidated = await invalidated.wasInvalidated
            XCTAssertTrue(wasInvalidated)
        }
    }

    func testPublicAuthenticationFailureDoesNotInvalidateExistingSession() async throws {
        let keychain = InMemoryKeychain()
        try keychain.setString("secret", for: "signSecret")
        let notifier = SessionInvalidationNotifier()
        let invalidated = InvalidationProbe()
        notifier.setHandler {
            await invalidated.markInvalidated()
        }
        let session = URLSession(configuration: .mock(statusCode: 401, body: #"{"message":"通行密钥认证失败"}"#))
        let client = APIClient(
            config: AppConfig(apiBaseURL: URL(string: "https://api.example.com")!, siteBaseURL: URL(string: "https://example.com")!),
            signer: AuthSigner(keychain: keychain),
            session: session,
            sessionInvalidationNotifier: notifier
        )

        do {
            let _: EmptyResponse = try await client.post("/auth/passkeys/authentication/finish", signed: false)
            XCTFail("Expected HTTP 401")
        } catch APIError.httpStatus(401, _, _, _) {
            let wasInvalidated = await invalidated.wasInvalidated
            XCTAssertFalse(wasInvalidated)
        }
    }

    func testHTTPStatusErrorIncludesBackendMessageAndRequestID() async throws {
        let keychain = InMemoryKeychain()
        let session = URLSession(configuration: .mock(statusCode: 401, body: #"{"message":"Unauthorized","traceId":"trace-123"}"#))
        let client = APIClient(
            config: AppConfig(apiBaseURL: URL(string: "https://api.example.com")!, siteBaseURL: URL(string: "https://example.com")!),
            signer: AuthSigner(keychain: keychain),
            session: session
        )

        do {
            let _: EmptyResponse = try await client.get("/user/info", signed: false)
            XCTFail("Expected HTTP 401")
        } catch APIError.httpStatus(401, let message, let requestID, let traceID) {
            XCTAssertEqual(message, "Unauthorized")
            XCTAssertNotNil(UUID(uuidString: requestID ?? ""))
            XCTAssertEqual(traceID, "trace-123")
        }
    }

    func testHTTPStatusErrorUsesTraceIDHeader() async throws {
        let keychain = InMemoryKeychain()
        let session = URLSession(
            configuration: .mock { _ in
                MockHTTPResponse(
                    statusCode: 401,
                    body: #"{"message":"Unauthorized"}"#,
                    headers: ["X-Trace-Id": "header-trace-456"]
                )
            }
        )
        let client = APIClient(
            config: AppConfig(apiBaseURL: URL(string: "https://api.example.com")!, siteBaseURL: URL(string: "https://example.com")!),
            signer: AuthSigner(keychain: keychain),
            session: session
        )

        do {
            let _: EmptyResponse = try await client.get("/user/info", signed: false)
            XCTFail("Expected HTTP 401")
        } catch APIError.httpStatus(401, _, _, let traceID) {
            XCTAssertEqual(traceID, "header-trace-456")
        }
    }
}

private actor RequestProbe {
    private(set) var lastRequest: URLRequest?

    func capture(_ request: URLRequest) {
        lastRequest = request
    }
}

private actor RequestListProbe {
    private(set) var requests: [URLRequest] = []

    func capture(_ request: URLRequest) {
        requests.append(request)
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
            headerFields: ["Content-Type": "application/json"].merging(result.headers) { _, value in value }
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
    let headers: [String: String]

    init(statusCode: Int, body: String, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.body = Data(body.utf8)
        self.headers = headers
    }

    init(statusCode: Int, body: Data, headers: [String: String] = [:]) {
        self.statusCode = statusCode
        self.body = body
        self.headers = headers
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
