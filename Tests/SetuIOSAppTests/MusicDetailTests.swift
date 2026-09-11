import XCTest
@testable import SetuIOSCore
@testable import SetuIOSApp

@MainActor
final class MusicDetailTests: XCTestCase {
    override func tearDown() { MusicV2URLProtocol.handler = nil; super.tearDown() }

    func testEachColdDetailUsesOneAggregateRequestAndWarmReentryZero() async throws {
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { capture.append($0); return MusicV2Fixtures.response(for: $0) }
        let store = MusicStore(client: musicTestClient(), userID: 1), v2 = makeMusicV2Client()
        await store.loadArtistDetail("netease:artist:1", client: v2)
        XCTAssertEqual(capture.requests.count, 1)
        await store.loadArtistDetail("netease:artist:1", client: v2)
        XCTAssertEqual(capture.requests.count, 1)
        await store.loadAlbumDetail("netease:album:1", client: v2)
        XCTAssertEqual(capture.requests.count, 2)
        await store.loadPlaylistDetailV2(.provider(.init(rawValue: "netease:playlist:1")), client: v2)
        XCTAssertEqual(capture.requests.count, 3)
        XCTAssertNotNil(store.artistDetail("netease:artist:1").value)
        XCTAssertNotNil(store.albumDetail("netease:album:1").value)
        let data = try XCTUnwrap(store.playlistDetailV2("netease:playlist:1").value)
        XCTAssertEqual(data.memberships.count, 1)
        XCTAssertTrue(data.tracks.isEmpty, "Missing projection must preserve membership without creating Track")
        XCTAssertEqual(data.memberships[0].position, 0)
    }

