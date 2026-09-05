import Foundation
import XCTest
@testable import SetuIOSCore

final class MusicV2ClientTests: XCTestCase {
    override func tearDown() {
        MusicV2URLProtocol.handler = nil
        super.tearDown()
    }

    func testAll34OperationsUseFrozenPathsAndNeverReadSigningKey() async throws {
        let capture = MusicV2RequestCapture()
        let keychain = MusicV2CountingKeychain()
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            return MusicV2Fixtures.response(for: request)
        }
        let client = makeMusicV2Client(keychain: keychain)
        let track = MusicV2TrackID(rawValue: "netease:track:1")
        let artist = MusicV2ArtistID(rawValue: "netease:artist:1")
        let album = MusicV2AlbumID(rawValue: "netease:album:1")
        let playlist = MusicV2PlaylistID.provider(.init(rawValue: "netease:playlist:1"))
        let providerPlaylist = MusicV2ProviderPlaylistID(rawValue: "netease:playlist:1")

        _ = try await client.home()                                      // 01
        _ = try await client.search(keywords: "中文 空格")               // 02
        _ = try await client.searchSuggestions(keywords: "中文")         // 03
        _ = try await client.hotSearch()                                 // 04
        _ = try await client.track(track)                                // 05
        _ = try await client.tracks([track])                             // 06
        _ = try await client.playback(trackID: track)                    // 07
        _ = try await client.playback(trackIDs: [track])                 // 08
        _ = try await client.lyrics(trackID: track)                      // 09
        _ = try await client.similar(trackID: track)                     // 10
        _ = try await client.artist(artist)                              // 11
        _ = try await client.artistTracks(artist)                        // 12
        _ = try await client.artistAlbums(artist)                        // 13
        _ = try await client.artistMVs(artist)                           // 14
        _ = try await client.album(album)                                // 15
        _ = try await client.playlist(playlist)                          // 16
        _ = try await client.playlistTracks(playlist)                    // 17
        _ = try await client.rankings()                                  // 18
        _ = try await client.recommendedTracks()                         // 19
        _ = try await client.recommendedPlaylists()                      // 20
        _ = try await client.newReleaseTracks()                          // 21
        _ = try await client.newReleaseAlbums()                          // 22
        _ = try await client.radioFM()                                   // 23
        try await client.blockRadioTrack(track)                          // 24
        _ = try await client.library()                                   // 25
        _ = try await client.likedTracks()                               // 26
        try await client.like(track)                                     // 27
        try await client.unlike(track)                                   // 28
        _ = try await client.favoritePlaylists()                         // 29
        try await client.savePlaylist(providerPlaylist)                  // 30
        try await client.unsavePlaylist(providerPlaylist)                // 31
        _ = try await client.history()                                   // 32
        try await client.recordHistory(trackID: track)                   // 33
        try await client.clearHistory()                                  // 34

        let requests = capture.requests
        XCTAssertEqual(requests.count, 34)
        XCTAssertEqual(keychain.readCount, 0, "Every v2 operation is SID-only and must bypass HMAC/Keychain")
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Signature") == nil })
        XCTAssertEqual(requests.map(\.httpMethod).filter { $0 == "GET" }.count, 27)
        XCTAssertEqual(requests.map(\.httpMethod).filter { $0 == "POST" }.count, 2)
        XCTAssertEqual(requests.map(\.httpMethod).filter { $0 == "PUT" }.count, 2)
        XCTAssertEqual(requests.map(\.httpMethod).filter { $0 == "DELETE" }.count, 3)

        let searchURL = try XCTUnwrap(requests[1].url)
        let searchItems = URLComponents(url: searchURL, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(searchItems?.first(where: { $0.name == "keywords" })?.value, "中文 空格")
        XCTAssertEqual(searchItems?.first(where: { $0.name == "scope" })?.value, "tracks")
        XCTAssertNil(searchItems?.first(where: { $0.name == "limit" }), "Omitted limit preserves FINAL all/single defaults")
        XCTAssertTrue(requests[4].url?.absoluteString.contains("netease%3Atrack%3A1") == true)
        XCTAssertTrue(requests[5].url?.absoluteString.contains("ids=netease%3Atrack%3A1") == true)
    }

    func test204IsConsumedWithoutJSONDecoding() async throws {
        MusicV2URLProtocol.handler = { request in (.init(status: 204, body: Data())) }
        let client = makeMusicV2Client()
        try await client.unlike(.init(rawValue: "netease:track:1"))
        try await client.clearHistory()
    }

