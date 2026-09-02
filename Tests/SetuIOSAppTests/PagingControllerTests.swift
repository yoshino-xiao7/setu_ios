import XCTest
import SetuIOSCore
@testable import SetuIOSApp

@MainActor
final class PagingControllerTests: XCTestCase {

    private struct Row: Identifiable, Equatable {
        let id: Int
    }

    private func makeController() -> PagingController<Row> {
        PagingController<Row>(pageSize: 2)
    }

    func testLoadFirstPagePopulatesItemsAndTotal() async {
        let pager = makeController()
        await pager.loadFirstPage { _ in .init(items: [Row(id: 1), Row(id: 2)], total: 3) }

        XCTAssertEqual(pager.items, [Row(id: 1), Row(id: 2)])
        XCTAssertEqual(pager.total, 3)
        XCTAssertTrue(pager.hasMore)
        XCTAssertNil(pager.initialError)
        XCTAssertEqual(pager.phase, .idle)
    }

    func testLoadMoreAppendsDeduplicatesAndAdvancesPage() async {
        let pager = makeController()
        await pager.loadFirstPage { _ in .init(items: [Row(id: 1)], total: 3) }

        await pager.loadMore { _ in .init(items: [Row(id: 1), Row(id: 2)], total: 3) }
        XCTAssertEqual(pager.items.map(\.id), [1, 2], "重复项应被过滤")

        await pager.loadMore { _ in .init(items: [Row(id: 3)], total: 3) }
        XCTAssertEqual(pager.items.map(\.id), [1, 2, 3])
        XCTAssertFalse(pager.hasMore)
    }

    func testLoadMoreIsRejectedWhileLoadingAndWhenExhausted() async {
        let pager = makeController()
        await pager.loadFirstPage { _ in .init(items: [Row(id: 1)], total: 1) }

        // 已加载完毕：不应再发起请求
        var fetchCount = 0
        await pager.loadMore { _ in
            fetchCount += 1
            return .init(items: [], total: 1)
        }
        XCTAssertEqual(fetchCount, 0)
    }

    func testLoadMoreFailureKeepsLoadedDataAndRecordsError() async {
        let pager = makeController()
        await pager.loadFirstPage { _ in .init(items: [Row(id: 1)], total: 3) }

        struct FetchFailed: Error {}
        await pager.loadMore { _ in throw FetchFailed() }

        XCTAssertEqual(pager.items.map(\.id), [1], "失败时保留已加载数据")
        XCTAssertNotNil(pager.loadMoreError)
        XCTAssertEqual(pager.phase, .idle)
    }

    func testInitialFailureRecordsErrorAndKeepsExistingItems() async {
        let pager = makeController()
        await pager.loadFirstPage { _ in .init(items: [Row(id: 1)], total: 1) }

        struct FetchFailed: Error {}
        await pager.loadFirstPage { _ in throw FetchFailed() }

        XCTAssertEqual(pager.items.map(\.id), [1])
        XCTAssertNotNil(pager.initialError)
    }

    func testStaleLoadMoreAfterRefreshIsIgnored() async {
        let pager = makeController()
        await pager.loadFirstPage { _ in .init(items: [Row(id: 7)], total: 10) }

        // 进行中的慢 loadMore 被随后的刷新（loadFirstPage）作废：
        // 慢响应返回时 generation 已过期，不允许污染新列表
        let slowLoadMore = Task { await pager.loadMore { _ in
            try? await Task.sleep(nanoseconds: 200_000_000)
            return PagingController<Row>.PageResult(items: [Row(id: 99)], total: 10)
        } }
        try? await Task.sleep(nanoseconds: 50_000_000)
        await pager.loadFirstPage { _ in .init(items: [Row(id: 1)], total: 10) }
        await slowLoadMore.value

        XCTAssertEqual(pager.items.map(\.id), [1])
        XCTAssertFalse(pager.items.contains(Row(id: 99)))
    }
    func testDuplicatesWithinPageAndEmptyLastPage() async {
        let pager = makeController()
        await pager.loadFirstPage { _ in .init(items: [Row(id: 1), Row(id: 1)], total: 9) }
        XCTAssertEqual(pager.items.map(\.id), [1])
        await pager.loadMore { _ in .init(items: [Row(id: 2), Row(id: 2)], total: 9) }
        XCTAssertEqual(pager.items.map(\.id), [1, 2])
        await pager.loadMore { _ in .init(items: [], total: 9) }
        XCTAssertFalse(pager.hasMore, "服务端总数漂移时空末页仍应终止分页")
    }

    func testUnauthorizedKeepsSignInActionDespiteCustomMessage() async {
        let pager = makeController()
        await pager.loadFirstPage({ _ in throw APIError.httpStatus(401, message: nil, requestID: nil, traceID: nil) }, onError: { _ in "稍后再试" })
        XCTAssertEqual(pager.initialError?.action, .signIn)
    }

    func testFilterChangeDiscardsPendingFirstPage() async {
        let pager = makeController()
        var resume: CheckedContinuation<PagingController<Row>.PageResult, Never>?
        let old = Task { await pager.loadFirstPage { _ in
            await withCheckedContinuation { resume = $0 }
        } }
        while resume == nil { await Task.yield() }
        await pager.loadFirstPage(clearExisting: true) { _ in .init(items: [Row(id: 2)], total: 1) }
        resume?.resume(returning: .init(items: [Row(id: 1)], total: 100))
        await old.value
        XCTAssertEqual(pager.items.map(\.id), [2])
        XCTAssertEqual(pager.total, 1)
        XCTAssertEqual(pager.phase, .idle)
    }

    func testCancellationKeepsRowsAndLeavesIdleWithoutError() async {
        let pager = makeController()
        await pager.loadFirstPage { _ in .init(items: [Row(id: 1)], total: 10) }
        let gate = MusicTestGate()
        let started = expectation(description: "page requested")
        let pending = Task { await pager.loadMore { _ in
            started.fulfill()
            await gate.wait()
            return .init(items: [Row(id: 2)], total: 10)
        } }
        await fulfillment(of: [started], timeout: 2)
        pending.cancel()
        await gate.open(); await pending.value
        XCTAssertEqual(pager.items.map(\.id), [1])
        XCTAssertNil(pager.loadMoreError)
        XCTAssertEqual(pager.phase, .idle)
    }

    func testOffsetExhaustionOverridesUniqueItemCount() async {
        let pager = makeController()
        await pager.loadFirstPage { _ in .init(items: [Row(id: 1)], total: 4) }
        await pager.loadMore { _ in .init(items: [Row(id: 1), Row(id: 2)], total: 4, hasMore: false) }
        XCTAssertEqual(pager.items.map(\.id), [1, 2])
        XCTAssertFalse(pager.hasMore)
    }

}
