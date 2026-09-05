import Foundation
import XCTest
@testable import SetuIOSCore
@testable import SetuIOSApp

@MainActor
final class MusicDiscoverTests: XCTestCase {
    override func tearDown() { MusicV2URLProtocol.handler = nil; super.tearDown() }

    func testHomeColdOneWarmAndNavigationReturnZeroForceOne() async throws {
        let capture = MusicV2RequestCapture(), keychain = MusicV2CountingKeychain()
        MusicV2URLProtocol.handler = { capture.append($0); return MusicV2Fixtures.response(for: $0) }
        let store = MusicStore(client: musicTestClient(), userID: 1), client = makeMusicV2Client(keychain: keychain)
        async let a: Void = store.loadHomeV2(client: client)
        async let b: Void = store.loadHomeV2(client: client)
        _ = await (a, b)
        XCTAssertEqual(capture.requests.map { $0.url!.path }, ["/user/music/v2/home"])
        await store.loadHomeV2(client: client)
        XCTAssertEqual(capture.requests.count, 1)
        await store.loadHomeV2(client: client, force: true)
        XCTAssertEqual(capture.requests.count, 2)
        XCTAssertNil(store.hotSearch.value); XCTAssertNil(store.playlists.value)
        XCTAssertEqual(keychain.readCount, 0)
    }

    func testLegacyHomeStillUsesSixReads() async {
        let server = MusicTestServer()
        let store = MusicStore(client: musicTestClient(server: server), userID: 1)
        await store.loadHome()
        let first = await server.requests
        XCTAssertEqual(first.count, 6)
        await store.loadHome()
        let second = await server.requests
        XCTAssertEqual(second.count, 6)
        XCTAssertNil(store.homeFeed.value)
    }

    func testHomeKnownSectionsKeepOrderUnknownSkippedAndDegradedItemsRetained() throws {
        let item: [String: Any] = ["kind": "track", "track": try json(MusicV2Fixtures.track)]
        let source = try json(MusicV2Fixtures.source)
        let sections: [[String: Any]] = [
            ["id": "future", "kind": "future", "arbitrary": true],
            section("stale", kind: "dailyTracks", items: [item], source: source, degraded: true),
            section("empty", kind: "newTracks", items: [], source: source, degraded: true),
            section("healthy", kind: "continueListening", items: [item], source: NSNull(), degraded: false)
        ]
        let feed = try JSONDecoder().decode(MusicV2HomeFeed.self, from: JSONSerialization.data(withJSONObject: ["sections": sections, "generatedAt": "2026-09-05T00:00:00Z"]))
        XCTAssertEqual(feed.sections.map(\.id), ["stale", "empty", "healthy"])
        XCTAssertEqual(feed.sections.map { $0.items.count }, [1, 0, 1])
        XCTAssertEqual(feed.sections.map(\.degraded), [true, true, false])
        let model = MusicHomeSectionPresentation(feed.sections[0], userID: 1)
        XCTAssertEqual(model.tracks.first?.id.rawValue, "netease:track:1")
        guard case .discovery(let provenance, _, _) = model.context else { return XCTFail("Expected exact source") }
        XCTAssertFalse(provenance.personalized); XCTAssertEqual(provenance.kind, .sharedAlgorithmic)
    }

