import Foundation
import XCTest
@testable import SetuIOSCore

final class PixivDirectHTTPTransportTests: XCTestCase {
    override func tearDown() { PixivOAuthTestProtocol.handler = nil; super.tearDown() }

    func testSlowImagesDoNotBlockMetadataAndQueuedCancellationFinishesPromptly() async throws {
        let occupied = expectation(description: "Four image transfers occupy image slots")
        occupied.expectedFulfillmentCount = 4
        let release = DispatchSemaphore(value: 0)
        let native = PixivNativeHTTPTransport { request in
            if request.url.contains("pximg.net") {
                occupied.fulfill()
                _ = release.wait(timeout: .now() + 4)
            }
            return PixivHTTPResponse(status: 200, data: Data(), contentType: "application/json")
        }
        let image = PixivHTTPRequest(url: "https://i.pximg.net/fixture.jpg")
        let transfers = (0..<4).map { _ in Task { try await native.send(image) } }
        await fulfillment(of: [occupied], timeout: 1)
        let apiCompleted = expectation(description: "Metadata bypasses busy image slots")
        let api = Task {
            _ = try await native.send(apiRequest())
            apiCompleted.fulfill()
        }
        await fulfillment(of: [apiCompleted], timeout: 0.5)
        let cancelled = expectation(description: "Queued image cancellation does not wait for a slot")
        let queued = Task {
            do { _ = try await native.send(image); XCTFail("Cancelled image completed") }
            catch is CancellationError { cancelled.fulfill() }
        }
        try await Task.sleep(for: .milliseconds(30))
        queued.cancel()
        await fulfillment(of: [cancelled], timeout: 0.5)
        for _ in transfers { release.signal() }
        _ = try await api.value
        for transfer in transfers { _ = try await transfer.value }
    }

    func testNativeDeadlineIncludesTimeWaitingForImageSlot() async throws {
        let occupied = expectation(description: "Image queue is busy")
        occupied.expectedFulfillmentCount = 4
        let release = DispatchSemaphore(value: 0)
        let native = PixivNativeHTTPTransport(deadline: 0.2) { _ in
            occupied.fulfill()
            _ = release.wait(timeout: .now() + 3)
            return PixivHTTPResponse(status: 200, data: Data(), contentType: "image/jpeg")
        }
        let image = PixivHTTPRequest(url: "https://i.pximg.net/fixture.jpg")
        let transfers = (0..<4).map { _ in Task { try await native.send(image) } }
        await fulfillment(of: [occupied], timeout: 1)
        let start = Date()
        do { _ = try await native.send(image); XCTFail("Queued request should expire") }
        catch { XCTAssertEqual(error.localizedDescription, "Pixiv 请求超时，请重试") }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        for _ in transfers { release.signal() }
        for transfer in transfers { _ = try? await transfer.value }
    }

    func testDirectConnectionUsedWhenSystemPathUnavailable() async throws {
        let direct = PixivPathFixture(available: true)
        let system = PixivPathFixture(available: false)
        let router = PixivDirectHTTPTransport(system: system, enhanced: direct)
        let response = try await router.send(apiRequest())
        XCTAssertEqual(response.status, 200)
        let sent = await direct.requests
        XCTAssertEqual(sent.filter { $0.headers["Authorization"] != nil }.count, 1)
    }

    func testLivePublicWorksTransport() async throws {
        guard ProcessInfo.processInfo.environment["SETU_PIXIV_API_LIVE_TEST"] == "1" else {
            throw XCTSkip("Public works endpoint probe is opt-in and uses no account")
        }
        var request = PixivHTTPRequest(url: "https://app-api.pixiv.net/v1/illust/recommended?filter=for_ios&include_ranking_label=true")
        request.headers = ["User-Agent": "PixivAndroidApp/5.0.155 (Android 10.0; Pixel C)",
            "App-OS": "Android", "App-OS-Version": "Android 10.0", "App-Version": "5.0.166"]
        let response = try await PixivDirectHTTPTransport().send(request)
        XCTAssertTrue(response.contentType.contains("application/json"), "Expected API JSON, got HTTP \(response.status)")
        XCTAssertTrue([400, 401].contains(response.status), "Expected unauthenticated API validation, got HTTP \(response.status)")
    }

