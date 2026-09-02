import XCTest
import Foundation
@testable import SetuIOSCore
@testable import SetuIOSApp

@MainActor
final class MusicSearchSessionTests: XCTestCase {
    private func fixture() -> (MusicSearchSession, SearchBackend, MusicRepository, MusicTestClock, SearchDelay) {
        let backend = SearchBackend()
        let clock = MusicTestClock()
        let delay = SearchDelay()
        let repo = MusicRepository(client: musicTestClient(), now: { clock.now })
        let defaults = UserDefaults(suiteName: "music-search-tests-\(UUID())")!
        let session = MusicSearchSession(repository: repo, now: { clock.now }, sleep: { try await delay.sleep($0) },
                                         historyDefaults: defaults, makeQuery: { keyword, offset, limit in
            MusicQuery(key: .search(keywords: keyword, offset: offset, limit: limit)) { _ in
                try await backend.fetch(keyword, offset: offset, limit: limit)
            }
        })
        return (session, backend, repo, clock, delay)
    }

    private func search(_ session: MusicSearchSession, _ keyword: String) async {
        session.query = keyword
        await session.submit()
    }

    func testDebounceWaits400msAndRapidInputOnlyExecutesFinalChineseKeyword() async {
        let (s, backend, _, _, delay) = fixture()
        s.query = "周"
        await delay.waitForSchedules(1)
        await delay.advance(.milliseconds(100))
        s.query = "周杰"
        await delay.waitForSchedules(2)
        await delay.advance(.milliseconds(100))
        s.query = "周杰伦"
        await delay.waitForSchedules(3)
        await delay.advance(.milliseconds(399))
        let before = await backend.requests
        XCTAssertTrue(before.isEmpty)
        let requested = expectation(description: "debounced request")
        await backend.observe(requested)
        await delay.advance(.milliseconds(1))
        await fulfillment(of: [requested], timeout: 2)
        await s.submit() // joins the already executing request
        let requests = await backend.requests
        XCTAssertEqual(requests, [.search(keywords: "周杰伦", offset: 0, limit: 10)])
    }

    func testSubmitImmediatelyCancelsPendingDebounceAndDoesNotReplay() async {
        let (s, backend, _, _, delay) = fixture()
        s.query = "陈"
        await delay.waitForSchedules(1)
        await s.submit()
        await delay.advance(.seconds(1))
        await s.submit()
        let requests = await backend.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(s.executedKeyword, "陈")
    }

