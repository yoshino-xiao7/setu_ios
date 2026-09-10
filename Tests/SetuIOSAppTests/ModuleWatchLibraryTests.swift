import XCTest
@testable import SetuIOSCore

@MainActor
final class ModuleWatchHistoryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var owner = "user-7"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "module-watch-\(UUID().uuidString)")
    }

    override func tearDown() {
        if let suite = defaults.persistentDomain(forName: "") { _ = suite }
        super.tearDown()
    }

    func testRecordsKeepTheNewestCopyAndCapAt100() {
        let store = ModuleWatchHistoryStore(defaults: defaults, ownerID: { self.owner })
        for index in 1...120 {
            store.record(ModuleWatchRecord(
                module: .jm,
                externalId: "album-\(index)",
                title: "本子 \(index)",
                viewedAt: Date(timeIntervalSince1970: TimeInterval(index))
            ))
        }
        store.record(ModuleWatchRecord(module: .jm, externalId: "album-120", title: "本子 120 续看", viewedAt: Date(timeIntervalSince1970: 200)))
        store.record(ModuleWatchRecord(module: .asmr, externalId: "41001", title: "第一夜"))

        let jm = store.records(module: .jm)
        XCTAssertEqual(jm.count, ModuleWatchHistoryStore.capacity)
        XCTAssertEqual(jm.first?.externalId, "album-120")
        XCTAssertEqual(jm.first?.title, "本子 120 续看")
        XCTAssertEqual(jm.map(\.externalId).filter { $0 == "album-120" }.count, 1)
        XCTAssertFalse(jm.contains(where: { $0.externalId == "album-1" }))
        XCTAssertEqual(store.records(module: .asmr).map(\.externalId), ["41001"])
    }

    func testHistoryIsIsolatedPerAccount() {
        let store = ModuleWatchHistoryStore(defaults: defaults, ownerID: { self.owner })
        store.record(ModuleWatchRecord(module: .jm, externalId: "88001", title: "用户七"))
        owner = "user-8"
        XCTAssertTrue(store.records(module: .jm).isEmpty)
        store.record(ModuleWatchRecord(module: .jm, externalId: "88002", title: "用户八"))
        owner = "user-7"
        XCTAssertEqual(store.records(module: .jm).map(\.externalId), ["88001"])
    }
}

@MainActor
final class JmReadingProgressStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "jm-progress-\(UUID().uuidString)")
    }

    func testSavesTheLatestChapterAndPage() {
        let store = JmReadingProgressStore(defaults: defaults, ownerID: { "7" })
        store.save(JmReadingProgress(albumID: "88001", chapterID: "1", pageIndex: 2, pageCount: 40, chapterTitle: "第1话"))
        store.save(JmReadingProgress(albumID: "88001", chapterID: "2", pageIndex: 7, pageCount: 44, chapterTitle: "第2话"))
        let progress = store.progress(albumID: "88001")
        XCTAssertEqual(progress?.chapterID, "2")
        XCTAssertEqual(progress?.pageIndex, 7)
        XCTAssertEqual(progress?.displayText, "第2话 · 8/44")
        XCTAssertEqual(progress?.pageProgressText, "8/44")
    }

    func testFavoriteSnapshotKeepsNewerProgress() {
        let store = JmReadingProgressStore(defaults: defaults, ownerID: { "7" })
        let local = JmReadingProgress(
            albumID: "88001",
            chapterID: "1",
            pageIndex: 3,
            pageCount: 20,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        store.save(local)
        let older = JmReadingProgress(
            albumID: "88001",
            chapterID: "9",
            pageIndex: 0,
            pageCount: 10,
            updatedAt: Date(timeIntervalSince1970: 50)
        )
        store.mergeFromFavorite(albumID: "88001", extraJSON: older.extraJSONString)
        XCTAssertEqual(store.progress(albumID: "88001")?.chapterID, "1")

        let newer = JmReadingProgress(
            albumID: "88001",
            chapterID: "3",
            pageIndex: 1,
            pageCount: 12,
            chapterTitle: "第3话",
            updatedAt: Date(timeIntervalSince1970: 400)
        )
        store.mergeFromFavorite(albumID: "88001", extraJSON: newer.extraJSONString)
        XCTAssertEqual(store.progress(albumID: "88001")?.chapterID, "3")
        XCTAssertEqual(JmReadingProgress.fromExtraJSON(newer.extraJSONString)?.pageIndex, 1)
    }
}
