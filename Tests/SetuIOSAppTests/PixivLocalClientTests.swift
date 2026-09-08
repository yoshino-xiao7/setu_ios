import CryptoKit
import Foundation
import XCTest
@testable import SetuIOSCore

final class PixivLocalClientTests: XCTestCase {
    func testCustomImageHostValidationAndRegisteredResourcePath() async throws {
        XCTAssertEqual(try PixivImageHost.normalizedCustomHost(" https://Images.Example.org/ "), "images.example.org")
        for input in ["", "localhost", "127.0.0.1", "http://images.example.org", "https://images.example.org/path", "images.example.org:443", "user@images.example.org", "images.example.org?q=x", "images.example.org#x", "app-api.pixiv.net", "images.local", "foo..org"] {
            XCTAssertThrowsError(try PixivImageHost.normalizedCustomHost(input), input)
        }
        let transport = PixivMockTransport()
        let client = PixivLocalClient(owner: "1", keychain: PixivMemoryKeychain(), transport: transport,
                                      imageHost: { .custom }, customImageHost: { "https://images.example.org/" })
        let auth = try await client.authorize()
        _ = try await client.complete(sessionID: auth.id, code: "fixture-code")
        let list = try await client.works()
        _ = try await client.media(XCTUnwrap(list.items.first?.pages.first?.thumbnailUrl))
        let requests = await transport.snapshot()
        let media = try XCTUnwrap(requests.last)
        XCTAssertEqual(media.url, "https://images.example.org/preview0.jpg")
        XCTAssertEqual(media.image_mirror_host, "images.example.org")
        XCTAssertEqual(Set(media.headers.keys), ["Referer", "User-Agent"])
    }

