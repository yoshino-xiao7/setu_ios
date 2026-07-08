import Foundation
import XCTest
@testable import SetuIOSCore

final class MusicClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        MusicClientMockURLProtocol.handler = nil
    }

    func testRecommendationEndpointsMatchFrontendMusicAPI() async throws {
        let capturedRequests = MusicClientRequestProbe()
        let session = URLSession(
            configuration: .musicClientMock { request in
                Task {
                    await capturedRequests.capture(request)
                }
                switch request.url?.path {
                case "/user/music/personalized":
                    return #"{"result":[{"id":1,"name":"推荐歌单","picUrl":"https://example.com/cover.jpg","playCount":12000,"description":"精选"}]}"#
                case "/user/music/personalized/newsong":
                    return #"{"result":[{"id":2,"name":"新歌","artists":[],"album":{"id":3,"name":"专辑"}}]}"#
                case "/user/music/recommend/songs":
                    return #"{"data":{"dailySongs":[{"id":4,"name":"每日推荐","artists":[],"album":{"id":5,"name":"专辑"}}]}}"#
                case "/user/music/playlist/track/all":
                    return #"{"songs":[{"id":6,"name":"歌单歌曲","artists":[],"album":{"id":7,"name":"专辑"}}]}"#
                default:
                    return "{}"
                }
            }
        )
        let client = MusicClient(apiClient: makeAPIClient(session: session))

        let playlists = try await client.personalizedPlaylists(limit: 6)
        let newSongs = try await client.personalizedNewSongs()
        let dailySongs = try await client.recommendSongs()
        let tracks = try await client.playlistTracks(id: 123, limit: 50)

        XCTAssertEqual(playlists.result.first?.name, "推荐歌单")
        XCTAssertEqual(newSongs.result.first?.name, "新歌")
        XCTAssertEqual(dailySongs.data.dailySongs.first?.name, "每日推荐")
        XCTAssertEqual(tracks.songs.first?.name, "歌单歌曲")

        let urls = await capturedRequests.urls
        XCTAssertTrue(urls.contains("https://api.example.com/user/music/personalized?limit=6"))
        XCTAssertTrue(urls.contains("https://api.example.com/user/music/personalized/newsong"))
        XCTAssertTrue(urls.contains("https://api.example.com/user/music/recommend/songs"))
        XCTAssertTrue(urls.contains("https://api.example.com/user/music/playlist/track/all?id=123&limit=50"))
    }

    func testSecureURLStringUpgradesHTTPAndAddsArtworkSizeForNeteaseCovers() {
        let url = secureURLString(
            "http://p3.music.126.net/abc/109951.jpg",
            artworkSize: .lockScreen
        )

        XCTAssertEqual(url, "https://p3.music.126.net/abc/109951.jpg?param=400y400")
    }

    func testSecureURLStringPreservesQueryAndReplacesExistingArtworkParam() {
        let url = secureURLString(
            "http://p4.music.126.net/cover.jpg?foo=bar&param=80y80",
            artworkSize: .thumbnail
        )

        XCTAssertEqual(url, "https://p4.music.126.net/cover.jpg?foo=bar&param=200y200")
    }

    func testSecureURLStringDoesNotAddArtworkParamToPlaybackURL() {
        let url = secureURLString("http://m701.music.126.net/song.mp3")

        XCTAssertEqual(url, "https://m701.music.126.net/song.mp3")
    }

    func testMusicSongCoverURLStringUsesSecureArtworkURL() throws {
        let data = Data(#"{"id":1,"name":"歌","artists":[],"album":{"id":2,"name":"专辑","picUrl":"http://p3.music.126.net/album.jpg"}}"#.utf8)
        let song = try JSONDecoder().decode(MusicSong.self, from: data)

        XCTAssertEqual(song.coverURLString, "https://p3.music.126.net/album.jpg?param=400y400")
    }

    func testPlaylistAndHistoryCoverURLsUseSecureArtworkURL() throws {
        let playlistSongData = Data(#"{"id":1,"songId":2,"songName":"歌","artistName":"歌手","coverUrl":"http://p3.music.126.net/song.jpg","duration":180000}"#.utf8)
        let historyData = Data(#"{"id":3,"userId":4,"songId":5,"songName":"历史歌","artistName":"歌手","coverUrl":"http://p4.music.126.net/history.jpg","duration":200000,"playTime":"2026-07-08"}"#.utf8)

        let playlistSong = try JSONDecoder().decode(PlaylistSong.self, from: playlistSongData)
        let history = try JSONDecoder().decode(MusicHistoryRecord.self, from: historyData)

        XCTAssertEqual(playlistSong.coverUrl, "https://p3.music.126.net/song.jpg?param=400y400")
        XCTAssertEqual(history.coverUrl, "https://p4.music.126.net/history.jpg?param=400y400")
    }

    private func makeAPIClient(session: URLSession) -> APIClient {
        let keychain = MusicClientTestKeychain()
        try? keychain.setString("secret", for: "signSecret")
        return APIClient(
            config: AppConfig(
                apiBaseURL: URL(string: "https://api.example.com")!,
                siteBaseURL: URL(string: "https://example.com")!
            ),
            signer: AuthSigner(keychain: keychain),
            session: session
        )
    }
}

private actor MusicClientRequestProbe {
    private(set) var urls: [String] = []

    func capture(_ request: URLRequest) {
        urls.append(request.url?.absoluteString ?? "")
    }
}

private final class MusicClientTestKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func string(for key: String) throws -> String? {
        lock.withLock { values[key] }
    }

    func setString(_ value: String, for key: String) throws {
        lock.withLock {
            values[key] = value
        }
    }

    func remove(_ key: String) throws {
        _ = lock.withLock {
            values.removeValue(forKey: key)
        }
    }
}

private final class MusicClientMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> String)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body = Self.handler?(request) ?? "{}"
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLSessionConfiguration {
    static func musicClientMock(handler: @escaping (URLRequest) -> String) -> URLSessionConfiguration {
        MusicClientMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MusicClientMockURLProtocol.self]
        return configuration
    }
}
