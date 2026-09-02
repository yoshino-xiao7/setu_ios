import Foundation
import XCTest
@testable import SetuIOSCore

final class MusicSearchRepositoryTests: XCTestCase {
    func testSearchKeyIncludesNormalizedKeywordOffsetLimitAndTenMinuteTTL() {
        let query = MusicQuery<MusicSearchResult>.search(keywords: " 周杰伦 \n", offset: 10, limit: 10)
        XCTAssertEqual(query.key, .search(keywords: "周杰伦", offset: 10, limit: 10))
        XCTAssertEqual(query.key.ttl, 600)
        XCTAssertNotEqual(query.key, MusicQuery<MusicSearchResult>.search(keywords: "周杰伦", offset: 0).key)
        XCTAssertNotEqual(query.key, MusicQuery<MusicSearchResult>.search(keywords: "周杰伦", offset: 10, limit: 20).key)
    }

    func testSearchTTLStaleValueForceAndPreciseInvalidation() async throws {
        let clock = MusicTestClock()
        let counter = MusicTestCounter()
        let repository = MusicRepository(client: musicTestClient(), now: { clock.now })
        let first = MusicQuery<Int>(key: .search(keywords: "A", offset: 0, limit: 10)) { _ in await counter.next() }
        let second = MusicQuery<Int>(key: .search(keywords: "A", offset: 10, limit: 10)) { _ in 10 }
        _ = try await repository.value(for: second)
        let initial = try await repository.value(for: first)
        XCTAssertEqual(initial.value, 1)
        clock.advance(599)
        let hit = try await repository.value(for: first)
        XCTAssertEqual(hit.value, 1)
        clock.advance(1)
        let stale = await repository.cached(for: first)
        XCTAssertEqual(stale?.value, 1)
        let fresh = try await repository.value(for: first)
        XCTAssertEqual(fresh.value, 2)
        let forced = try await repository.value(for: first, force: true)
        XCTAssertEqual(forced.value, 3)
        await repository.invalidate([first.key])
        let missing = await repository.cached(for: first)
        let preserved = await repository.cached(for: second)
        XCTAssertNil(missing)
        XCTAssertEqual(preserved?.value, 10)
    }

    func testCancellingOneSearchConsumerKeepsOtherConsumerAlive() async throws {
        let gate = MusicTestGate()
        let counter = MusicTestCounter()
        let started = expectation(description: "loader")
        let repository = MusicRepository(client: musicTestClient())
        let query = MusicQuery<Int>(key: .search(keywords: "A", offset: 0, limit: 10)) { _ in
            _ = await counter.next(); started.fulfill(); await gate.wait(); return 7
        }
        let first = Task { try await repository.value(for: query).value }
        await fulfillment(of: [started], timeout: 2)
        let second = Task { try await repository.value(for: query).value }
        let deadline = ContinuousClock.now + .seconds(2)
        while await repository.inFlightConsumerCount(for: query.key) < 2, ContinuousClock.now < deadline { await Task.yield() }
        let consumers = await repository.inFlightConsumerCount(for: query.key)
        XCTAssertEqual(consumers, 2)
        first.cancel()
        await gate.open()
        do { _ = try await first.value; XCTFail("Cancelled caller should stop") } catch is CancellationError {} catch { XCTFail("\(error)") }
        let value = try await second.value
        XCTAssertEqual(value, 7)
        let count = await counter.count
        XCTAssertEqual(count, 1)
    }
}