    func testAuthorizationRefreshAndWorksShareSelectedConnectionWhileMediaUsesRhttp() async throws {
        let system = PixivPathFixture(available: true, application: PixivMockTransport(expireFirstToken: true))
        let enhanced = PixivPathFixture(available: false)
        let client = PixivLocalClient(owner: "1", keychain: PixivMemoryKeychain(),
            transport: PixivDirectHTTPTransport(system: system, enhanced: enhanced))
        let auth = try await client.authorize()
        _ = try await client.complete(sessionID: auth.id, code: "fixture-code")
        _ = try await client.works()
        let requests = await system.requests
        let grants = requests.filter { $0.url.contains("oauth.secure.pixiv.net") }
        let works = requests.filter { $0.url.contains("app-api.pixiv.net") && $0.headers["Authorization"] != nil }
        XCTAssertEqual(grants.count, 2)
        XCTAssertTrue(grants.allSatisfy { $0.url == "https://oauth.secure.pixiv.net/auth/token" })
        XCTAssertEqual(works.count, 1)
        XCTAssertTrue(works.first?.url.contains("/illust/recommended") == true)
        let media = PixivHTTPRequest(url: "https://i.pximg.net/img-original/fixture.jpg")
        _ = try await PixivDirectHTTPTransport(system: system, enhanced: enhanced).send(media)
        let enhancedRequests = await enhanced.requests
        XCTAssertEqual(enhancedRequests.filter { $0.url.contains("pximg.net") }.map(\.url), [media.url])
    }

    func testEnhanced403SelectsSystemWithoutSendingCredentialsToProbe() async throws {
        let direct = PixivPathFixture(available: false, failureStatus: 403)
        let system = PixivPathFixture(available: true)
        let router = PixivDirectHTTPTransport(system: system, enhanced: direct)
        _ = try await router.send(apiRequest())
        let probes = await direct.requests
        XCTAssertEqual(probes.count, 1)
        XCTAssertTrue(probes.allSatisfy { $0.headers["Authorization"] == nil && $0.body == nil && $0.method == "GET" })
        let sent = await system.requests
        XCTAssertEqual(sent.filter { $0.headers["Authorization"] != nil }.count, 1)
    }

    func testChangedNetworkReselectsAndRetriesSafeReadOnlyOnce() async throws {
        let direct = PixivPathFixture(available: true)
        let system = PixivPathFixture(available: false)
        let router = PixivDirectHTTPTransport(system: system, enhanced: direct)
        _ = try await router.send(apiRequest())
        await direct.setAvailable(false)
        await system.setAvailable(true)
        let result = try await router.send(apiRequest())
        XCTAssertEqual(result.status, 200)
        let sent = await system.requests
        XCTAssertEqual(sent.filter { $0.headers["Authorization"] != nil }.count, 1)
    }

