import Foundation
import XCTest
@testable import SetuIOSCore
@testable import SetuIOSApp

@MainActor
final class MusicCutoverTests: XCTestCase {
    override func tearDown() { MusicV2URLProtocol.handler = nil; super.tearDown() }
    func testAlbumArtworkIsUsedWhenTrackArtworkIsMissing() throws {
        let json = MusicV2Fixtures.track.replacingOccurrences(of: "\"album\":null", with: #""album":{"id":null,"title":"Album","artwork":{"url":"https://example.test/cover.jpg"}}"#)
        let track = try JSONDecoder().decode(MusicV2Track.self, from: Data(json.utf8))
        XCTAssertEqual(MusicPlaybackTrack(track: track).coverURLString, "https://example.test/cover.jpg")
        XCTAssertEqual(MusicRecentHistoryCard(track: track, onPlay: {}).artwork, "https://example.test/cover.jpg")
    }

    func testDownloadEntriesUseFlagAwareResolver() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for file in ["MusicHomeView.swift", "MusicSearchView.swift", "Player/NowPlayingSheet.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent("Sources/SetuIOSApp/Features/Music/\(file)"), encoding: .utf8)
            XCTAssertFalse(source.contains("environment.musicClient.url("), "\(file) must not bypass playback routing for downloads")
        }
    }