    func testFinalMusicErrorIsPreservedAsTypedServerError() async throws {
        MusicV2URLProtocol.handler = { _ in
            .init(status: 503, body: Data(#"{"code":"UPSTREAM_AUTH_INVALID","message":"provider unavailable","retryable":true,"traceId":"trace-1"}"#.utf8))
        }
        do {
            _ = try await makeMusicV2Client().home()
            XCTFail("Expected a typed server error")
        } catch let error as MusicV2ServerError {
            XCTAssertEqual(error.status, 503)
            XCTAssertEqual(error.error.code, .upstreamAuthInvalid)
            XCTAssertEqual(error.error.traceId, "trace-1")
            XCTAssertEqual(UserFacingErrorMapper.map(error).action, .wait)
        }
    }

    func testSID401InvalidatesAuthSessionWithoutHMAC() async throws {
        MusicV2URLProtocol.handler = { _ in
            .init(status: 401, body: Data(#"{"code":"UNAUTHORIZED","message":"session expired","retryable":false,"traceId":null}"#.utf8))
        }
        let invalidations = AsyncCounter()
        let notifier = SessionInvalidationNotifier()
        notifier.setHandler { await invalidations.increment() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MusicV2URLProtocol.self]
        let base = URL(string: "https://music-v2.test")!
        let api = APIClient(
            config: AppConfig(apiBaseURL: base, siteBaseURL: base),
            signer: AuthSigner(keychain: MusicV2CountingKeychain()),
            session: URLSession(configuration: configuration),
            sessionInvalidationNotifier: notifier
        )
        do { _ = try await MusicV2Client(apiClient: api).home(); XCTFail("Expected 401") } catch {}
        let invalidationCount = await invalidations.value
        XCTAssertEqual(invalidationCount, 1)
    }
}

private actor AsyncCounter {
    private var count = 0
    func increment() { count += 1 }
    var value: Int { count }
}

func makeMusicV2Client(keychain: KeychainStoring = MusicV2CountingKeychain()) -> MusicV2Client {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MusicV2URLProtocol.self]
    let base = URL(string: "https://music-v2.test")!
    return MusicV2Client(apiClient: APIClient(
        config: AppConfig(apiBaseURL: base, siteBaseURL: base),
        signer: AuthSigner(keychain: keychain),
        session: URLSession(configuration: configuration)
    ))
}

final class MusicV2CountingKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock(); private var reads = 0
    var readCount: Int { lock.withLock { reads } }
    func string(for key: String) throws -> String? { lock.withLock { reads += 1 }; return "must-not-be-read" }
    func setString(_ value: String, for key: String) throws {}
    func remove(_ key: String) throws {}
}

final class MusicV2RequestCapture: @unchecked Sendable {
    private let lock = NSLock(); private var values: [URLRequest] = []
    func append(_ request: URLRequest) { lock.withLock { values.append(request) } }
    var requests: [URLRequest] { lock.withLock { values } }
}

final class MusicV2URLProtocol: URLProtocol {
    struct Reply { let status: Int; let body: Data; let headers: [String: String]; init(status: Int = 200, body: Data, headers: [String: String] = [:]) { self.status = status; self.body = body; self.headers = headers } }
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Reply)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.handler?(request) ?? .init(status: 500, body: Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers.merging(["Content-Type": "application/json"]) { first, _ in first })!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !reply.body.isEmpty { client?.urlProtocol(self, didLoad: reply.body) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

enum MusicV2Fixtures {
    static let artistBrief = #"{"name":"Artist","id":"netease:artist:1","artwork":null}"#
    static let availability = #"{"status":"playable","reason":null,"maxQuality":"standard"}"#
    static var track: String { #"{"id":"netease:track:1","source":"netease","title":"Track","artists":[\#(artistBrief)],"availability":\#(availability),"album":null,"durationMs":0,"artwork":null,"mvId":null,"aliases":[],"translatedTitle":null}"# }
    static var artist: String { #"{"id":"netease:artist:1","source":"netease","name":"Artist","aliases":[],"artwork":null,"description":null,"trackCount":0,"albumCount":0,"mvCount":0}"# }
    static var album: String { #"{"id":"netease:album:1","source":"netease","title":"Album","artists":[\#(artistBrief)],"artwork":null,"releaseDate":null,"trackCount":0,"company":null,"description":null,"editionLabel":null}"# }
    static var mv: String { #"{"id":"netease:mv:1","title":"MV","artists":[\#(artistBrief)],"artwork":null,"durationMs":null,"playCount":null}"# }
    static let source = #"{"kind":"sharedAlgorithmic","audience":"shared","personalized":false,"catalogSource":"netease","label":null,"ownerId":null}"#
    static let providerPlaylist = #"{"id":"netease:playlist:1","origin":"provider","title":"Playlist","tags":[],"isRanking":false,"artwork":null,"description":null,"trackCount":0,"playCount":null,"creator":null,"updatedAt":null,"updateFrequency":null}"#
    static var trackPage: String { #"{"items":[\#(track)],"offset":0,"limit":20,"hasMore":false,"total":1,"nextOffset":null}"# }
    static var albumPage: String { #"{"items":[\#(album)],"offset":0,"limit":20,"hasMore":false,"total":1,"nextOffset":null}"# }
    static var mvPage: String { #"{"items":[\#(mv)],"offset":0,"limit":20,"hasMore":false,"total":1,"nextOffset":null}"# }
    static var membership: String { #"{"playlistId":"netease:playlist:1","trackId":"netease:track:1","position":0,"track":null,"relationId":null,"addedAt":null}"# }
    static var membershipPage: String { #"{"items":[\#(membership)],"offset":0,"limit":50,"hasMore":false,"total":1,"nextOffset":null}"# }

    static func response(for request: URLRequest) -> MusicV2URLProtocol.Reply {
        guard request.httpMethod == "GET" else { return .init(status: 204, body: Data()) }
        let path = request.url!.path
        let body: String
        switch path {
        case "/user/music/v2/home": body = #"{"sections":[],"generatedAt":"2026-09-03T08:00:00Z"}"#
        case "/user/music/v2/search": body = #"{"query":"q","scope":"tracks","sections":[{"scope":"tracks","status":"loaded","items":\#(trackPage),"error":null}],"best":null}"#
        case "/user/music/v2/search/suggest": body = #"{"keywords":[],"tracks":[],"artists":[],"playlists":[]}"#
        case "/user/music/v2/search/hot": body = #"{"items":[],"source":\#(source)}"#
        case "/user/music/v2/tracks": body = #"{"items":[\#(track)]}"#
        case "/user/music/v2/tracks/playback": return .init(body: Data(#"{"items":[]}"#.utf8), headers: ["X-Setu-Playback-Contract": "3.0.0"])
        case let p where p.hasSuffix("/playback"):
            return .init(body: Data(#"{"kind":"denied","trackId":"netease:track:1","availability":{"status":"unavailable","reason":"Unavailable","maxQuality":null}}"#.utf8), headers: ["X-Setu-Playback-Contract": "3.0.0"])
        case let p where p.hasSuffix("/lyrics"): body = #"{"trackId":"netease:track:1","kind":"none","lines":[],"hasTranslation":false,"contributors":[]}"#
        case let p where p.hasSuffix("/similar"): body = #"{"tracks":[],"playlists":[],"source":\#(source)}"#
        case let p where p.contains("/artists/") && p.hasSuffix("/tracks"): body = trackPage
        case let p where p.contains("/artists/") && p.hasSuffix("/albums"): body = albumPage
        case let p where p.contains("/artists/") && p.hasSuffix("/mvs"): body = mvPage
        case let p where p.contains("/artists/"): body = #"{"artist":\#(artist),"topTracks":[],"albums":[],"mvs":[],"similar":[]}"#
        case let p where p.contains("/albums/"): body = #"{"album":\#(album),"tracks":[]}"#
        case let p where p.contains("/playlists/") && p.hasSuffix("/tracks"): body = membershipPage
        case let p where p.contains("/playlists/"): body = #"{"playlist":\#(providerPlaylist),"memberships":\#(membershipPage)}"#
        case "/user/music/v2/rankings": body = #"{"items":[],"source":\#(source)}"#
        case "/user/music/v2/recommend/tracks": body = #"{"tracks":[],"source":\#(source)}"#
        case "/user/music/v2/recommend/playlists": body = #"{"items":[],"source":\#(source)}"#
        case "/user/music/v2/new-releases/tracks": body = #"{"area":"all","items":\#(trackPage),"source":\#(source)}"#
        case "/user/music/v2/new-releases/albums": body = #"{"area":"all","items":\#(albumPage),"source":\#(source)}"#
        case "/user/music/v2/radio/fm": body = #"{"tracks":[],"source":\#(source)}"#
        case "/user/music/v2/library": body = #"{"ownerId":"setu:user:u1","likedTrackCount":0,"savedPlaylistCount":0,"historyCount":0,"ownedPlaylistCount":0,"recentHistory":[],"ownedPlaylists":[],"savedPlaylists":[]}"#
        case "/user/music/v2/library/liked-tracks": body = #"{"items":[],"offset":0,"limit":20,"hasMore":false,"total":0,"nextOffset":null}"#
        case "/user/music/v2/library/favorite-playlists": body = #"{"items":[],"offset":0,"limit":20,"hasMore":false,"total":0,"nextOffset":null}"#
        case "/user/music/v2/library/history": body = #"{"items":[],"offset":0,"limit":20,"hasMore":false,"total":0,"nextOffset":null}"#
        default: body = track
        }
        return .init(body: Data(body.utf8))
    }
}
