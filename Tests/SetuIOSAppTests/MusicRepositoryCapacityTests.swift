import XCTest
@testable import SetuIOSCore

final class MusicRepositoryCapacityTests: XCTestCase {
    func testBoundedSearchCacheRetainsRecentlyAccessedData() async throws {
        let repository = MusicRepository(client: musicTestClient(), capacity: 3)
        let hot = query(0)
        _ = try await repository.value(for: hot)
        for index in 1...100 {
            _ = await repository.cached(for: hot)
            _ = try await repository.value(for: query(index))
            let count = await repository.cachedEntryCount()
            XCTAssertLessThanOrEqual(count, 3)
        }
        let hit = await repository.cached(for: hot)
        XCTAssertEqual(hit?.value, 0)
        let evicted = await repository.cached(for: query(1))
        XCTAssertNil(evicted)
    }

    func testExpiryIsEvictedBeforeFreshDataWithoutExtendingTTLOnRead() async throws {
        let clock = MusicTestClock()
        let repository = MusicRepository(client: musicTestClient(), now: { clock.now }, capacity: 2)
        _ = try await repository.value(for: query(0))
        clock.advance(300)
        _ = try await repository.value(for: query(1))
        clock.advance(300)
        let stale = await repository.cached(for: query(0))
        XCTAssertEqual(stale?.value, 0, "SWR keeps stale data until capacity pressure")
        XCTAssertEqual(stale?.fetchedAt, Date(timeIntervalSince1970: 1_000))
        _ = try await repository.value(for: query(2))
        let expired = await repository.cached(for: query(0))
        let fresh = await repository.cached(for: query(1))
        XCTAssertNil(expired)
        XCTAssertEqual(fresh?.value, 1)
    }

    func testDefaultCapacityIs128AndResetRemovesAllEntries() async throws {
        let repository = MusicRepository(client: musicTestClient())
        for index in 0..<300 { _ = try await repository.value(for: query(index)) }
        let count = await repository.cachedEntryCount()
        XCTAssertEqual(count, 128)
        print("MusicRepository: 300 distinct queries, \(count) retained entries")
        await repository.reset()
        let resetCount = await repository.cachedEntryCount()
        XCTAssertEqual(resetCount, 0)
    }

    func testEvictionDoesNotCancelSharedFlightAndInvalidationStillRevokesIt() async throws {
        let repository = MusicRepository(client: musicTestClient(), capacity: 1)
        let gate = MusicTestGate()
        let counter = MusicTestCounter()
        let started = expectation(description: "shared request")
        let pendingQuery = MusicQuery<Int>(key: .search(keywords: "pending", offset: 0, limit: 10)) { _ in
            _ = await counter.next(); started.fulfill(); await gate.wait(); return 42
        }
        let first = Task { try await repository.value(for: pendingQuery).value }
        await fulfillment(of: [started], timeout: 2)
        let second = Task { try await repository.value(for: pendingQuery).value }
        let deadline = ContinuousClock.now + .seconds(2)
        while await repository.inFlightConsumerCount(for: pendingQuery.key) < 2, ContinuousClock.now < deadline { await Task.yield() }
        let consumers = await repository.inFlightConsumerCount(for: pendingQuery.key)
        XCTAssertEqual(consumers, 2)
        for index in 0..<10 { _ = try await repository.value(for: query(index)) }
        await gate.open()
        async let churn: Void = churnCache(repository)
        let values = try await [first.value, second.value]
        try await churn
        XCTAssertEqual(values, [42, 42])
        let calls = await counter.count
        XCTAssertEqual(calls, 1)
        await repository.invalidate([query(99).key])
        let removed = await repository.cached(for: query(99))
        XCTAssertNil(removed)
        // Existing repository tests also hold a flight through invalidate/reset and reject its late result.
    }

    private func churnCache(_ repository: MusicRepository) async throws {
        for index in 10..<100 { _ = try await repository.value(for: query(index)) }
    }
    private func query(_ index: Int) -> MusicQuery<Int> {
        MusicQuery(key: .search(keywords: "query-\(index)", offset: 0, limit: 10)) { _ in index }
    }
}