    func testConcurrentRequestsShareProbeAndCacheSelection() async throws {
        let direct = PixivPathFixture(available: true)
        let system = PixivPathFixture(available: false)
        let router = PixivDirectHTTPTransport(system: system, enhanced: direct)
        let request = apiRequest()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 { group.addTask { _ = try await router.send(request) } }
            try await group.waitForAll()
        }
        let sent = await direct.requests
        XCTAssertEqual(sent.filter { $0.headers["Authorization"] == nil }.count, 1)
        XCTAssertEqual(sent.filter { $0.headers["Authorization"] != nil }.count, 10)
    }

    func testAuthorizationAndMutationsAreNeverReplayedAfterFailure() async throws {
        for url in ["https://oauth.secure.pixiv.net/auth/token", "https://app-api.pixiv.net/v2/illust/bookmark/add"] {
            let direct = PixivPathFixture(available: true)
            let system = PixivPathFixture(available: true)
            let router = PixivDirectHTTPTransport(system: system, enhanced: direct)
            _ = try await router.send(apiRequest())
            await direct.setAvailable(false)
            var request = PixivHTTPRequest(url: url); request.method = "POST"; request.body = "fixture"
            do { _ = try await router.send(request); XCTFail("Expected failed mutation") } catch { }
            let directSent = await direct.requests, systemSent = await system.requests
            XCTAssertEqual(directSent.filter { $0.method == "POST" }.count, 1)
            XCTAssertEqual(systemSent.filter { $0.method == "POST" }.count, 0)
        }
    }

    func testOAuthRejectsForeignPathsAndSetuCredentialsBeforeNetworking() async {
        PixivOAuthTestProtocol.handler = { _ in XCTFail("Invalid request reached the network"); return (200, [:], Data()) }
        for url in ["http://oauth.secure.pixiv.net/auth/token", "https://oauth.secure.pixiv.net/auth/token?redirect=1", "https://untrusted.invalid/auth/token"] {
            var request = PixivHTTPRequest(url: url); request.method = "POST"
            do { _ = try await transport().send(request); XCTFail("Invalid URL accepted") } catch { }
        }
        for header in ["Cookie", "Authorization", "X-Signature", "Host"] {
            var request = tokenRequest(); request.headers[header] = "fixture-secret"
            do { _ = try await transport().send(request); XCTFail("Foreign credential accepted") } catch { }
        }
    }

    func testOAuthPreservesJSONStatusWithoutCookies() async throws {
        let payload = Data("{\"error\":\"invalid_grant\"}".utf8)
        PixivOAuthTestProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Signature"))
            return (400, ["Content-Type": "application/json"], payload)
        }
        let result = try await transport().send(tokenRequest())
        XCTAssertEqual(result.status, 400)
        XCTAssertEqual(result.data, payload)
    }

    func testAPIKeepsBearerAndMutationBodyWithoutSetuCookies() async throws {
        for method in ["GET", "POST"] {
            let path = method == "GET" ? "/v1/illust/recommended?filter=for_ios" : "/v2/illust/bookmark/add"
            var request = PixivHTTPRequest(url: "https://app-api.pixiv.net" + path)
            request.method = method
            request.headers = ["Authorization": "Bearer fixture-pixiv-token"]
            if method == "POST" { request.body = "illust_id=123&restrict=private" }
            PixivOAuthTestProtocol.handler = { outgoing in
                XCTAssertEqual(outgoing.httpMethod, method)
                XCTAssertEqual(outgoing.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-pixiv-token")
                XCTAssertNil(outgoing.value(forHTTPHeaderField: "Cookie"))
                XCTAssertNil(outgoing.value(forHTTPHeaderField: "X-Signature"))
                return (200, ["Content-Type": "application/json"], Data("{}".utf8))
            }
            let response = try await transport().send(request)
            XCTAssertEqual(response.status, 200)
        }
    }

    func testAPIRejectsUntrustedTargetsMethodsAndHeaders() async {
        PixivOAuthTestProtocol.handler = { _ in XCTFail("Invalid request reached the network"); return (200, [:], Data()) }
        for url in ["http://app-api.pixiv.net/v1/illust/recommended", "https://app-api.pixiv.net.evil.invalid/v1/illust/recommended",
            "https://app-api.pixiv.net:443/v1/illust/recommended", "https://user@app-api.pixiv.net/v1/illust/recommended",
            "https://app-api.pixiv.net/v1/illust/recommended#fragment", "https://app-api.pixiv.net/v1/%69llust/recommended",
            "https://app-api.pixiv.net/web/v1/login", "https://app-api.pixiv.net/v2/illust/bookmark/add"] {
            do { _ = try await transport().send(PixivHTTPRequest(url: url)); XCTFail("Invalid API URL accepted") } catch { }
        }
        for header in ["Cookie", "Host", "X-Signature", "X-Nonce", "X-Timestamp"] {
            var request = apiRequest(); request.headers[header] = "fixture-secret"
            do { _ = try await transport().send(request); XCTFail("Foreign credential accepted") } catch { }
        }
        for value in ["Basic fixture", "Bearer fixture\r\nCookie: SID=fixture"] {
            var request = apiRequest(); request.headers["Authorization"] = value
            do { _ = try await transport().send(request); XCTFail("Invalid authorization accepted") } catch { }
        }
        for method in ["POST", "DELETE", "PUT"] {
            var request = apiRequest(); request.method = method
            do { _ = try await transport().send(request); XCTFail("Invalid method accepted") } catch { }
        }
    }

    func testAPIRejectsRedirectsAndPreserves403WithoutRetrying() async throws {
        PixivOAuthTestProtocol.handler = { _ in (302, ["Location": "https://untrusted.invalid/"], Data()) }
        do { _ = try await transport().send(apiRequest()); XCTFail("API redirect accepted") } catch { }
        var calls = 0
        PixivOAuthTestProtocol.handler = { _ in calls += 1; return (403, ["Content-Type": "text/html"], Data()) }
        let response = try await transport().send(apiRequest())
        XCTAssertEqual(response.status, 403)
        XCTAssertEqual(calls, 1)
        PixivOAuthTestProtocol.handler = { _ in (200, [:], Data(repeating: 1, count: 65)) }
        var request = apiRequest(); request.max_bytes = 64
        do { _ = try await transport().send(request); XCTFail("Unbounded API response accepted") } catch { }
    }

    private func apiRequest() -> PixivHTTPRequest {
        var request = PixivHTTPRequest(url: "https://app-api.pixiv.net/v1/illust/recommended")
        request.headers = ["Authorization": "Bearer fixture-pixiv-token"]
        return request
    }

    func testOAuthRefusesRedirectAndBoundsUnknownLengthResponses() async {
        PixivOAuthTestProtocol.handler = { _ in (302, ["Location": "https://untrusted.invalid/"], Data()) }
        do { _ = try await transport().send(tokenRequest()); XCTFail("Redirect accepted") } catch { }
        PixivOAuthTestProtocol.handler = { _ in (200, ["Content-Type": "application/json"], Data(repeating: 1, count: 65)) }
        var request = tokenRequest(); request.max_bytes = 64
        do { _ = try await transport().send(request); XCTFail("Unbounded response accepted") } catch { }
    }

    private func transport() -> PixivSystemHTTPTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PixivOAuthTestProtocol.self]
        return PixivSystemHTTPTransport(configuration: configuration)
    }
    private func tokenRequest() -> PixivHTTPRequest {
        var request = PixivHTTPRequest(url: "https://oauth.secure.pixiv.net/auth/token")
        request.method = "POST"; request.body = "grant_type=authorization_code&code=fixture-code"
        request.headers = ["Content-Type": "application/x-www-form-urlencoded"]
        return request
    }
}

private actor PixivPathFixture: PixivHTTPTransport {
    var available: Bool
    var requests: [PixivHTTPRequest] = []
    let failureStatus: Int?
    let application: PixivMockTransport?
    init(available: Bool, failureStatus: Int? = nil, application: PixivMockTransport? = nil) {
        self.available = available; self.failureStatus = failureStatus; self.application = application
    }
    func setAvailable(_ value: Bool) { available = value }
    func send(_ request: PixivHTTPRequest) async throws -> PixivHTTPResponse {
        requests.append(request)
        if request.url.contains("pximg.net") { return PixivHTTPResponse(status: 200, data: Data(), contentType: "image/jpeg") }
        if !available {
            if let failureStatus { return PixivHTTPResponse(status: failureStatus, data: Data(), contentType: "text/html") }
            throw URLError(.cannotConnectToHost)
        }
        let probe = request.url.contains("app-api.pixiv.net") && request.headers["Authorization"] == nil && request.method == "GET"
        if !probe, let application { return try await application.send(request) }
        return PixivHTTPResponse(status: probe ? 400 : 200, data: Data("{}".utf8), contentType: "application/json")
    }
}

private final class PixivOAuthTestProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.handler?(request) ?? (500, [:], Data())
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
