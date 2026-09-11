import XCTest
@testable import SetuIOSCore

final class JmPagePrefetchWindowTests: XCTestCase {
    func testLoadsTheCurrentPageBeforeUpcomingPages() {
        XCTAssertEqual(JmPagePrefetchWindow.indices(current: 0, count: 20), [0, 1, 2, 3])
        XCTAssertEqual(JmPagePrefetchWindow.indices(current: 5, count: 10), [5, 6, 7, 8, 4])
        XCTAssertEqual(JmPagePrefetchWindow.indices(current: 9, count: 10), [9, 8])
        XCTAssertEqual(JmPagePrefetchWindow.indices(current: 0, count: 0), [])
    }
}

@MainActor
final class JmPageImageLoaderTests: XCTestCase {
    func testPrefetchFetchesNearbyPagesWithoutReadingTheWholeChapter() async {
        let pages = (0..<20).map(Self.page)
        let recorder = FetchRecorder()
        let loader = JmPageImageLoader { page in
            await recorder.append(page.id)
            return Self.png
        }

        loader.prefetch(pages: pages, currentIndex: 0)
        let ids = await recorder.waitUntil { Set($0) == Set(["p-0", "p-1", "p-2", "p-3"]) }

        XCTAssertEqual(ids.first, "p-0")
        XCTAssertEqual(Set(ids), Set(["p-0", "p-1", "p-2", "p-3"]))
        XCTAssertFalse(ids.contains("p-19"))
    }

    func testMovingThePrefetchWindowDoesNotTreatUpcomingPagesAsRead() async {
        let pages = (0..<12).map(Self.page)
        let recorder = FetchRecorder()
        let loader = JmPageImageLoader { page in
            await recorder.append(page.id)
            try await Task.sleep(for: .milliseconds(5))
            return Self.png
        }
        var visibleIndex = 2
        loader.prefetch(pages: pages, currentIndex: visibleIndex)
        _ = await recorder.waitUntil { Set($0).isSuperset(of: ["p-2", "p-3", "p-4", "p-5"]) }
        XCTAssertEqual(visibleIndex, 2)

        loader.prefetch(pages: pages, currentIndex: 6)
        let ids = await recorder.waitUntil { $0.contains("p-6") && $0.contains("p-7") }
        XCTAssertEqual(visibleIndex, 2)
        XCTAssertTrue(ids.contains("p-6"))
        XCTAssertTrue(ids.contains("p-7"))
        XCTAssertFalse(ids.contains("p-11"))
    }

    private static func page(_ index: Int) -> JmPageImage {
        JmPageImage(
            id: "p-\(index)",
            url: URL(string: "https://cdn.example/photo/\(index).jpg")!,
            albumID: 1,
            scrambleID: 220_980
        )
    }

    private static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
}

private actor FetchRecorder {
    private(set) var ids: [String] = []

    func append(_ id: String) {
        ids.append(id)
    }

    func waitUntil(
        timeout: Duration = .milliseconds(800),
        predicate: ([String]) -> Bool
    ) async -> [String] {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if predicate(ids) { return ids }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return ids
    }
}
