import Foundation
import XCTest
@testable import SetuIOSCore

@MainActor
final class CloudVideoUploadStoreTests: XCTestCase {
    func testSerialQueueKeepsLaterFilesWaitingAndAcceptsContinueAdd() async throws {
        let tus = FakeTUSClient()
        tus.holdFirst = true
        let sessions = FakeUploadSessions()
        let store = makeStore(sessions: sessions, tus: tus)

        store.enqueue([draft("one"), draft("two")])
        await waitUntil { tus.started == 1 }

        XCTAssertEqual(sessions.createdTitles, ["one"])
        XCTAssertEqual(store.queuedCount, 2)
        XCTAssertTrue(store.summary.contains("排队 1 个"))

        store.enqueue([draft("three")])
        await waitUntil { store.items.count == 3 }

        XCTAssertEqual(tus.started, 1)
        XCTAssertEqual(sessions.createdTitles.count, 1)

        tus.release()
        await waitUntil { !store.busy }

        XCTAssertEqual(sessions.createdTitles, ["one", "two", "three"])
        XCTAssertEqual(sessions.synced, [1, 2, 3])
        XCTAssertEqual(tus.sessionIDs, [1, 2, 3])
        XCTAssertTrue(store.items.isEmpty)
    }

    func testRetryReusesTheSameUploadSession() async throws {
        let tus = FakeTUSClient()
        tus.failRemaining = 1
        let sessions = FakeUploadSessions()
        let store = makeStore(sessions: sessions, tus: tus)

        store.enqueue([draft("one"), draft("two")])
        await waitUntil { !store.busy }

        XCTAssertEqual(sessions.createdTitles, ["one", "two"])
        XCTAssertEqual(tus.sessionIDs, [1, 1, 2])
        XCTAssertEqual(sessions.synced, [1, 2])
        XCTAssertTrue(store.items.isEmpty)
    }

    func testRestoreDoesNotCreateASecondSessionAndRefreshesTicket() async throws {
        let file = try makeTempVideo()
        let snapshot = CloudVideoUploadSnapshot(
            wifiOnly: true,
            items: [
                CloudVideoUploadItem(
                    id: "restored",
                    title: "过夜",
                    rating: "all_ages",
                    fileName: "overnight.mp4",
                    fileURL: file,
                    byteCount: 12,
                    phase: .uploading,
                    session: CloudVideoUploadSession(
                        id: 44,
                        bunnyVideoId: "guid-44",
                        libraryId: 99,
                        tusEndpoint: "https://video.bunnycdn.com/tusupload",
                        authorizationSignature: "sig",
                        authorizationExpire: 1,
                        title: "过夜",
                        status: "uploading"
                    )
                )
            ]
        )
        let persistence = CloudVideoUploadMemoryPersistence(snapshot: snapshot)
        let sessions = FakeUploadSessions()
        let tus = FakeTUSClient()
        let store = makeStore(sessions: sessions, tus: tus, persistence: persistence)
        store.startIfNeeded()
        await waitUntil { !store.busy }

        XCTAssertTrue(sessions.createdTitles.isEmpty)
        XCTAssertEqual(sessions.refreshIDs, [44])
        XCTAssertEqual(tus.sessionIDs, [44])
        XCTAssertEqual(sessions.synced, [44])
        XCTAssertTrue(store.items.isEmpty)
    }

    func testWifiOnlyPausesThenResumesOnWifi() async throws {
        let network = CloudVideoUploadManualNetwork(isSatisfied: true, isWifi: false)
        let tus = FakeTUSClient()
        let sessions = FakeUploadSessions()
        let store = makeStore(sessions: sessions, tus: tus, network: network)
        store.wifiOnly = true
        store.enqueue([draft("one")])
        await waitUntil { store.items.first?.phase == .waitingForWifi }

        XCTAssertEqual(tus.started, 0)
        XCTAssertEqual(store.pauseReason, .wifi)

        network.update(isSatisfied: true, isWifi: true)
        await waitUntil { !store.busy }
        XCTAssertEqual(sessions.createdTitles, ["one"])
        XCTAssertTrue(store.items.isEmpty)
    }