    func testSelectedMirrorOnlyReceivesRegisteredImageWithoutAccountHeaders() async throws {
        let transport = PixivMockTransport()
        let client = PixivLocalClient(owner: "1", keychain: PixivMemoryKeychain(), transport: transport, imageHost: { .mirror })
        let auth = try await client.authorize()
        _ = try await client.complete(sessionID: auth.id, code: "fixture-code")
        let list = try await client.works()
        let path = try XCTUnwrap(list.items.first?.pages.first?.thumbnailUrl)
        _ = try await client.media(path)
        _ = try await client.media(path)
        let requests = await transport.snapshot()
        let images = requests.filter { URL(string: $0.url)?.host == "i.pixiv.re" }
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.url, "https://i.pixiv.re/preview0.jpg")
        XCTAssertEqual(Set(try XCTUnwrap(images.first).headers.keys), ["Referer", "User-Agent"])
        XCTAssertTrue(requests.contains { URL(string: $0.url)?.host == "app-api.pixiv.net" && $0.headers["Authorization"] != nil })
        do { _ = try await client.media("https://i.pixiv.re/anything.jpg"); XCTFail("Arbitrary mirror URL accepted") } catch { }
        for raw in ["https://app-api.pixiv.net/v1/illust/detail", "https://s.pximg.net/file.png", "http://i.pximg.net/a.jpg", "https://i.pximg.net.evil/a.jpg", "https://user@i.pximg.net/a.jpg"] {
            XCTAssertEqual(PixivImageHost.mirror.resourceURL(raw), raw)
        }
        XCTAssertEqual(PixivImageHost.mirror.resourceURL("https://i-cf.pximg.net/a.jpg"), "https://i.pixiv.re/a.jpg")
    }

    func testMediaCacheEvictsLeastRecentlyViewedWithinByteAndCountLimits() {
        var cache = PixivMediaCache(byteLimit: 6, countLimit: 2)
        cache.insert(Data([1, 2]), for: "a")
        cache.insert(Data([3, 4]), for: "b")
        XCTAssertNotNil(cache.value(for: "a"))
        cache.insert(Data([5, 6]), for: "c")
        XCTAssertNil(cache.value(for: "b"))
        XCTAssertEqual(cache.byteCount, 4)
        cache.insert(Data(repeating: 7, count: 5), for: "d")
        XCTAssertNil(cache.value(for: "a")); XCTAssertNil(cache.value(for: "c"))
        XCTAssertEqual(cache.byteCount, 5)
        cache.insert(Data(repeating: 8, count: 7), for: "oversized")
        XCTAssertNil(cache.value(for: "oversized")); XCTAssertNotNil(cache.value(for: "d"))
        cache.removeAll()
        XCTAssertEqual(cache.byteCount, 0); XCTAssertNil(cache.value(for: "d"))
    }

    func testConcurrentViewsShareDownloadAndFailureCanBeRetried() async throws {
        let transport = PixivMockTransport(mediaFailures: 1)
        let client = PixivLocalClient(owner: "1", keychain: PixivMemoryKeychain(), transport: transport)
        let auth = try await client.authorize()
        _ = try await client.complete(sessionID: auth.id, code: "fixture-code")
        let list = try await client.works()
        let path = try XCTUnwrap(list.items.first?.pages.first?.thumbnailUrl)
        do { _ = try await client.media(path); XCTFail("Failed download cached") } catch { }
        let leaving = Task { try await client.media(path) }
        let staying = Task { try await client.media(path) }
        try await Task.sleep(for: .milliseconds(10))
        leaving.cancel()
        let data = try await staying.value
        XCTAssertFalse(data.isEmpty)
        do { _ = try await leaving.value; XCTFail("Cancelled view received data") } catch is CancellationError { }
        _ = try await client.media(path)
        let count = await transport.snapshot().filter { $0.url.contains("pximg.net") }.count
        XCTAssertEqual(count, 2, "One failed download plus one shared successful retry")
    }

    func testReturningToLoadedImageAndRefreshingFeedDoNotDownloadItAgain() async throws {
        let transport = PixivMockTransport()
        let client = PixivLocalClient(owner: "1", keychain: PixivMemoryKeychain(), transport: transport)
        let auth = try await client.authorize()
        _ = try await client.complete(sessionID: auth.id, code: "fixture-code")
        let first = try await client.works()
        let path = try XCTUnwrap(first.items.first?.pages.first?.thumbnailUrl)
        let data = try await client.media(path)
        for _ in 0..<3 {
            let revisited = try await client.media(path)
            XCTAssertEqual(revisited, data)
        }
        let refreshed = try await client.works()
        let refreshedPath = try XCTUnwrap(refreshed.items.first?.pages.first?.thumbnailUrl)
        _ = try await client.media(refreshedPath)
        let requests = await transport.snapshot().filter { $0.url.contains("pximg.net") }
        XCTAssertEqual(requests.count, 1, "Scrolling back and refreshed capabilities must reuse the downloaded image")
        try await client.unlink()
        do { _ = try await client.media(path); XCTFail("Unlinked cache remained accessible") } catch { }
        let next = try await client.authorize()
        _ = try await client.complete(sessionID: next.id, code: "fixture-code")
        let rebound = try await client.works()
        _ = try await client.media(XCTUnwrap(rebound.items.first?.pages.first?.thumbnailUrl))
        let after = await transport.snapshot().filter { $0.url.contains("pximg.net") }
        XCTAssertEqual(after.count, 2, "Rebinding must clear cached media")
    }

    func testOAuthUsesCompatibleClientHeadersAndReportsExchangeStageWithoutResponseSecrets() async throws {
        let transport = PixivMockTransport(tokenStatus: 403)
        let keychain = PixivMemoryKeychain()
        let client = PixivLocalClient(owner: "1", keychain: keychain, transport: transport)
        let auth = try await client.authorize()
        do {
            _ = try await client.complete(sessionID: auth.id, code: "fixture-sensitive-code")
            XCTFail("Rejected token exchange accepted")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("令牌交换被拒绝（HTTP 403）"))
            XCTAssertFalse(error.localizedDescription.contains("fixture-sensitive"))
        }
        let requests = await transport.snapshot()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.headers["User-Agent"], "PixivAndroidApp/5.0.155 (Android 6.0; Pixel C)")
        XCTAssertEqual(request.headers["App-OS"], "Android")
        XCTAssertEqual(request.headers["App-OS-Version"], "Android 6.0")
        XCTAssertEqual(request.headers["Content-Type"], "application/x-www-form-urlencoded")
        XCTAssertTrue(keychain.values.isEmpty)
        do { _ = try await client.complete(sessionID: auth.id, code: "fixture-sensitive-code"); XCTFail("Reused failed code") } catch { }
        let count = await transport.snapshot().count
        XCTAssertEqual(count, 1, "A denied authorization code must not be retried automatically")
    }

    func testRefreshCannotChangeBoundAccount() async throws {
        let transport = PixivMockTransport(expireFirstToken: true, refreshAccountID: 88)
        let client = PixivLocalClient(owner: "1", keychain: PixivMemoryKeychain(), transport: transport)
        let session = try await client.authorize()
        _ = try await client.complete(sessionID: session.id, code: "fixture-code")
        do { _ = try await client.works(); XCTFail("Refresh changed bound Pixiv account") } catch { }
        let binding = try await client.binding()
        XCTAssertEqual(binding.accountId, "77")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2, "Rejected refresh must not send a works request")
    }

    func testForeignAndStaleCapabilitiesCannotFetchAnotherBindingMedia() async throws {
        let transport = PixivMockTransport()
        let first = PixivLocalClient(owner: "1", keychain: PixivMemoryKeychain(), transport: transport)
        let second = PixivLocalClient(owner: "2", keychain: PixivMemoryKeychain(), transport: transport)
        for client in [first, second] {
            let session = try await client.authorize()
            _ = try await client.complete(sessionID: session.id, code: "fixture-code")
        }
        let list = try await first.works()
        let cursor = try XCTUnwrap(list.nextCursor)
        let media = try XCTUnwrap(list.items.first?.pages.first?.thumbnailUrl)
        XCTAssertNil(list.items.first?.pages.first?.originalUrl, "Feed must not register originals")
        for client in [second] {
            do { _ = try await client.works(params: ["cursor": cursor]); XCTFail("Foreign cursor accepted") } catch { }
            do { _ = try await client.media(media); XCTFail("Foreign media accepted") } catch { }
        }
        let before = await transport.requests.count
        let session = try await first.authorize()
        _ = try await first.complete(sessionID: session.id, code: "new-fixture-code")
        do { _ = try await first.works(params: ["cursor": cursor]); XCTFail("Stale cursor accepted") } catch { }
        do { _ = try await first.media(media); XCTFail("Stale media accepted") } catch { }
        let after = await transport.requests.count
        XCTAssertEqual(after, before + 1, "Only reauthorization may reach the network")
    }

    func testMultipageDetailAndUntrustedNextURL() async throws {
        let transport = PixivMockTransport()
        let client = PixivLocalClient(owner: "1", keychain: PixivMemoryKeychain(), transport: transport)
        let session = try await client.authorize()
        _ = try await client.complete(sessionID: session.id, code: "fixture-code")
        let detail = try await client.detail(id: "123")
        XCTAssertEqual(detail.pages.count, 2)
        XCTAssertEqual(detail.pages.map(\.index), [0, 1])
        for page in detail.pages { _ = try await client.media(XCTUnwrap(page.originalUrl)) }
        let images = await transport.requests.filter { $0.url.contains("pximg.net") }
        XCTAssertEqual(images.map(\.url), ["https://i.pximg.net/p0.jpg", "https://i.pximg.net/p1.jpg"])
        XCTAssertTrue(images.allSatisfy { $0.headers["Authorization"] == nil })
        await transport.setNextURL("https://attacker.invalid/?token=steal")
        do { _ = try await client.works(); XCTFail("Untrusted pagination accepted") } catch { }
        let requests = await transport.requests
        XCTAssertFalse(requests.contains { $0.url.contains("attacker.invalid") })
    }

    func testExpiredTokenRefreshIsCoalescedAcrossConcurrentRequests() async throws {
        let transport = PixivMockTransport(expireFirstToken: true)
        let client = PixivLocalClient(owner: "1", keychain: PixivMemoryKeychain(), transport: transport)
        let auth = try await client.authorize()
        _ = try await client.complete(sessionID: auth.id, code: "fixture-code")
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { _ = try await client.works() } }
            try await group.waitForAll()
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.filter { $0.url.contains("/auth/token") }.count, 2)
        XCTAssertEqual(requests.filter { $0.url.contains("/illust/recommended") }.count, 8)
        XCTAssertTrue(requests.allSatisfy { $0.headers["Cookie"] == nil && $0.headers["X-Signature"] == nil })
    }
    func testPKCEIsOneUseAndCredentialsStayInOwnerKeychain() async throws {
        let keychain = PixivMemoryKeychain()
        let transport = PixivMockTransport()
        let first = PixivLocalClient(owner: "1", keychain: keychain, transport: transport)
        let second = PixivLocalClient(owner: "2", keychain: keychain, transport: transport)
        let session = try await first.authorize()
        do { _ = try await second.complete(sessionID: session.id, code: "fixture-code"); XCTFail("Wrong owner accepted session") } catch { }
        let binding = try await first.complete(sessionID: session.id, code: "fixture-code")
        XCTAssertEqual(binding.accountId, "77")
        let other = try await second.binding()
        XCTAssertFalse(other.bound)
        do { _ = try await first.complete(sessionID: session.id, code: "fixture-code"); XCTFail("Consumed session accepted") } catch { }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(URL(string: requests[0].url)?.host, "oauth.secure.pixiv.net")
        XCTAssertNil(requests[0].headers["Cookie"])
        XCTAssertNil(requests[0].headers["X-Signature"])
        let form = URLComponents(string: "https://fixture.invalid/?" + (requests[0].body ?? ""))?.queryItems ?? []
        let verifier = try XCTUnwrap(form.first { $0.name == "code_verifier" }?.value)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let urlChallenge = URLComponents(string: session.loginUrl)?.queryItems?.first { $0.name == "code_challenge" }?.value
        XCTAssertEqual(challenge, urlChallenge)
        XCTAssertTrue(keychain.values.keys.allSatisfy { $0.hasPrefix("pixiv.local.1") })
        try await first.unlink()
        XCTAssertTrue(keychain.values.isEmpty)
    }
}
final class PixivMemoryKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]
    var values: [String: String] { lock.lock(); defer { lock.unlock() }; return storage }
    func string(for key: String) throws -> String? { lock.lock(); defer { lock.unlock() }; return storage[key] }
    func setString(_ value: String, for key: String) throws { lock.lock(); defer { lock.unlock() }; storage[key] = value }
    func remove(_ key: String) throws { lock.lock(); defer { lock.unlock() }; storage.removeValue(forKey: key) }
}
actor PixivMockTransport: PixivHTTPTransport {
    var requests: [PixivHTTPRequest] = []
    let expireFirstToken: Bool
    let refreshAccountID: Int
    let tokenStatus: Int
    var mediaFailures: Int
    func snapshot() -> [PixivHTTPRequest] { requests }
    var nextURL = "https://app-api.pixiv.net/v1/illust/recommended?offset=30"
    init(expireFirstToken: Bool = false, refreshAccountID: Int = 77, tokenStatus: Int = 200, mediaFailures: Int = 0) { self.expireFirstToken = expireFirstToken; self.refreshAccountID = refreshAccountID; self.tokenStatus = tokenStatus; self.mediaFailures = mediaFailures }
    func setNextURL(_ url: String) { nextURL = url }
    func send(_ request: PixivHTTPRequest) async throws -> PixivHTTPResponse {
        requests.append(request)
        if request.url.contains("pximg.net") || request.url.contains("i.pixiv.re") || request.image_mirror_host != nil {
            try await Task.sleep(for: .milliseconds(40))
            if mediaFailures > 0 { mediaFailures -= 1; throw PixivClientError("fixture failure") }
            return PixivHTTPResponse(status: 200, data: Data([0xff, 0xd8]), contentType: "image/jpeg")
        }
        if !request.url.contains("/auth/token") {
            let work: [String: Any] = ["id": 123, "title": "fixture", "user": ["id": 77, "name": "artist"], "page_count": 2,
                "image_urls": ["medium": "https://i.pximg.net/cover.jpg"],
                "meta_pages": (0..<2).map { ["image_urls": ["original": "https://i.pximg.net/p\($0).jpg", "medium": "https://i.pximg.net/preview\($0).jpg"]] }]
            let payload: [String: Any] = request.url.contains("/illust/detail") ? ["illust": work] : ["illusts": [work], "next_url": nextURL]
            return PixivHTTPResponse(status: 200, data: try JSONSerialization.data(withJSONObject: payload), contentType: "application/json")
        }
        if tokenStatus != 200 { return PixivHTTPResponse(status: tokenStatus, data: Data("fixture-sensitive-response".utf8), contentType: "text/html") }
        let expire = expireFirstToken && requests.count == 1 ? 0 : 3600
        try await Task.sleep(for: .milliseconds(30))
        let accountID = request.body?.contains("grant_type=refresh_token") == true ? refreshAccountID : 77
        let token = "{\"access_token\":\"fixture-access\",\"refresh_token\":\"fixture-refresh\",\"expires_in\":\(expire),\"user\":{\"id\":\(accountID),\"name\":\"artist\"}}"
        return PixivHTTPResponse(status: 200, data: Data(token.utf8), contentType: "application/json")
    }
}
