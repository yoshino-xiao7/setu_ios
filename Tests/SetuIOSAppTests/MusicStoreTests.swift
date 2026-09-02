import Foundation
import XCTest
@testable import SetuIOSCore
@testable import SetuIOSApp

@MainActor
final class MusicStoreTests: XCTestCase {
    func testHomeReturnAndSharedPlaylistConsumersSendZeroRequestsWithinTTL() async {
        let server = MusicTestServer()
        let store = MusicStore(client: musicTestClient(server: server), userID: 1)
        await store.loadHome()
        XCTAssertNotNil(store.hotSearch.value)
        XCTAssertNotNil(store.recommendedPlaylists.value)
        XCTAssertNotNil(store.newSongs.value)
        XCTAssertNotNil(store.dailySongs.value)
        XCTAssertNotNil(store.recentHistory.value)
        XCTAssertNotNil(store.playlists.value)
        let first = await server.requests
        XCTAssertEqual(first.count, 6)
        // Same Store as the NavigationStack root, destination and all picker sheets.
        let start = ContinuousClock.now
        await store.loadHome()
        await store.loadPlaylists()
        await store.loadPlaylists()
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(100))
        let returned = await server.requests
        XCTAssertEqual(returned, first)
    }

    func testExpiredHomeKeepsAllContentDuringSilentRefresh() async {
        let server = MusicTestServer()
        let clock = MusicTestClock()
        let store = MusicStore(client: musicTestClient(server: server), userID: 1, now: { clock.now })
        await store.loadHome()
        clock.advance(1_801)
        let gate = MusicTestGate()
        let started = expectation(description: "all six refreshes")
        started.expectedFulfillmentCount = 6
        await server.hold(gate, observed: started)
        let refresh = Task { await store.loadHome() }
        await fulfillment(of: [started], timeout: 3)
        XCTAssertTrue(store.hotSearch.isRefreshing)
        XCTAssertTrue(store.recommendedPlaylists.isRefreshing)
        XCTAssertTrue(store.newSongs.isRefreshing)
        XCTAssertTrue(store.dailySongs.isRefreshing)
        XCTAssertTrue(store.recentHistory.isRefreshing)
        XCTAssertTrue(store.playlists.isRefreshing)
        if case .loaded = store.hotSearch.state {} else { XCTFail("No skeleton during SWR") }
        XCTAssertNotNil(store.recommendedPlaylists.value)
        XCTAssertNotNil(store.newSongs.value)
        XCTAssertNotNil(store.dailySongs.value)
        XCTAssertNotNil(store.recentHistory.value)
        XCTAssertNotNil(store.playlists.value)
        await gate.open()
        await refresh.value
    }

    func testDetailSurvivesNavigationAndWritesUpdateOnlyAffectedResources() async throws {
        let server = MusicTestServer()
        let store = MusicStore(client: musicTestClient(server: server), userID: 1)
        await store.loadHome()
        await store.loadDetail(1)
        await store.loadDetail(2)
        let resource = store.detail(1)
        await store.loadDetail(1)
        XCTAssertTrue(resource === store.detail(1))
        var requests = await server.requests
        XCTAssertEqual(requests.filter { $0 == "GET /user/playlists/1" }.count, 1)
        let originalGETs = requests.filter { $0.hasPrefix("GET") }.count
        let song = try XCTUnwrap(resource.value?.songs?.first)
        try await store.removeSong(playlistID: 1, song: song)
        XCTAssertEqual(resource.value?.songs?.count, 0)
        XCTAssertEqual(store.playlists.value?.first?.songCount, 0)
        try await store.add(AddSongToPlaylistRequest(song: song), toPlaylist: 1)
        XCTAssertEqual(resource.value?.songs?.map(\.songId), [7])
        XCTAssertEqual(store.playlists.value?.first?.songCount, 1)
        try await store.updatePlaylist(id: 1, name: "改名", description: "描述", coverUrl: nil, isPublic: 1)
        XCTAssertEqual(resource.value?.name, "改名")
        XCTAssertEqual(store.playlists.value?.first?.name, "改名")
        try await store.setPlayMode(playlistID: 1, playMode: "single")
        XCTAssertEqual(resource.value?.playMode, "single")
        try await store.createPlaylist(name: "新歌单", description: nil, isPublic: 0)
        XCTAssertEqual(store.playlists.value?.first?.id, 3)
        try await store.deletePlaylist(id: 1)
        XCTAssertFalse(store.playlists.value?.contains { $0.id == 1 } ?? true)
        XCTAssertNil(store.playlistDetails[1])
        await store.loadDetail(2)
        requests = await server.requests
        XCTAssertTrue(requests.contains("DELETE /user/playlists/1/songs/91"), "Use the backend relation ID, not songId 7")
        XCTAssertEqual(requests.filter { $0.hasPrefix("GET") }.count, originalGETs)
        XCTAssertNotNil(store.hotSearch.fetchedAt, "Playlist mutations must not invalidate recommendations")
    }

    func testCreateWithoutCachedListPublishesImmediatelyAndReconcilesSilently() async throws {
        let server = MusicTestServer()
        let store = MusicStore(client: musicTestClient(server: server), userID: 1)
        let gate = MusicTestGate()
        let started = expectation(description: "reconcile previously unavailable list")
        await server.set("GET /user/playlists", #"[{"id":3,"name":"新歌单"},{"id":1,"name":"已有歌单"}]"#)
        await server.hold(gate, observed: started, paths: ["GET /user/playlists"])
        try await store.createPlaylist(name: "新歌单", description: nil, isPublic: 0)
        XCTAssertEqual(store.playlists.value?.map(\.id), [3])
        await fulfillment(of: [started], timeout: 3)
        if case .loaded = store.playlists.state {} else { XCTFail("Created playlist must not become a skeleton") }
        await gate.open()
        await store.loadPlaylists()
        XCTAssertEqual(store.playlists.value?.map(\.id), [3, 1])
    }

    func testFailedMutationPreservesExistingPlaylist() async throws {
        let server = MusicTestServer()
        let store = MusicStore(client: musicTestClient(server: server), userID: 1)
        await store.loadDetail(1)
        await server.set("DELETE /user/playlists/1/songs/91", #"{"code":400,"message":"拒绝"}"#)
        await server.setStatus("DELETE /user/playlists/1/songs/91", 400)
        let song = try XCTUnwrap(store.detail(1).value?.songs?.first)
        do { try await store.removeSong(playlistID: 1, song: song); XCTFail("Expected failure") } catch {}
        XCTAssertEqual(store.detail(1).value?.songs?.count, 1)
    }

    func testUserSwitchClearsValuesAndRejectsOldReadAndWriteCompletions() async throws {
        let server = MusicTestServer()
        let store = MusicStore(client: musicTestClient(server: server), userID: 1)
        await store.loadHome()
        await store.loadDetail(1)
        await store.loadHistory()
        let gate = MusicTestGate()
        let started = expectation(description: "old read and write")
        started.expectedFulfillmentCount = 2
        await server.hold(gate, observed: started)
        let refresh = Task { await store.loadPlaylists(force: true) }
        let write = Task { try await store.createPlaylist(name: "A", description: nil, isPublic: 0) }
        await fulfillment(of: [started], timeout: 3)
        store.reset(for: 2)
        XCTAssertNil(store.hotSearch.value)
        XCTAssertNil(store.playlists.value)
        XCTAssertNil(store.history.value)
        XCTAssertNil(store.recentHistory.value)
        XCTAssertTrue(store.playlistDetails.isEmpty)
        await server.hold(nil)
        await server.set("GET /user/playlists", #"[{"id":22,"name":"B"}]"#)
        await store.loadPlaylists()
        await gate.open()
        await refresh.value
        do { try await write.value; XCTFail("Old-account completion must be revoked") } catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertEqual(store.playlists.value?.map(\.id), [22])
        store.reset(for: nil)
        XCTAssertNil(store.playlists.value)
    }

    func testHistoryPaginationSurvivesReentryAndClearDoesNotReload() async {
        let server = MusicTestServer()
        let rows = (1...20).map { #"{"id":\#($0),"userId":1,"songId":\#($0),"songName":"曲","artistName":"人","playTime":"今天"}"# }.joined(separator: ",")
        await server.set("GET /user/music/history", "[\(rows)]")
        await server.set("GET /user/music/history/count", "21")
        let store = MusicStore(client: musicTestClient(server: server), userID: 1)
        await store.loadHistory()
        await server.set("GET /user/music/history", #"[{"id":21,"userId":1,"songId":21,"songName":"曲","artistName":"人","playTime":"今天"}]"#)
        await store.loadMoreHistory()
        XCTAssertEqual(store.history.value?.records.count, 21)
        let before = await server.requests
        await store.loadHistory()
        let after = await server.requests
        XCTAssertEqual(after, before)
        do { try await store.clearHistory() } catch { XCTFail("\(error)") }
        XCTAssertEqual(store.history.value?.records.count, 0)
        XCTAssertEqual(store.recentHistory.value?.count, 0)
        let cleared = await server.requests
        XCTAssertEqual(cleared.count, before.count + 1)
    }

    func testHistoryWritePrependsAndDeduplicatesBeforeRevalidation() async throws {
        let server = MusicTestServer()
        let store = MusicStore(client: musicTestClient(server: server), userID: 1)
        await store.loadHome()
        await store.loadHistory()
        let gate = MusicTestGate()
        let started = expectation(description: "history reconciliation")
        started.expectedFulfillmentCount = 2
        await server.hold(gate, observed: started, paths: ["GET /user/music/history", "GET /user/music/history/count"])
        try await store.addHistory(AddMusicHistoryRequest(songId: 7, songName: "重新播放", artistName: "歌手", albumName: nil, coverUrl: nil, duration: 1))
        await fulfillment(of: [started], timeout: 3)
        XCTAssertEqual(store.history.value?.records.map(\.songId), [7])
        XCTAssertEqual(store.history.value?.records.first?.songName, "重新播放")
        XCTAssertEqual(store.history.value?.count, 1)
        XCTAssertEqual(store.recentHistory.value?.first?.songName, "重新播放")
        XCTAssertTrue(store.history.isRefreshing)
        await server.hold(nil)
        await gate.open()
        await store.loadHistory()
        // Drain the owned reconciliation before the next URLProtocol fixture is installed.
        await store.loadHome()
    }

    func testLateDetailReadCannotUndoSuccessfulRemoval() async throws {
        let server = MusicTestServer()
        let store = MusicStore(client: musicTestClient(server: server), userID: 1)
        await store.loadPlaylists()
        await store.loadDetail(1)
        let song = try XCTUnwrap(store.detail(1).value?.songs?.first)
        let gate = MusicTestGate()
        let started = expectation(description: "stale detail read")
        await server.hold(gate, observed: started, paths: ["GET /user/playlists/1"])
        let refresh = Task { await store.loadDetail(1, force: true) }
        await fulfillment(of: [started], timeout: 3)
        try await store.removeSong(playlistID: 1, song: song)
        XCTAssertEqual(store.detail(1).value?.songs?.count, 0)
        await gate.open()
        await refresh.value
        XCTAssertEqual(store.detail(1).value?.songs?.count, 0)
        XCTAssertEqual(store.playlists.value?.first?.songCount, 0)
    }

    func testResourceLoadingCancellationAndRefreshFailureKeepValue() async {
        let resource = MusicResource<Int>()
        let gate = MusicTestGate()
        let started = expectation(description: "initial")
        let load = Task { await resource.load(ttl: 10, now: Date(), force: false) {
            started.fulfill(); await gate.wait(); return (7, Date())
        } }
        await fulfillment(of: [started], timeout: 2)
        if case .loading = resource.state {} else { XCTFail("Cold load needs skeleton") }
        load.cancel() // View disappears. Store-owned request still populates the resource.
        await gate.open()
        await load.value
        XCTAssertEqual(resource.value, 7)
        await resource.load(ttl: 10, now: Date(), force: true) { throw URLError(.notConnectedToInternet) }
        XCTAssertEqual(resource.value, 7)
        XCTAssertNotNil(resource.error)
        XCTAssertFalse(resource.isRefreshing)
        if case .loaded = resource.state {} else { XCTFail("Refresh failure must preserve content") }
    }
}