    func testLegacyDownloadIdentityUsesV2WhenPlaybackCutoverIsEnabled() async throws {
        let legacy = MusicTestServer(), capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            if request.url!.path == "/user/music/rollout/capabilities" {
                return .init(body: Data(#"{"version":1,"admitNewPlaybackSession":true,"validForSeconds":30}"#.utf8))
            }
            if request.url!.path == "/user/music/v2/tracks" {
                return .init(body: Data("{\"items\":[\(MusicV2Fixtures.track)]}".utf8))
            }
            return .init(body: typedSourceResponse(request), headers: ["X-Setu-Playback-Contract": "3.0.0"])
        }
        let resolver = PlaybackURLResolver(client: musicTestClient(server: legacy), v2: makeMusicV2Client(), usesV2Playback: true)
        let value = try await resolver.resolve(trackID: 1, quality: .exhigh)
        XCTAssertEqual(value.trackID, .legacy(1))
        XCTAssertEqual(capture.requests.map { $0.url!.path }, ["/user/music/rollout/capabilities", "/user/music/v2/tracks", "/user/music/v2/tracks/netease:track:1/playback"])
        let legacyRequests = await legacy.requests
        XCTAssertTrue(legacyRequests.isEmpty)
    }

    func testLegacyHomeUsesCanonicalHistoryWithoutLegacyHistoryRequest() async {
        let legacy = MusicTestServer()
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            if request.url!.path == "/user/music/v2/tracks" {
                return .init(body: Data("{\"items\":[\(MusicV2Fixtures.track)]}".utf8))
            }
            return .init(body: Data(#"{"items":[{"ownerId":"setu:user:1","trackId":"netease:track:1","lastPlayedAt":"2026-09-06T00:00:00Z","track":null}],"offset":0,"limit":20,"hasMore":false,"total":1,"nextOffset":null}"#.utf8))
        }
        let store = MusicStore(client: musicTestClient(server: legacy), userID: 1)
        await store.loadHome(historyClient: makeMusicV2Client())
        XCTAssertEqual(capture.requests.map { $0.url!.path }, ["/user/music/v2/library/history", "/user/music/v2/tracks"])
        XCTAssertEqual(store.canonicalHistory.value?.items.first?.id.rawValue, "netease:track:1")
        XCTAssertNotNil(store.canonicalHistory.value?.items.first?.entry.track?.title)
        XCTAssertNil(store.recentHistory.value)
        let requests = await legacy.requests
        XCTAssertFalse(requests.contains { $0.contains("/history") })
    }
    func testReleaseMetadataBoundedAndMissingSafe() {
        XCTAssertEqual(MusicClientRelease.header(version: "1.0.0", build: "123"), "ios:1.0.0:123")
        for value in ["a\r\nCookie:secret", "user@example.com", String(repeating: "a", count: 41), ""] {
            XCTAssertNil(MusicClientRelease.header(version: "1.0", build: value))
        }
    }
    func testHistoryPinSurvivesFlagRollbackButNotOwnerOrBackendChange() {
        let name = "music-cutover-test-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let base = URL(string: "https://music.example.test")!
        XCTAssertFalse(MusicHistoryCohort.usesV2(base: base, owner: 1, flag: false, defaults: defaults))
        MusicHistoryCohort.pin(base: base, owner: 1, defaults: defaults)
        XCTAssertTrue(MusicHistoryCohort.usesV2(base: base, owner: 1, flag: false, defaults: defaults))
        XCTAssertFalse(MusicHistoryCohort.usesV2(base: base, owner: 2, flag: false, defaults: defaults))
        XCTAssertFalse(MusicHistoryCohort.usesV2(base: URL(string: "https://other.example.test")!, owner: 1, flag: false, defaults: defaults))
    }
    func testRemoteDenialStopsNewSessionWithoutResolvingOrChangingIdentity() async {
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in capture.append(request); return .init(body: Data(#"{"version":1,"admitNewPlaybackSession":false,"validForSeconds":30}"#.utf8)) }
        let resolver = PlaybackURLResolver(client: musicTestClient(), v2: makeMusicV2Client(), usesV2Playback: true)
        do { try await resolver.authorizeNewSession(); XCTFail("Must deny") } catch {}
        XCTAssertEqual(capture.requests.map { $0.url!.path }, ["/user/music/rollout/capabilities"])
    }
    func testTransportOnWordPresentationOffStillLoadsStructuredLyrics() async {
        MusicV2URLProtocol.handler = { _ in .init(body: Data(p13WordJSON.utf8)) }
        let model = NowPlayingLyricsModel()
        await model.load(identity: .canonical(.init(rawValue: "netease:track:1")), environment: p13Environment(word: false))
        guard case .loaded(let lines) = model.state else { return XCTFail("Transport independent of presentation") }
        XCTAssertEqual(lines.first?.text, "你好世界")
        XCTAssertEqual(lines.first?.words.count, 0)
    }
    func testSearchSourceCursorSurvivesEmptyMappedPageAndOwnerReset() async {
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            let offset = request.url?.query?.contains("offset=20") == true ? 20 : 0
            return .init(body: Data("""
            {"query":"hello","scope":"tracks","best":null,"sections":[{"scope":"tracks","status":"loaded","error":null,"items":{"items":[],"offset":\(offset),"limit":20,"total":null,"hasMore":true,"nextOffset":\(offset + 20)}}]}
            """.utf8))
        }
        let store = MusicStore(client: musicTestClient(), userID: 1)
        store.v2SearchSession.query = "hello"
        await store.v2SearchSession.submit(client: makeMusicV2Client())
        XCTAssertEqual(store.v2SearchSession.nextOffset, 20)
        await store.v2SearchSession.submit(client: makeMusicV2Client(), more: true)
        XCTAssertEqual(store.v2SearchSession.nextOffset, 40)
        XCTAssertEqual(capture.requests.count, 2)
        store.reset(for: 2)
        XCTAssertTrue(store.v2SearchSession.pages.isEmpty)
    }
    func testHistoryClearFailureRollsBackAndOwnerResetDropsRows() async throws {
        MusicV2URLProtocol.handler = { request in
            if request.httpMethod == "DELETE" { return .init(status: 503, body: Data(#"{"code":"UPSTREAM_UNAVAILABLE","message":"later","retryable":true,"traceId":null}"#.utf8)) }
            return .init(body: Data(#"{"items":[{"ownerId":"setu:user:1","trackId":"netease:track:opaque","lastPlayedAt":"2026-09-06T00:00:00Z","track":null}],"offset":0,"limit":20,"hasMore":false,"total":1,"nextOffset":null}"#.utf8))
        }
        let store = MusicStore(client: musicTestClient(), userID: 1), client = makeMusicV2Client()
        await store.loadCanonicalHistory(client: client)
        XCTAssertEqual(store.canonicalHistory.value?.total, 1)
        do { try await store.clearCanonicalHistory(client: client); XCTFail("Must fail") } catch {}
        XCTAssertEqual(store.canonicalHistory.value?.items.first?.id.rawValue, "netease:track:opaque")
        store.reset(for: 2)
        XCTAssertNil(store.canonicalHistory.value)
    }
}