    func testSubmitAndDebounceShareInFlightRequest() async {
        let (s, backend, _, _, delay) = fixture()
        let gate = MusicTestGate()
        let started = expectation(description: "request")
        await backend.hold("A", gate: gate, started: started)
        s.query = "A"
        await delay.waitForSchedules(1)
        await delay.advance(.milliseconds(400))
        await fulfillment(of: [started], timeout: 2)
        let submit = Task { await s.submit() }
        await gate.open()
        await submit.value
        let requests = await backend.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testChangedInputCancelsOldRequestAndDiscardsCancellationIgnoringResponse() async {
        let (s, backend, _, _, _) = fixture()
        let gate = MusicTestGate()
        let started = expectation(description: "old request")
        let cancelled = expectation(description: "old loader cancelled")
        await backend.hold("A", gate: gate, started: started, cancelled: cancelled)
        let old = Task { await self.search(s, "A") }
        await fulfillment(of: [started], timeout: 2)
        await search(s, "B")
        await fulfillment(of: [cancelled], timeout: 2)
        await gate.open()
        await old.value
        XCTAssertEqual(s.resultKeyword, "B")
        XCTAssertEqual(s.pager.items.first?.title, "B 0")
        XCTAssertNil(s.pager.initialError)
    }

    func testColdSearchShowsSkeletonOnlyWithoutValue() async {
        let (s, backend, _, _, _) = fixture()
        let gate = MusicTestGate()
        let started = expectation(description: "request")
        await backend.hold("A", gate: gate, started: started)
        let task = Task { await self.search(s, "A") }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(s.showsSkeleton)
        await gate.open(); await task.value
        XCTAssertFalse(s.showsSkeleton)
    }

    func testNewKeywordKeepsOldRowsWhileSearching() async {
        let (s, backend, _, _, _) = fixture()
        await search(s, "A")
        let gate = MusicTestGate()
        let started = expectation(description: "request")
        await backend.hold("B", gate: gate, started: started)
        let task = Task { await self.search(s, "B") }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(s.pager.items.first?.title, "A 0")
        XCTAssertFalse(s.showsSkeleton)
        XCTAssertTrue(s.isSearching)
        await gate.open(); await task.value
        XCTAssertEqual(s.pager.items.first?.title, "B 0")
    }

    func testFirstPageDoesNotAutomaticallyFetchSecondPage() async {
        let (s, backend, _, _, _) = fixture()
        await search(s, "A")
        let requests = await backend.requests
        XCTAssertEqual(requests, [.search(keywords: "A", offset: 0, limit: 10)])
        XCTAssertEqual(s.pager.items.count, 10)
        XCTAssertTrue(s.pager.hasMore)
    }

    func testOnlyLastThreeRowsTriggerPagination() async {
        let (s, backend, _, _, _) = fixture()
        await search(s, "A")
        await s.loadMore(near: 6)
        XCTAssertEqual(s.pager.items.count, 10)
        await s.loadMore(near: 7)
        XCTAssertEqual(s.pager.items.count, 20)
        let requests = await backend.requests
        XCTAssertEqual(requests.last, .search(keywords: "A", offset: 10, limit: 10))
    }

    func testRepeatedNearEndCallbacksShareOnePage() async {
        let (s, backend, _, _, _) = fixture()
        await search(s, "A")
        let gate = MusicTestGate()
        let started = expectation(description: "page")
        await backend.hold("A", offset: 10, gate: gate, started: started)
        let first = Task { await s.loadMore(near: 7) }
        await fulfillment(of: [started], timeout: 2)
        await s.loadMore(near: 8)
        await s.loadMore(near: 9)
        await gate.open(); await first.value
        let requests = await backend.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(s.pager.items.count, 20)
    }

    func testPaginationAppendsAndDeduplicatesWithoutCorruptingOffset() async {
        let (s, backend, _, _, _) = fixture()
        await backend.duplicateSecondPage()
        await search(s, "A")
        await s.loadMore()
        XCTAssertEqual(s.pager.items.map(\.id), Array(0..<19))
        await s.loadMore()
        let requests = await backend.requests
        XCTAssertEqual(requests.last, .search(keywords: "A", offset: 20, limit: 10))
        XCTAssertEqual(Set(s.pager.items.map(\.id)).count, s.pager.items.count)
        XCTAssertFalse(s.pager.hasMore, "Raw offset reaches total even with duplicate IDs")
    }

    func testHasMoreFalseStopsRequests() async {
        let (s, backend, _, _, _) = fixture()
        await backend.setTotal(10)
        await search(s, "A")
        await s.loadMore()
        let requests = await backend.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertFalse(s.canLoadMore)
    }

    func testOldKeywordPageCannotAppendAfterQueryChanges() async {
        let (s, backend, _, _, _) = fixture()
        await search(s, "A")
        let gate = MusicTestGate()
        let started = expectation(description: "page")
        await backend.hold("A", offset: 10, gate: gate, started: started)
        let page = Task { await s.loadMore() }
        await fulfillment(of: [started], timeout: 2)
        await search(s, "B")
        await gate.open(); await page.value
        XCTAssertEqual(s.resultKeyword, "B")
        XCTAssertEqual(s.pager.items.count, 10)
        XCTAssertTrue(s.pager.items.allSatisfy { $0.title.hasPrefix("B") })
    }

    func testSameKeywordUsesSessionWithinTTLAndKeepsLoadedPages() async {
        let (s, backend, _, _, _) = fixture()
        await search(s, "A"); await s.loadMore()
        await s.submit()
        let requests = await backend.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(s.pager.items.count, 20)
    }

    func testDifferentKeywordsHaveIndependentRepositoryCache() async {
        let (s, backend, _, _, _) = fixture()
        await search(s, "A"); await search(s, "B"); await search(s, "A")
        let requests = await backend.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(s.pager.items.first?.title, "A 0")
    }

    func testCachedQueryRestoresWithin100Milliseconds() async {
        let (s, backend, _, _, _) = fixture()
        await search(s, "A"); await search(s, "B")
        let start = ContinuousClock.now
        await search(s, "A")
        let elapsed = start.duration(to: .now)
        XCTAssertLessThan(elapsed, .milliseconds(100))
        print("Search cached A-B-A restore: \(elapsed)")
        let requests = await backend.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testNavigationReactivationPreservesQuerySegmentAndPages() async {
        let (s, backend, _, _, _) = fixture()
        await s.activate(initialQuery: "A")
        await s.loadMore()
        s.selectedSegment = .albums
        await s.activate(initialQuery: nil)
        XCTAssertEqual(s.query, "A")
        XCTAssertEqual(s.selectedSegment, .albums)
        XCTAssertEqual(s.pager.items.count, 20)
        let requests = await backend.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testReappearingRouteDoesNotReapplyItsOriginalQuery() async {
        let (s, _, repo, _, _) = fixture()
        let route = UUID()
        await s.activate(initialQuery: "入口", routeID: route)
        await search(s, "后来输入")
        await s.activate(initialQuery: "入口", routeID: route)
        XCTAssertEqual(s.query, "后来输入")
        XCTAssertEqual(s.resultKeyword, "后来输入")
        let nextRoute = UUID()
        await s.activate(initialQuery: "入口", routeID: nextRoute)
        XCTAssertEqual(s.resultKeyword, "入口", "A new explicit search entry still replaces the previous query")
        s.reset(repository: repo)
        await s.activate(initialQuery: "入口", routeID: nextRoute)
        XCTAssertTrue(s.query.isEmpty, "A surviving old route must not replay its pre-reset entry query")
    }

    func testSegmentChangesDoNotSearchOrRecomputeAggregates() async {
        let (s, backend, _, _, _) = fixture()
        await search(s, "A")
        let revision = s.resultsRevision
        s.selectedSegment = .artists; s.selectedSegment = .albums; s.selectedSegment = .songs
        XCTAssertEqual(s.resultsRevision, revision)
        let requests = await backend.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testArtistAggregatesSplitMultipleArtistsAndCount() async {
        let (s, _, _, _, _) = fixture()
        await search(s, "A")
        XCTAssertEqual(s.artistItems, [.init(title: "Artist", count: 10), .init(title: "Guest", count: 10)])
    }

    func testAlbumAggregatesArePrecomputed() async {
        let (s, _, _, _, _) = fixture()
        await search(s, "A")
        XCTAssertEqual(s.albumItems, [.init(title: "Album", count: 10)])
        let revision = s.resultsRevision
        s.query = "AB"
        XCTAssertEqual(s.resultsRevision, revision, "Typing must not aggregate old results")
        s.query = ""
    }

    func testPageAppendUpdatesAggregatesOnce() async {
        let (s, _, _, _, _) = fixture()
        await search(s, "A")
        let revision = s.resultsRevision
        await s.loadMore()
        XCTAssertEqual(s.resultsRevision, revision + 1)
        XCTAssertEqual(s.artistItems.first?.count, 20)
        XCTAssertEqual(s.albumItems.first?.count, 20)
    }

    func testResetClearsSearchContextAndSelectedSegmentSynchronously() async {
        let (s, _, repo, _, _) = fixture()
        await search(s, "A"); s.selectedSegment = .albums
        s.reset(repository: repo)
        XCTAssertTrue(s.query.isEmpty)
        XCTAssertTrue(s.pager.items.isEmpty)
        XCTAssertTrue(s.artistItems.isEmpty)
        XCTAssertEqual(s.selectedSegment, .songs)
        XCTAssertFalse(s.isSearching)
    }

    func testStoreUserSwitchResetsItsOwnedSession() async {
        let store = MusicStore(client: musicTestClient(), userID: 1)
        let session = store.searchSession
        session.query = "周"
        session.selectedSegment = .artists
        store.reset(for: 2)
        XCTAssertTrue(store.searchSession === session)
        XCTAssertTrue(session.query.isEmpty)
        XCTAssertEqual(session.selectedSegment, .songs)
    }

    func testResetRejectsLateOldUserSearch() async {
        let (s, backend, _, _, _) = fixture()
        let gate = MusicTestGate()
        let started = expectation(description: "old account request")
        await backend.hold("A", gate: gate, started: started)
        let task = Task { await self.search(s, "A") }
        await fulfillment(of: [started], timeout: 2)
        s.reset(repository: MusicRepository(client: musicTestClient()))
        await gate.open(); await task.value
        XCTAssertTrue(s.pager.items.isEmpty)
        XCTAssertTrue(s.resultKeyword.isEmpty)
        XCTAssertFalse(s.isSearching)
    }

    func testEmptyQueryCancelsAndMakesNoRequest() async {
        let (s, backend, _, _, _) = fixture()
        await search(s, " \n  ")
        let requests = await backend.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertFalse(s.showsSkeleton)
    }

    func testColdSearchFailureShowsError() async {
        let (s, backend, _, _, _) = fixture()
        await backend.fail("A")
        await search(s, "A")
        XCTAssertNotNil(s.pager.initialError)
        XCTAssertFalse(s.showsSkeleton)
        XCTAssertTrue(s.pager.items.isEmpty)
    }

    func testSearchFailureRetainsOldResultsAndCanRetry() async {
        let (s, backend, _, _, _) = fixture()
        await search(s, "A")
        await backend.fail("B")
        await search(s, "B")
        XCTAssertEqual(s.pager.items.first?.title, "A 0")
        XCTAssertNotNil(s.pager.initialError)
        XCTAssertFalse(s.canLoadMore)
        await backend.fail(nil)
        await s.submit()
        XCTAssertEqual(s.pager.items.first?.title, "B 0")
        XCTAssertNil(s.pager.initialError)
    }

    func testPageFailureRetainsResultsAndRetriesSameOffset() async {
        let (s, backend, _, _, _) = fixture()
        await search(s, "A")
        await backend.fail("A")
        await s.loadMore()
        XCTAssertEqual(s.pager.items.count, 10)
        XCTAssertNotNil(s.pager.loadMoreError)
        await s.loadMore(near: 9)
        let failedRequests = await backend.requests
        XCTAssertEqual(failedRequests.count, 2, "Visibility updates must not loop automatic retries")
        await backend.fail(nil)
        await s.loadMore()
        XCTAssertEqual(s.pager.items.count, 20)
        let requests = await backend.requests
        XCTAssertEqual(requests.suffix(2), [.search(keywords: "A", offset: 10, limit: 10), .search(keywords: "A", offset: 10, limit: 10)])
    }

    func testExpiredSessionRevalidatesWithoutHidingRows() async {
        let (s, backend, _, clock, _) = fixture()
        await search(s, "A")
        clock.advance(601)
        let gate = MusicTestGate()
        let started = expectation(description: "revalidation")
        await backend.hold("A", gate: gate, started: started)
        let task = Task { await s.submit() }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(s.hasResults)
        XCTAssertFalse(s.showsSkeleton)
        await gate.open(); await task.value
        let requests = await backend.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testHistoryTrimDeduplicateRemoveAndClear() async {
        let (s, _, _, _, _) = fixture()
        await search(s, " A "); await search(s, "B"); await search(s, "A")
        XCTAssertEqual(s.history, ["A", "B"])
        s.removeHistory("B")
        XCTAssertEqual(s.history, ["A"])
        s.clearHistory()
        XCTAssertTrue(s.history.isEmpty)
        await s.submit()
        XCTAssertEqual(s.history, ["A"], "An explicit cached search still records history after clearing it")
    }

    func testRowModelPreservesOriginalSongAndNormalizedDisplayFields() {
        let song = MusicSong(id: 1, name: "Song", artists: [.init(id: 2, name: " Artist ")], album: .init(id: 3, name: "Album", picUrl: "http://example.com/a.jpg"), mv: 9)
        let model = MusicSongRowModel(song: song)
        XCTAssertEqual(model.id, song.id)
        XCTAssertEqual(model.artist, "Artist")
        XCTAssertEqual(model.album, "Album")
        XCTAssertTrue(model.hasMV)
        XCTAssertEqual(model.coverURLString, "https://example.com/a.jpg")
        XCTAssertEqual(model.song.mv, 9)
    }
}

private actor SearchBackend {
    private(set) var requests: [MusicCacheKey] = []
    private var total = 30
    private var duplicate = false
    private var failedKeyword: String?
    private var holdKey: MusicCacheKey?
    private var gate: MusicTestGate?
    private var started: XCTestExpectation?
    private var cancelled: XCTestExpectation?
    private var observed: XCTestExpectation?
    func setTotal(_ total: Int) { self.total = total }
    func duplicateSecondPage() { duplicate = true }
    func fail(_ keyword: String?) { failedKeyword = keyword }
    func observe(_ expectation: XCTestExpectation) { observed = expectation }
    func hold(_ keyword: String, offset: Int = 0, gate: MusicTestGate, started: XCTestExpectation, cancelled: XCTestExpectation? = nil) {
        holdKey = .search(keywords: keyword, offset: offset, limit: 10)
        self.gate = gate; self.started = started; self.cancelled = cancelled
    }
    func fetch(_ keyword: String, offset: Int, limit: Int) async throws -> MusicSearchResult {
        let key = MusicCacheKey.search(keywords: keyword, offset: offset, limit: limit)
        requests.append(key)
        observed?.fulfill(); observed = nil
        if key == holdKey, let gate {
            started?.fulfill()
            let cancelled = cancelled
            await withTaskCancellationHandler { await gate.wait() } onCancel: { cancelled?.fulfill() }
            // Intentionally ignore cancellation to exercise generation and repository tickets.
        }
        if keyword == failedKeyword { throw URLError(.notConnectedToInternet) }
        let ids = offset >= total ? [] : Array(offset..<min(offset + limit, total))
        let songs: [[String: Any]] = ids.map { number in
            let id = duplicate && offset == 10 ? number - 1 : number
            return ["id": id, "name": "\(keyword) \(id)", "artists": [["id": 1, "name": "Artist"], ["id": 2, "name": "Guest"]], "album": ["id": 3, "name": "Album"]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["result": ["songs": songs, "songCount": total]])
        return try JSONDecoder().decode(MusicSearchResult.self, from: data)
    }
}

/// Logical time, cancellation-aware continuations, and explicit registration barriers; no sleeps.
private actor SearchDelay {
    private var now: Duration = .zero
    private var schedules = 0
    private var pending: [UUID: (Duration, CheckedContinuation<Void, Error>)] = [:]
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = (now + duration, continuation)
                schedules += 1
                let ready = observers.filter { $0.0 <= schedules }
                observers.removeAll { $0.0 <= schedules }
                for observer in ready { observer.1.resume() }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    func waitForSchedules(_ count: Int) async {
        if schedules >= count { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }
    func advance(_ duration: Duration) {
        now += duration
        let ready = pending.filter { $0.value.0 <= now }
        for (id, waiter) in ready { pending[id] = nil; waiter.1.resume() }
    }
    private func cancel(_ id: UUID) { pending.removeValue(forKey: id)?.1.resume(throwing: CancellationError()) }
}
