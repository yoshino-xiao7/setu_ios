import Foundation
import XCTest
@testable import SetuIOSCore
@testable import SetuIOSApp

final class MusicRepositoryTests: XCTestCase {
    func testFirstRequestTTLExpiryForceAndPreciseInvalidation() async throws {
        let clock = MusicTestClock()
        let counter = MusicTestCounter()
        let repository = MusicRepository(client: musicTestClient(), now: { clock.now })
        let query = MusicQuery<Int>(key: .hotSearch) { _ in await counter.next() }
        let first = try await repository.value(for: query)
        XCTAssertEqual(first.value, 1)
        let hit = try await repository.value(for: query)
        XCTAssertEqual(hit.value, 1)
        clock.advance(1_801)
        let stale = await repository.cached(for: query)
        XCTAssertEqual(stale?.value, 1, "Expired data must remain available for SWR")
        let refreshed = try await repository.value(for: query)
        XCTAssertEqual(refreshed.value, 2)
        let forced = try await repository.value(for: query, force: true)
        XCTAssertEqual(forced.value, 3)
        await repository.invalidate([.playlist(7)])
        let unrelated = try await repository.value(for: query)
        XCTAssertEqual(unrelated.value, 3)
        await repository.invalidate([.hotSearch])
        let invalidated = await repository.cached(for: query)
        XCTAssertNil(invalidated)
        let reloaded = try await repository.value(for: query)
        XCTAssertEqual(reloaded.value, 4)
    }

    func testConcurrentConsumersShareOneRequest() async throws {
        let counter = MusicTestCounter()
        let gate = MusicTestGate()
        let started = expectation(description: "network started")
        let repository = MusicRepository(client: musicTestClient())
        let query = MusicQuery<Int>(key: .hotSearch) { _ in
            let result = await counter.next()
            started.fulfill()
            await gate.wait()
            return result
        }
        let callers = Task {
            try await withThrowingTaskGroup(of: Int.self) { group in
                for _ in 0..<20 { group.addTask { try await repository.value(for: query).value } }
                var values: [Int] = []
                for try await value in group { values.append(value) }
                return values
            }
        }
        await fulfillment(of: [started], timeout: 2)
        await gate.open()
        let values = try await callers.value
        XCTAssertEqual(values, Array(repeating: 1, count: 20))
        let count = await counter.count
        XCTAssertEqual(count, 1)
    }

    func testInvalidationRejectsLateResponseEvenAtSameTimestamp() async throws {
        let clock = MusicTestClock()
        let gate = MusicTestGate()
        let started = expectation(description: "old request")
        let repository = MusicRepository(client: musicTestClient(), now: { clock.now })
        let old = MusicQuery<Int>(key: .hotSearch) { _ in
            started.fulfill(); await gate.wait(); return 1
        }
        let pending = Task { try await repository.value(for: old) }
        await fulfillment(of: [started], timeout: 2)
        await repository.invalidate([.hotSearch])
        let fresh = try await repository.value(for: MusicQuery<Int>(key: .hotSearch) { _ in 2 })
        XCTAssertEqual(fresh.value, 2)
        await gate.open()
        do { _ = try await pending.value; XCTFail("Revoked request must not publish") } catch is CancellationError {} catch { XCTFail("\(error)") }
        let cached = await repository.cached(for: old)
        XCTAssertEqual(cached?.value, 2)
    }

    func testCancelledConsumerDoesNotCancelSharedCacheWork() async throws {
        let gate = MusicTestGate()
        let started = expectation(description: "request")
        let repository = MusicRepository(client: musicTestClient())
        let query = MusicQuery<Int>(key: .hotSearch) { _ in started.fulfill(); await gate.wait(); return 7 }
        let consumer = Task { try await repository.value(for: query) }
        await fulfillment(of: [started], timeout: 2)
        consumer.cancel()
        await gate.open()
        do { _ = try await consumer.value; XCTFail("Cancelled consumer should stop") } catch is CancellationError {} catch { XCTFail("\(error)") }
        let cached = await repository.cached(for: query)
        XCTAssertEqual(cached?.value, 7)
        await repository.reset()
        let cleared = await repository.cached(for: query)
        XCTAssertNil(cleared)
    }
}