    func testExpiredSessionPausesQueueWithoutDroppingIt() async throws {
        let sessions = FakeUploadSessions()
        sessions.failCreateWith = APIError.httpStatus(401, message: "登录已过期")
        let store = makeStore(sessions: sessions, tus: FakeTUSClient())
        store.enqueue([draft("one"), draft("two")])
        await waitUntil { store.pauseReason == .session }

        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.pauseReason, .session)
        XCTAssertFalse(store.items.contains(where: { $0.phase == .failed }))
    }

    func testExhaustedAttemptsSkipToTheNextFile() async throws {
        let tus = FakeTUSClient()
        tus.failRemaining = 100
        let sessions = FakeUploadSessions()
        let store = makeStore(
            sessions: sessions,
            tus: tus,
            configuration: CloudVideoUploadConfiguration(maxAttempts: 2, stallTimeout: 180, retryPause: 0, ticketRefreshLead: 600)
        )
        store.enqueue([draft("one"), draft("two")])
        await waitUntil { store.items.filter { $0.phase == .failed }.count == 2 }

        XCTAssertEqual(store.items.map(\.title), ["one", "two"])
        XCTAssertEqual(store.items.map(\.phase), [.failed, .failed])
        XCTAssertEqual(sessions.createdTitles, ["one", "two"])
    }

    private func makeStore(
        sessions: FakeUploadSessions,
        tus: FakeTUSClient,
        persistence: CloudVideoUploadMemoryPersistence = CloudVideoUploadMemoryPersistence(),
        network: CloudVideoUploadManualNetwork = CloudVideoUploadManualNetwork(),
        configuration: CloudVideoUploadConfiguration = .tests
    ) -> CloudVideoUploadStore {
        CloudVideoUploadStore(
            sessions: sessions,
            inbox: CloudVideoPassthroughInbox(),
            tus: tus,
            persistence: persistence,
            network: network,
            configuration: configuration,
            sleep: { _ in }
        )
    }

    private func draft(_ title: String) -> CloudVideoUploadDraft {
        CloudVideoUploadDraft(
            title: title,
            fileName: "\(title).mp4",
            sourceURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(title)-\(UUID().uuidString).mp4"),
            byteCount: 12
        )
    }

    private func makeTempVideo() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try Data("video".utf8).write(to: url)
        return url
    }

    private func waitUntil(_ probe: @escaping () -> Bool) async {
        for _ in 0..<200 {
            if probe() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("timed out waiting for upload store")
    }
}

private final class FakeTUSClient: CloudVideoTUSUploading, @unchecked Sendable {
    private let lock = NSLock()
    var started = 0
    var sessionIDs: [Int] = []
    var failRemaining = 0
    var holdFirst = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func upload(
        fileURL: URL,
        session: CloudVideoUploadSession,
        existingUploadURL: URL?,
        chunkSize: Int,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        let shouldHold: Bool = lock.withLock {
            started += 1
            sessionIDs.append(session.id)
            return holdFirst && started == 1
        }
        onProgress(1, 10)
        if shouldHold {
            await withCheckedContinuation { continuation in
                lock.withLock { waiters.append(continuation) }
            }
        }
        let failing: Bool = lock.withLock {
            if failRemaining > 0 {
                failRemaining -= 1
                return true
            }
            return false
        }
        if failing {
            throw URLError(.timedOut)
        }
        onProgress(10, 10)
        return URL(string: "https://video.bunnycdn.com/tusupload/\(session.bunnyVideoId)")!
    }

    func release() {
        let pending = lock.withLock {
            let values = waiters
            waiters = []
            return values
        }
        pending.forEach { $0.resume() }
    }
}

private final class FakeUploadSessions: CloudVideoUploadSessioning, @unchecked Sendable {
    var createdTitles: [String] = []
    var refreshIDs: [Int] = []
    var synced: [Int] = []
    var deleted: [Int] = []
    var failCreateWith: Error?
    private var nextID = 1

    func createUploadSession(title: String) async throws -> CloudVideoUploadSession {
        if let failCreateWith { throw failCreateWith }
        createdTitles.append(title)
        let id = nextID
        nextID += 1
        return makeSession(id: id, title: title)
    }

    func refreshTusTicket(id: Int) async throws -> CloudVideoUploadSession {
        refreshIDs.append(id)
        return makeSession(id: id, title: "过夜", expire: 9_999_999_999)
    }

    func syncAdminCloudVideo(id: Int) async throws -> AdminCloudVideoItem {
        synced.append(id)
        return try JSONDecoder().decode(
            AdminCloudVideoItem.self,
            from: Data(#"{"id":\#(id),"title":"t","status":"encoding","visibility":"draft","rating":"all_ages"}"#.utf8)
        )
    }

    func updateAdminCloudVideo(id: Int, update: AdminCloudVideoUpdate) async throws -> AdminCloudVideoItem {
        try await syncAdminCloudVideo(id: id)
    }

    func deleteAdminCloudVideo(id: Int) async throws {
        deleted.append(id)
    }

    private func makeSession(id: Int, title: String, expire: Int64 = 9_999_999_999) -> CloudVideoUploadSession {
        CloudVideoUploadSession(
            id: id,
            bunnyVideoId: "guid-\(id)",
            libraryId: 99,
            tusEndpoint: "https://video.bunnycdn.com/tusupload",
            authorizationSignature: "sig-\(id)",
            authorizationExpire: expire,
            title: title,
            status: "uploading"
        )
    }
}