    func testRefreshFailureKeepsHomeAndAuthenticationIsNotEmptySuccess() async throws {
        let store = MusicStore(client: musicTestClient(), userID: 1), client = makeMusicV2Client()
        MusicV2URLProtocol.handler = { MusicV2Fixtures.response(for: $0) }
        await store.loadHomeV2(client: client)
        MusicV2URLProtocol.handler = { _ in .init(status: 503, body: Data(#"{"code":"UPSTREAM_UNAVAILABLE","message":"暂不可用","retryable":true,"traceId":null}"#.utf8)) }
        await store.loadHomeV2(client: client, force: true)
        XCTAssertNotNil(store.homeFeed.value); XCTAssertNotNil(store.homeFeed.error)
        await store.loadRankings(client: client)
        XCTAssertNil(store.rankings.value); XCTAssertNotNil(store.rankings.error)
        MusicV2URLProtocol.handler = { _ in .init(status: 401, body: Data(#"{"code":"UNAUTHORIZED","message":"请登录","retryable":false,"traceId":null}"#.utf8)) }
        await store.loadDailyRecommendations(client: client)
        XCTAssertNil(store.dailyRecommendations.value)
        XCTAssertEqual(store.dailyRecommendations.error?.action, .signIn)
    }

    func testDiscoveryPagesUseP9AndAreaCursorCachesStaySeparate() async throws {
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            guard request.url!.path.contains("/new-releases/") else { return MusicV2Fixtures.response(for: request) }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let offset = Int(query.first { $0.name == "offset" }!.value!)!
            let area = query.first { $0.name == "area" }!.value!
            let album = request.url!.path.hasSuffix("/albums")
            var item = try! selflessJSON(album ? MusicV2Fixtures.album : MusicV2Fixtures.track)
            item["id"] = "netease:\(album ? "album" : "track"):\(area)-\(offset)"
            let page: [String: Any] = ["items": [item], "offset": offset, "limit": 30,
                "hasMore": offset == 0, "nextOffset": offset == 0 ? 37 : NSNull(), "total": NSNull()]
            let body: [String: Any] = ["area": area, "items": page, "source": try! selflessJSON(MusicV2Fixtures.source)]
            return .init(body: try! JSONSerialization.data(withJSONObject: body))
        }
        let store = MusicStore(client: musicTestClient(), userID: 1), client = makeMusicV2Client()
        await store.loadRankings(client: client); await store.loadDailyRecommendations(client: client)
        await store.loadNewTracks(.zh, client: client)
        async let a: Void = store.loadNewTracks(.zh, client: client, more: true)
        async let b: Void = store.loadNewTracks(.zh, client: client, more: true)
        _ = await (a, b)
        XCTAssertEqual(store.releaseTracks(.zh).value?.items.map(\.id.rawValue), ["netease:track:zh-0", "netease:track:zh-37"])
        XCTAssertNil(store.releaseTracks(.zh).value?.nextOffset)
        XCTAssertEqual(capture.requests.filter { $0.url!.query?.contains("offset=37") == true }.count, 1)
        await store.loadNewAlbums(.jp, client: client)
        XCTAssertEqual(store.releaseAlbums(.jp).value?.items.first?.id.rawValue, "netease:album:jp-0")
        let count = capture.requests.count
        await store.loadNewTracks(.zh, client: client)
        XCTAssertEqual(capture.requests.count, count)
        await store.loadNewTracks(.zh, client: client, force: true)
        XCTAssertEqual(store.releaseTracks(.zh).value?.items.count, 1)
        await store.loadNewTracks(.zh, client: client, more: true)
        XCTAssertEqual(capture.requests.count, count + 2, "Refresh invalidates old page caches")
        store.reset(for: 2)
        XCTAssertNil(store.homeFeed.value); XCTAssertNil(store.rankings.value); XCTAssertNil(store.dailyRecommendations.value)
        XCTAssertTrue(store.newReleaseTracks.isEmpty); XCTAssertTrue(store.newReleaseAlbums.isEmpty)
    }

    func testFlagsRouteCapabilitiesAndSourceRemainTruthful() {
        var flags = MusicFeatureFlags()
        for selection in ["dailyTracks", "rankings", "newTracks", "newAlbums", "radio"] {
            XCTAssertNil(MusicDiscoverRoutes.route(.discovery(selection: selection, label: nil), flags: flags))
        }
        flags.usesV2Home = true; flags.rankingsEnabled = true; flags.newReleasesEnabled = true
        XCTAssertEqual(MusicDiscoverRoutes.route(.discovery(selection: "newAlbums", label: nil), flags: flags), .newReleases(albums: true))
        XCTAssertEqual(MusicDiscoverRoutes.route(.discovery(selection: "dailyTracks", label: nil), flags: flags), .dailyRecommend)
        XCTAssertNil(MusicDiscoverRoutes.route(.discovery(selection: "radio", label: nil), flags: flags))
        XCTAssertNil(MusicDiscoverRoutes.route(.library(collection: "liked", label: nil), flags: flags))
        XCTAssertNil(MusicDiscoverRoutes.route(.resource(ref: .playlist(.unknown("future:1")), label: nil), flags: flags))
        XCTAssertFalse(flags.usesV2Playback); XCTAssertFalse(flags.likedTracksEnabled); XCTAssertFalse(flags.radioFMEnabled)
    }

    func testDailyResourceHonorsDayBoundaryAndWarmReentry() async {
        let clock = MusicTestClock(), capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { capture.append($0); return MusicV2Fixtures.response(for: $0) }
        let store = MusicStore(client: musicTestClient(), userID: 1, now: { clock.now }), client = makeMusicV2Client()
        await store.loadDailyRecommendations(client: client)
        await store.loadDailyRecommendations(client: client)
        XCTAssertEqual(capture.requests.count, 1)
        clock.advance(24 * 60 * 60)
        await store.loadDailyRecommendations(client: client)
        XCTAssertEqual(capture.requests.count, 2)
    }

    func testUserSwitchRejectsInFlightHomeAndReloadsForNewOwner() async {
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            Thread.sleep(forTimeInterval: 0.05)
            return MusicV2Fixtures.response(for: request)
        }
        let store = MusicStore(client: musicTestClient(), userID: 1), client = makeMusicV2Client()
        let old = Task { await store.loadHomeV2(client: client) }
        while capture.requests.isEmpty { await Task.yield() }
        store.reset(for: 2)
        await old.value
        XCTAssertNil(store.homeFeed.value)
        await store.loadHomeV2(client: client)
        XCTAssertNotNil(store.homeFeed.value)
        XCTAssertEqual(capture.requests.count, 2)
    }

    private func json(_ raw: String) throws -> [String: Any] { try selflessJSON(raw) }
    private func section(_ id: String, kind: String, items: [[String: Any]], source: Any, degraded: Bool) -> [String: Any] {
        ["id": id, "kind": kind, "title": id, "subtitle": NSNull(), "action": NSNull(), "source": source, "items": items, "degraded": degraded]
    }
}
private func selflessJSON(_ raw: String) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String: Any]
}