// Deterministic clocks and gates; no wall-clock sleeps in cache/concurrency tests.
final class MusicTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_000)
    var now: Date { lock.withLock { date } }
    func advance(_ interval: TimeInterval) { lock.withLock { date.addTimeInterval(interval) } }
}
actor MusicTestCounter {
    private(set) var count = 0
    func next() -> Int { count += 1; return count }
}
actor MusicTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

func musicTestClient(server: MusicTestServer? = nil) -> MusicClient {
    MusicTestURLProtocol.server = server
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MusicTestURLProtocol.self]
    let keychain = MusicTestKeychain()
    try? keychain.setString("fixture-secret", for: "signSecret")
    return MusicClient(apiClient: APIClient(
        config: AppConfig(apiBaseURL: URL(string: "https://music.test")!, siteBaseURL: URL(string: "https://music.test")!),
        signer: AuthSigner(keychain: keychain), session: URLSession(configuration: configuration)
    ))
}
private final class MusicTestKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    func string(for key: String) throws -> String? { lock.withLock { values[key] } }
    func setString(_ value: String, for key: String) throws { lock.withLock { values[key] = value } }
    func remove(_ key: String) throws { lock.withLock { _ = values.removeValue(forKey: key) } }
}
actor MusicTestServer {
    private(set) var requests: [String] = []
    var body: [String: String] = [:]
    private var statuses: [String: Int] = [:]
    private var gate: MusicTestGate?
    private var observed: XCTestExpectation?
    private var heldPaths: Set<String>?
    func hold(_ gate: MusicTestGate?, observed: XCTestExpectation? = nil, paths: Set<String>? = nil) {
        self.gate = gate; self.observed = observed; self.heldPaths = paths
    }
    func set(_ path: String, _ body: String) { self.body[path] = body }
    func setStatus(_ path: String, _ status: Int) { statuses[path] = status }
    func respond(_ request: URLRequest) async -> (body: String, status: Int) {
        let key = "\(request.httpMethod ?? "GET") \(request.url!.path)"
        requests.append(key)
        let result = body[key] ?? Self.defaults[key] ?? #"{"code":200,"data":"ok"}"#
        let status = statuses[key] ?? 200
        if heldPaths == nil || heldPaths!.contains(key) {
            observed?.fulfill()
            if let gate { await gate.wait() }
        }
        return (result, status)
    }
    static let defaults: [String: String] = [
        "GET /user/music/search/hot": #"{"result":{"hots":[{"first":"热搜"}]}}"#,
        "GET /user/music/personalized": #"{"result":[]}"#,
        "GET /user/music/personalized/newsong": #"{"result":[]}"#,
        "GET /user/music/recommend/songs": #"{"data":{"dailySongs":[]}}"#,
        "GET /user/music/history": #"[{"id":91,"userId":1,"songId":7,"songName":"历史","artistName":"歌手","playTime":"2026-09-02"}]"#,
        "GET /user/music/history/count": "1",
        "GET /user/playlists": #"[{"id":1,"name":"歌单","songCount":1,"playMode":"random"},{"id":2,"name":"其它","songCount":0}]"#,
        "GET /user/playlists/1": #"{"id":1,"name":"歌单","songCount":1,"playMode":"random","songs":[{"id":91,"songId":7,"songName":"歌曲","artistName":"歌手"}]}"#,
        "GET /user/playlists/2": #"{"id":2,"name":"其它","songCount":0,"songs":[]}"#,
        "POST /user/playlists": #"{"id":3,"name":"新歌单","songCount":0}"#,
    ]
}
private final class MusicTestURLProtocol: URLProtocol {
    nonisolated(unsafe) static var server: MusicTestServer?
    private var responseTask: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let server = Self.server
        responseTask = Task {
            let responseBody = await server?.respond(request) ?? (body: "{}", status: 200)
            guard !Task.isCancelled else { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: responseBody.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(responseBody.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { responseTask?.cancel() }
}