    func testPlaylistPaginationPreservesMissingMembershipAndServerCursor() async throws {
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            if request.url!.path.hasSuffix("/tracks") {
                return .init(body: Data(MusicV2Fixtures.membershipPage.replacingOccurrences(of: "\"position\":0", with: "\"position\":50")
                    .replacingOccurrences(of: "\"offset\":0", with: "\"offset\":50").utf8))
            }
            let page = MusicV2Fixtures.membershipPage.replacingOccurrences(of: "\"hasMore\":false", with: "\"hasMore\":true")
                .replacingOccurrences(of: "\"nextOffset\":null", with: "\"nextOffset\":50")
            return .init(body: Data("{\"playlist\":\(MusicV2Fixtures.providerPlaylist),\"memberships\":\(page)}".utf8))
        }
        let store = MusicStore(client: musicTestClient(), userID: 1), v2 = makeMusicV2Client()
        let id = MusicV2PlaylistID.provider(.init(rawValue: "netease:playlist:1"))
        await store.loadPlaylistDetailV2(id, client: v2)
        XCTAssertEqual(capture.requests.count, 1)
        async let first: Void = store.loadMorePlaylistDetail(id, client: v2)
        async let second: Void = store.loadMorePlaylistDetail(id, client: v2)
        _ = await (first, second)
        XCTAssertEqual(capture.requests.count, 2)
        XCTAssertTrue(capture.requests[1].url!.query!.contains("offset=50"))
        let value = try XCTUnwrap(store.playlistDetailV2(id.rawValue).value)
        XCTAssertEqual(value.memberships.map(\.position), [0, 50])
        XCTAssertNil(value.nextOffset)
        XCTAssertTrue(value.tracks.isEmpty)
    }

    func testErrorUnauthorizedRetryAndUserResetDoNotBecomeEmptySuccess() async throws {
        let store = MusicStore(client: musicTestClient(), userID: 1), v2 = makeMusicV2Client()
        MusicV2URLProtocol.handler = { _ in .init(status: 503, body: Data(#"{"code":"UPSTREAM_UNAVAILABLE","message":"Unavailable","retryable":true,"traceId":null}"#.utf8)) }
        await store.loadArtistDetail("netease:artist:1", client: v2)
        XCTAssertNil(store.artistDetail("netease:artist:1").value)
        XCTAssertEqual(store.artistDetail("netease:artist:1").error?.action, .retry)
        MusicV2URLProtocol.handler = { _ in .init(status: 401, body: Data(#"{"code":"UNAUTHORIZED","message":"Sign in","retryable":false,"traceId":null}"#.utf8)) }
        await store.loadAlbumDetail("netease:album:1", client: v2)
        XCTAssertNil(store.albumDetail("netease:album:1").value)
        XCTAssertEqual(store.albumDetail("netease:album:1").error?.action, .signIn)
        MusicV2URLProtocol.handler = { MusicV2Fixtures.response(for: $0) }
        await store.loadArtistDetail("netease:artist:1", client: v2, force: true)
        XCTAssertNotNil(store.artistDetail("netease:artist:1").value)
        let old = store.artistDetail("netease:artist:1")
        store.reset(for: 2)
        XCTAssertNil(old.value)
        XCTAssertTrue(store.artistDetails.isEmpty)
        XCTAssertTrue(store.albumDetails.isEmpty)
        XCTAssertTrue(store.playlistDetailsV2.isEmpty)
    }

    func testOwnershipAndRelationBridgeNeverUseTrackIdentity() throws {
        let provider = try JSONDecoder().decode(MusicV2PlaylistDetail.self, from: Data("{\"playlist\":\(MusicV2Fixtures.providerPlaylist),\"memberships\":\(MusicV2Fixtures.membershipPage)}".utf8))
        XCTAssertNil(MusicPlaylistDetailData(provider).ownedLocal(by: 1))
        let local = MusicV2Fixtures.providerPlaylist.replacingOccurrences(of: "netease:playlist:1", with: "setu:playlist:42")
            .replacingOccurrences(of: "\"origin\":\"provider\"", with: "\"origin\":\"local\"")
            .dropLast() + #", "ownerId":"setu:user:9","visibility":"private","defaultPlaybackMode":"sequence","createdAt":"2026-09-05T00:00:00Z"}"#
        let emptyPage = #"{"items":[],"offset":0,"limit":50,"hasMore":false,"total":0,"nextOffset":null}"#
        let data = MusicPlaylistDetailData(try JSONDecoder().decode(MusicV2PlaylistDetail.self, from: Data("{\"playlist\":\(local),\"memberships\":\(emptyPage)}".utf8)))
        XCTAssertNotNil(data.ownedLocal(by: 9)); XCTAssertNil(data.ownedLocal(by: 8)); XCTAssertNil(data.ownedLocal(by: nil))
        XCTAssertEqual(try MusicLocalPlaylistBridge.path(MusicV2SetuPlaylistID(rawValue: "setu:playlist:42")), "42")
        XCTAssertEqual(try MusicLocalPlaylistBridge.path(MusicV2PlaylistRelationID(rawValue: "setu:playlistMembership:7")), "7")
        XCTAssertThrowsError(try MusicLocalPlaylistBridge.path(MusicV2PlaylistRelationID(rawValue: "netease:track:7")))
        XCTAssertThrowsError(try MusicLocalPlaylistBridge.path(MusicV2SetuPlaylistID(rawValue: "setu:playlist:04")))
    }

    func testDetailMutationInvalidatesBothLegacyResourceAndRepositoryCache() async throws {
        let server = MusicTestServer()
        let store = MusicStore(client: musicTestClient(server: server), userID: 1)
        await store.loadPlaylists(); await store.loadDetail(1)
        await server.set("GET /user/playlists", #"[{"id":1,"name":"从详情页改名"}]"#)
        await store.invalidateLegacyPlaylistReadsAfterDetailWrite()
        await store.loadPlaylists(); await store.loadDetail(1)
        XCTAssertEqual(store.playlists.value?.first?.name, "从详情页改名")
        let requests = await server.requests
        XCTAssertEqual(requests.filter { $0 == "GET /user/playlists" }.count, 2)
        XCTAssertEqual(requests.filter { $0 == "GET /user/playlists/1" }.count, 2)
    }

    func testPlayingPlaylistQueuesEveryPageNotJustTheFirstFifty() async throws {
        let playlistID = MusicV2PlaylistID.provider(.init(rawValue: "netease:playlist:big"))
        let total = 70
        MusicV2URLProtocol.handler = { request in
            let offset = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "offset" }?.value.flatMap(Int.init) ?? 0
            let page = playlistMembershipPage(playlistID: playlistID.rawValue, offset: offset, total: total)
            if request.url!.path.hasSuffix("/tracks") {
                return .init(body: Data(page.utf8))
            }
            let playlist = MusicV2Fixtures.providerPlaylist
                .replacingOccurrences(of: "netease:playlist:1", with: playlistID.rawValue)
                .replacingOccurrences(of: "\"trackCount\":0", with: "\"trackCount\":\(total)")
            return .init(body: Data("{\"playlist\":\(playlist),\"memberships\":\(page)}".utf8))
        }
        let store = MusicStore(client: musicTestClient(), userID: 1)
        let player = MusicPlaybackController(persistsPlayback: false)
        addTeardownBlock { await MainActor.run { player.stop() } }
        let intent = MusicPlaybackIntent(player: player, store: store, libraryClient: makeMusicV2Client())
        await store.loadPlaylistDetailV2(playlistID, client: makeMusicV2Client())
        let data = try XCTUnwrap(store.playlistDetailV2(playlistID.rawValue).value)
        XCTAssertEqual(data.tracks.count, 50)
        XCTAssertNotNil(data.nextOffset)
        let first = try XCTUnwrap(data.tracks.first)
        await intent.play(first, in: data.tracks, context: data.context)
        XCTAssertEqual(player.queueTracks.count, total)
        XCTAssertEqual(player.queueTracks.first?.title, "Song 0")
        XCTAssertEqual(player.queueTracks.last?.title, "Song 69")
        XCTAssertEqual(store.playlistDetailV2(playlistID.rawValue).value?.tracks.count, total)
    }

    func testPlaylistRemainderDoesNotJoinADifferentQueue() async throws {
        let url = URL(fileURLWithPath: "/private/tmp/nonexistent-playback-fixture")
        let player = MusicPlaybackController(persistsPlayback: false)
        addTeardownBlock { await MainActor.run { player.stop() } }
        let current = MusicPlaybackTrack(id: 1, title: "Current", artist: "", album: "", coverURLString: nil,
                                         durationMilliseconds: 1_000, mvID: nil, streamURL: url)
        let leftover = MusicPlaybackTrack(id: 2, title: "Leftover", artist: "", album: "", coverURLString: nil,
                                          durationMilliseconds: 1_000, mvID: nil, streamURL: url)
        let playlist = PlaybackContext.playlist(id: .provider(.canonical(.init(rawValue: "netease:playlist:a"))), label: "A")
        let other = PlaybackContext.playlist(id: .provider(.canonical(.init(rawValue: "netease:playlist:b"))), label: "B")
        player.play(url: url, track: current, context: other, queueTracks: [current])
        player.appendUpcoming([leftover], matching: playlist)
        XCTAssertEqual(player.queueTracks.map(\.title), ["Current"])
        player.appendUpcoming([leftover], matching: other)
        XCTAssertEqual(player.queueTracks.map(\.title), ["Current", "Leftover"])
    }

    func testRoutesOffAndUnknownOrNullIdentityStayUnavailable() {
        var flags = MusicFeatureFlags()
        XCTAssertNil(MusicDetailRoutes.artist(.init(rawValue: "netease:artist:1"), flags: flags))
        XCTAssertNil(MusicDetailRoutes.album(.init(rawValue: "netease:album:1"), flags: flags))
        flags.artistDetailEnabled = true; flags.albumDetailEnabled = true
        XCTAssertEqual(MusicDetailRoutes.artist(.init(rawValue: "netease:artist:opaque%2Fid"), flags: flags), .artistDetail("netease:artist:opaque%2Fid"))
        XCTAssertNil(MusicDetailRoutes.artist(.init(rawValue: "future:artist:1"), flags: flags))
        XCTAssertNil(MusicDetailRoutes.album(nil, flags: flags))
        XCTAssertFalse(flags.usesV2Playback); XCTAssertFalse(flags.usesV2PlaylistDetail)
    }
}

private func playlistMembershipPage(playlistID: String, offset: Int, total: Int, limit: Int = 50) -> String {
    let end = min(offset + limit, total)
    let items = (offset..<end).map { index -> String in
        let track = MusicV2Fixtures.track
            .replacingOccurrences(of: "netease:track:1", with: "netease:track:\(index)")
            .replacingOccurrences(of: "\"title\":\"Track\"", with: "\"title\":\"Song \(index)\"")
        return "{\"playlistId\":\"\(playlistID)\",\"trackId\":\"netease:track:\(index)\",\"position\":\(index),\"track\":\(track),\"relationId\":null,\"addedAt\":null}"
    }.joined(separator: ",")
    let hasMore = end < total
    return "{\"items\":[\(items)],\"offset\":\(offset),\"limit\":\(limit),\"hasMore\":\(hasMore),\"total\":\(total),\"nextOffset\":\(hasMore ? String(end) : "null")}"
}
