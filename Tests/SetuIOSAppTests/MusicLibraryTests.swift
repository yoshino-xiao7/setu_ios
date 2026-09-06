import Foundation
import XCTest
@testable import SetuIOSCore
@testable import SetuIOSApp

@MainActor
final class MusicLibraryTests: XCTestCase {
    override func tearDown() { MusicV2URLProtocol.handler = nil; super.tearDown() }

    func testLikedTrackMetadataIsHydratedAndWarmReadIsCached() async {
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            if request.url?.path.hasSuffix("/tracks") == true {
                return .init(body: Data("{\"items\":[\(MusicV2Fixtures.track)],\"missingIds\":[]}".utf8))
            }
            return .init(body: Self.page(ids: ["1"]))
        }
        let store = MusicStore(client: musicTestClient(), userID: 1)
        await store.loadLikedTracks(client: makeMusicV2Client())
        XCTAssertNotNil(store.likedTracks.value?.items.first?.track)
        await store.loadLikedTracks(client: makeMusicV2Client())
        XCTAssertEqual(capture.requests.count, 2)
    }

    func testHistoryDateUsesLocalDayAndReadableTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let now = ISO8601DateFormatter().date(from: "2026-09-06T02:00:00Z")!
        XCTAssertEqual(MusicHistoryDateLabel.text("2026-09-06T01:05:00.123Z", now: now, calendar: calendar), "今天 09:05")
        XCTAssertEqual(MusicHistoryDateLabel.text("2026-09-04T23:30:00Z", now: now, calendar: calendar), "昨天 07:30")
        XCTAssertEqual(MusicHistoryDateLabel.text("bad", now: now, calendar: calendar), "时间未知")
    }

    func testCanonicalPlaylistRequestPreservesOpaqueIdentity() throws {
        let request = AddSongToPlaylistRequest(trackId: .init(rawValue: "netease:track:opaque%2Fpart"), songName: "Song", artistName: "Artist", albumName: nil, coverUrl: nil, duration: 1)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(json["trackId"] as? String, "netease:track:opaque%2Fpart")
        XCTAssertNil(json["songId"])
        XCTAssertNil(PlaylistSong(local: request))
    }

    func testPaginationNullSnapshotsAndUnknownAbsence() async throws {
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            let second = request.url?.query?.contains("offset=20") == true
            return .init(body: Self.page(ids: [second ? "2" : "1"], next: second ? nil : 20, total: 2))
        }
        let store = MusicStore(client: musicTestClient(), userID: 1), client = makeMusicV2Client()
        await store.loadLikedTracks(client: client)
        XCTAssertEqual(store.likedState(.init(rawValue: "netease:track:1")), true)
        XCTAssertNil(store.likedState(.init(rawValue: "netease:track:2")))
        XCTAssertNil(store.likedTracks.value?.items.first?.track)
        await store.loadLikedTracks(client: client, more: true)
        XCTAssertEqual(store.likedTrackIDs.count, 2)
        XCTAssertEqual(store.likedState(.init(rawValue: "netease:track:3")), false)
        XCTAssertEqual(capture.requests.filter { $0.url?.path.hasSuffix("liked-tracks") == true }.count, 2)
    }

    func testOptimisticLikeVisibleBeforeResponseAndFailureRollsBack() async throws {
        let started = expectation(description: "write started"), gate = DispatchSemaphore(value: 0)
        MusicV2URLProtocol.handler = { request in
            if request.httpMethod == "PUT" {
                started.fulfill(); _ = gate.wait(timeout: .now() + 5)
                return .init(status: 503, body: Self.error)
            }
            return .init(body: Self.page(ids: []))
        }
        let store = MusicStore(client: musicTestClient(), userID: 1), client = makeMusicV2Client()
        await store.loadLikedTracks(client: client)
        let id = MusicV2TrackID(rawValue: "netease:track:opaque%2Fpart")
        let write = Task { try await store.toggleLike(id, client: client, enabled: true) }
        await fulfillment(of: [started], timeout: 3)
        XCTAssertEqual(store.likedState(id), true)
        XCTAssertEqual(store.likedTracks.value?.total, 1)
        gate.signal()
        do { try await write.value; XCTFail("Must report failure") } catch {}
        XCTAssertEqual(store.likedState(id), false)
        XCTAssertEqual(store.likedTracks.value?.total, 0)
        await settle(store)
    }

    func testSaveImmediateSuccessAndOpaqueIdentityUsesOneWrite() async throws {
        let capture = MusicV2RequestCapture(), started = expectation(description: "save started"), gate = DispatchSemaphore(value: 0)
        let state = LibraryTestState()
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            if request.httpMethod == "PUT" {
                started.fulfill(); _ = gate.wait(timeout: .now() + 5); state.set(true)
                return .init(status: 204, body: Data())
            }
            return .init(body: Self.page(ids: state.value ? ["opaque%2Fpart"] : [], saved: true))
        }
        let store = MusicStore(client: musicTestClient(), userID: 1), client = makeMusicV2Client()
        await store.loadFavoritePlaylists(client: client)
        let id = MusicV2ProviderPlaylistID(rawValue: "netease:playlist:opaque%2Fpart")
        let write = Task { try await store.toggleFavoritePlaylist(id, client: client, enabled: true) }
        await fulfillment(of: [started], timeout: 3)
        XCTAssertEqual(store.savedState(id), true)
        XCTAssertNil(store.favoritePlaylists.value?.items.first?.playlist)
        gate.signal(); try await write.value; await settle(store)
        XCTAssertEqual(store.savedState(id), true)
        let writes = capture.requests.filter { $0.httpMethod == "PUT" }
        XCTAssertEqual(writes.count, 1)
        XCTAssertTrue(writes[0].url!.absoluteString.contains("opaque%252Fpart"))
    }

    func testAccountSwitchDuringWriteCannotRollbackOrPopulateNewUser() async throws {
        let started = expectation(description: "write started"), gate = DispatchSemaphore(value: 0)
        MusicV2URLProtocol.handler = { request in
            if request.httpMethod == "DELETE" {
                started.fulfill(); _ = gate.wait(timeout: .now() + 5)
                return .init(status: 503, body: Self.error)
            }
            return .init(body: Self.page(ids: ["1"]))
        }
        let store = MusicStore(client: musicTestClient(), userID: 1), client = makeMusicV2Client()
        await store.loadLikedTracks(client: client)
        let write = Task { try await store.toggleLike(.init(rawValue: "netease:track:1"), client: client, enabled: true) }
        await fulfillment(of: [started], timeout: 3)
        store.reset(for: 2); gate.signal()
        do { try await write.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(store.likedTrackIDs.isEmpty); XCTAssertTrue(store.savedPlaylistIDs.isEmpty)
        XCTAssertNil(store.likedTracks.value); XCTAssertNil(store.favoritePlaylists.value); XCTAssertNil(store.library.value)
        XCTAssertFalse(store.libraryWriting)
    }

    func testFalseFlagRejectsMutationWithoutRequest() async {
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in capture.append(request); return .init(status: 204, body: Data()) }
        let store = MusicStore(client: musicTestClient(), userID: 1)
        do { try await store.toggleLike(.init(rawValue: "netease:track:1"), client: makeMusicV2Client(), enabled: false); XCTFail() } catch {}
        do { try await store.toggleFavoritePlaylist(.init(rawValue: "netease:playlist:1"), client: makeMusicV2Client(), enabled: false); XCTFail() } catch {}
        XCTAssertTrue(capture.requests.isEmpty)
        XCTAssertNil(MusicDiscoverRoutes.route(.library(collection: "liked", label: nil), flags: .init()))
    }

    func testErrorsDoNotBecomeEmptyAndRetryRecovers() async {
        let store = MusicStore(client: musicTestClient(), userID: 1), client = makeMusicV2Client()
        MusicV2URLProtocol.handler = { _ in .init(status: 401, body: Self.error) }
        await store.loadLikedTracks(client: client)
        XCTAssertNil(store.likedTracks.value); XCTAssertEqual(store.likedTracks.error?.action, .signIn)
        MusicV2URLProtocol.handler = { _ in .init(body: Self.page(ids: [])) }
        await store.loadLikedTracks(client: client, force: true)
        XCTAssertEqual(store.likedTracks.value?.items.count, 0)
    }

    private func settle(_ store: MusicStore) async {
        for _ in 0..<100 {
            if !store.libraryWriting && !store.likedTracks.isRefreshing && !store.favoritePlaylists.isRefreshing { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    nonisolated static let error = Data(#"{"code":"UPSTREAM_UNAVAILABLE","message":"测试错误","retryable":true,"traceId":null}"#.utf8)
    nonisolated static func page(ids: [String], next: Int? = nil, total: Int? = nil, saved: Bool = false) -> Data {
        let items = ids.map { id in
            saved ? "{\"ownerId\":\"setu:user:1\",\"playlistId\":\"netease:playlist:\(id)\",\"savedAt\":\"2026-09-06T00:00:00Z\",\"playlist\":null}" :
                "{\"ownerId\":\"setu:user:1\",\"trackId\":\"netease:track:\(id)\",\"likedAt\":\"2026-09-06T00:00:00Z\",\"track\":null}"
        }.joined(separator: ",")
        return Data("{\"items\":[\(items)],\"offset\":0,\"limit\":20,\"hasMore\":\(next != nil),\"total\":\(total ?? ids.count),\"nextOffset\":\(next.map(String.init) ?? "null")}".utf8)
    }
}

private final class LibraryTestState: @unchecked Sendable {
    private let lock = NSLock(); private var stored = false
    var value: Bool { lock.withLock { stored } }
    func set(_ value: Bool) { lock.withLock { stored = value } }
}
