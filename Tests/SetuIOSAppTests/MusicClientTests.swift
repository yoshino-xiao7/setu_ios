import Foundation
import XCTest
@testable import SetuIOSApp
@testable import SetuIOSCore
@testable import SetuIOSApp

final class MusicClientTests: XCTestCase {
    func testEveryAudioQualityIsSentToPlaybackEndpoint() async throws {
        for quality in MusicAudioQuality.allCases {
            let session = URLSession(configuration: .musicClientMock { request in
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
                XCTAssertEqual(request.url?.path, "/user/music/url")
                XCTAssertEqual(query?.first(where: { $0.name == "level" })?.value, quality.rawValue)
                return "{\"data\":[]}"
            })
            _ = try await MusicClient(apiClient: makeAPIClient(session: session)).url(songID: 7, level: quality.rawValue)
        }
    }

    func testBatchPlaybackURLSendsCommaSeparatedIDsAndDecodesExpiry() async throws {
        let session = URLSession(configuration: .musicClientMock { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(query?.first(where: { $0.name == "id" })?.value, "7,8")
            return #"{"data":[{"id":8,"expi":1200},{"id":7,"expi":60}]}"#
        })
        let response = try await MusicClient(apiClient: makeAPIClient(session: session)).url(songIDs: [7, 8])
        XCTAssertEqual(response.data?.map(\.id), [8, 7])
        XCTAssertEqual(response.data?.first(where: { $0.id == 7 })?.expi, 60)
    }

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

    func testPersonalizedNewSongDecodesNestedSongPayload() async throws {
        let session = URLSession(
            configuration: .musicClientMock { request in
                XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/user/music/personalized/newsong")
                return #"""
                {
                  "result": [
                    {
                      "id": 1001,
                      "name": "甲乙丙丁",
                      "picUrl": "http://p3.music.126.net/recommend-cover.jpg",
                      "song": {
                        "id": 1001,
                        "name": "甲乙丙丁",
                        "artists": [
                          { "id": 1, "name": "许志安" },
                          { "id": 2, "name": "张学友" }
                        ],
                        "album": {
                          "id": 88,
                          "name": "拉阔音乐压轴篇98",
                          "picUrl": "http://p4.music.126.net/album-cover.jpg"
                        },
                        "duration": 251000,
                        "mv": 0
                      }
                    }
                  ]
                }
                """#
            }
        )
        let client = MusicClient(apiClient: makeAPIClient(session: session))

        let response = try await client.personalizedNewSongs()
        let song = try XCTUnwrap(response.result.first)

        XCTAssertEqual(song.id, 1001)
        XCTAssertEqual(song.name, "甲乙丙丁")
        XCTAssertEqual(song.artistNames, "许志安 / 张学友")
        XCTAssertEqual(song.albumName, "拉阔音乐压轴篇98")
        XCTAssertEqual(song.durationMilliseconds, 251000)
        XCTAssertEqual(song.coverURLString, "https://p3.music.126.net/recommend-cover.jpg?param=400y400")
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

    func testUnavailableMusicMessagesMapUpstreamDiagnosticsToProductLanguage() throws {
        let copyrightResponse = try JSONDecoder().decode(
            MusicUrlResponse.self,
            from: Data(#"{"data":[{"id":1,"url":null,"playability":"UNAVAILABLE","playabilityReason":"NO_COPYRIGHT worker=music-3"}]}"#.utf8)
        )
        let unknownResponse = try JSONDecoder().decode(
            MusicUrlResponse.self,
            from: Data(#"{"data":[],"message":"upstream timeout at node music-7"}"#.utf8)
        )
        let memberResponse = try JSONDecoder().decode(
            MusicUrlResponse.self,
            from: Data(#"{"data":[{"id":2,"url":null,"playability":"VIP_ONLY"}]}"#.utf8)
        )

        XCTAssertEqual(copyrightResponse.unavailableMessage, "这首歌受版权限制，暂时无法播放")
        XCTAssertEqual(unknownResponse.unavailableMessage, "音乐服务暂时无法提供这首歌，请稍后再试")
        XCTAssertEqual(memberResponse.unavailableMessage, "这首歌需要音乐平台会员，暂时无法播放完整版")
        XCTAssertFalse(copyrightResponse.unavailableMessage.contains("worker"))
        XCTAssertFalse(unknownResponse.unavailableMessage.contains("upstream"))
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

    func testAddHistoryRequestPostsPlaybackTrackPayload() async throws {
        let capturedRequests = MusicClientRequestProbe()
        let captured = expectation(description: "history request recorded")
        let session = URLSession(
            configuration: .musicClientMock { request in
                Task {
                    await capturedRequests.capture(request)
                    captured.fulfill()
                }
                return #""ok""#
            }
        )
        let client = MusicClient(apiClient: makeAPIClient(session: session))

        try await client.addHistory(
            AddMusicHistoryRequest(
                songId: 42,
                songName: "自动连播歌曲",
                artistName: "歌手",
                albumName: "专辑",
                coverUrl: "https://p3.music.126.net/cover.jpg?param=400y400",
                duration: 188000
            )
        )

        await fulfillment(of: [captured], timeout: 2)
        let requests = await capturedRequests.requests
        XCTAssertEqual(requests.first?.method, "POST")
        XCTAssertEqual(requests.first?.url, "https://api.example.com/user/music/history")
        let body = try XCTUnwrap(requests.first?.body)
        XCTAssertTrue(body.contains(#""songId":42"#))
        XCTAssertTrue(body.contains(#""songName":"自动连播歌曲""#))
        XCTAssertTrue(body.contains(#""duration":188000"#))
    }

    func testAddPlaylistSongToAnotherPlaylistPostsSongPayload() async throws {
        let capturedRequests = MusicClientRequestProbe()
        let session = URLSession(
            configuration: .musicClientMock { request in
                Task {
                    await capturedRequests.capture(request)
                }
                return #""ok""#
            }
        )
        let client = MusicClient(apiClient: makeAPIClient(session: session))
        let song = try JSONDecoder().decode(
            PlaylistSong.self,
            from: Data(#"{"id":1,"songId":77,"songName":"歌单歌曲","artistName":"歌手","albumName":"专辑","coverUrl":"http://p3.music.126.net/song.jpg","duration":210000}"#.utf8)
        )

        try await client.add(song: song, toPlaylist: 9)

        let requests = await capturedRequests.requests
        XCTAssertEqual(requests.first?.method, "POST")
        XCTAssertEqual(requests.first?.url, "https://api.example.com/user/playlists/9/songs")
        let body = try XCTUnwrap(requests.first?.body)
        XCTAssertTrue(body.contains(#""songId":77"#))
        XCTAssertTrue(body.contains(#""songName":"歌单歌曲""#))
        XCTAssertTrue(body.contains(#""duration":210000"#))
    }

    func testMvUrlAcceptsArrayPayloadLikeFrontendMvPlayback() async throws {
        let session = URLSession(
            configuration: .musicClientMock { request in
                XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/user/music/mv/url?id=5436712")
                return #"{"code":200,"data":[{"id":5436712,"url":"http://example.com/mv.mp4","r":720,"size":300000,"br":720}]}"#
            }
        )
        let client = MusicClient(apiClient: makeAPIClient(session: session))

        let response = try await client.mvUrl(id: 5_436_712)

        XCTAssertEqual(response.data?.id, 5_436_712)
        XCTAssertEqual(response.data?.httpsURLString, "https://example.com/mv.mp4")
    }

    func testMvUrlAcceptsRawPayloadLikeFrontendMvPlayback() throws {
        let data = Data(#"{"id":5436712,"url":"//example.com/mv.mp4","r":720,"size":300000,"br":720}"#.utf8)

        let response = try JSONDecoder().decode(MusicMvUrlResponse.self, from: data)

        XCTAssertEqual(response.data?.id, 5_436_712)
        XCTAssertEqual(response.data?.httpsURLString, "https://example.com/mv.mp4")
    }

    @MainActor
    func testSearchSessionNetworkUsesTenItemOffsetsAndCachesRepeatedKeyword() async throws {
        let probe = MusicClientRequestProbe()
        let received = expectation(description: "three search HTTP requests")
        received.expectedFulfillmentCount = 3
        let session = URLSession(configuration: .musicClientMock { request in
            Task { await probe.capture(request); received.fulfill() }
            let params = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let offset = Int(params.first { $0.name == "offset" }!.value!)!
            let songs = (offset..<offset + 10).map { "{\"id\":\($0),\"name\":\"歌曲\($0)\"}" }.joined(separator: ",")
            return "{\"result\":{\"songs\":[\(songs)],\"songCount\":30}}"
        })
        let repo = MusicRepository(client: MusicClient(apiClient: makeAPIClient(session: session)))
        let search = MusicSearchSession(repository: repo, historyDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        search.query = "周杰伦"; await search.submit()
        XCTAssertEqual(search.pager.items.count, 10)
        await search.submit()
        await search.loadMore(near: 7)
        search.query = "陈"; await search.submit()
        search.query = "周杰伦"; await search.submit()
        await fulfillment(of: [received], timeout: 2)
        let requests = await probe.urls
        XCTAssertEqual(requests.count, 3)
        let queries = requests.map { URLComponents(string: $0)!.queryItems! }
        XCTAssertEqual(queries.map { $0.first { $0.name == "keywords" }!.value! }, ["周杰伦", "周杰伦", "陈"])
        XCTAssertEqual(queries.map { $0.first { $0.name == "offset" }!.value! }, ["0", "10", "0"])
        XCTAssertTrue(queries.allSatisfy { $0.first { $0.name == "limit" }?.value == "10" })
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
    private(set) var requests: [CapturedMusicClientRequest] = []

    func capture(_ request: URLRequest) {
        urls.append(request.url?.absoluteString ?? "")
        requests.append(
            CapturedMusicClientRequest(
                method: request.httpMethod ?? "GET",
                url: request.url?.absoluteString ?? "",
                body: Self.bodyString(from: request)
            )
        )
    }

    private static func bodyString(from request: URLRequest) -> String? {
        if let body = request.httpBody {
            return String(data: body, encoding: .utf8)
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return String(data: data, encoding: .utf8)
    }
}

private struct CapturedMusicClientRequest: Sendable {
    let method: String
    let url: String
    let body: String?
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

@MainActor
final class MusicQualitySelectionTests: XCTestCase {
    private func makeSilentWave() throws -> URL {
        // A real local audio source exercises AVFoundation validation without network or sound.
        let sampleBytes = 8_000 * 2 * 100
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        append(UInt32(36 + sampleBytes))
        data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(8_000))
        append(UInt32(16_000))
        append(UInt16(2))
        append(UInt16(16))
        data.append(Data("data".utf8))
        append(UInt32(sampleBytes))
        data.append(Data(repeating: 0, count: sampleBytes))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("setu-quality-\(UUID().uuidString).wav")
        try data.write(to: url)
        return url
    }

    private func makePlayer() throws -> MusicPlaybackController {
        let songs = try JSONDecoder().decode([MusicSong].self, from: Data(#"[{"id":7,"name":"音质测试","artists":[],"album":{"id":1,"name":"测试"},"duration":180000}]"#.utf8))
        let player = MusicPlaybackController(persistsPlayback: false)
        player.configurePreview(songs: songs)
        return player
    }

    func testPreferenceSurvivesControllerRecreationWithoutPlayback() async throws {
        let suite = "setu-quality-test-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let player = MusicPlaybackController(preferences: preferences)
        XCTAssertEqual(player.audioQuality, .exhigh)
        let changed = await player.setAudioQuality(.hires)
        XCTAssertTrue(changed)
        XCTAssertEqual(MusicPlaybackController(preferences: preferences).audioQuality, .hires)
    }

    func testUnavailableQualityKeepsPreferenceTrackPositionAndPause() async throws {
        let player = try makePlayer()
        let originalTime = player.currentTimeSeconds
        player.resolveQualityURL = { track, quality in
            XCTAssertEqual(track.id, 7)
            XCTAssertEqual(quality, .lossless)
            return .unavailable(UserFacingError(message: "该音质暂不可用"))
        }
        let changed = await player.setAudioQuality(.lossless)
        XCTAssertFalse(changed)
        XCTAssertEqual(player.audioQuality, .exhigh)
        XCTAssertEqual(player.currentTrack?.id, 7)
        XCTAssertEqual(player.currentTimeSeconds, originalTime)
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isChangingQuality)
        guard case .failure(let error) = player.feedback else { return XCTFail("Expected recoverable failure") }
        XCTAssertEqual(error.action, .retry)
    }

    func testSuccessfulQualityChangeRetainsPausedPositionAndQueue() async throws {
        let player = try makePlayer()
        let audioURL = try makeSilentWave()
        defer { player.stop(); try? FileManager.default.removeItem(at: audioURL) }
        let originalTime = player.currentTimeSeconds
        let originalQueue = player.queueTracks
        player.resolveQualityURL = { _, quality in
            XCTAssertEqual(quality, .higher)
            return .success(audioURL)
        }
        let changed = await player.setAudioQuality(.higher)
        XCTAssertTrue(changed)
        XCTAssertEqual(player.audioQuality, .higher)
        XCTAssertEqual(player.currentTimeSeconds, originalTime)
        XCTAssertEqual(player.queueTracks.map(\.id), originalQueue.map(\.id))
        XCTAssertFalse(player.isPlaying, "Changing quality must not start a paused track")
        XCTAssertFalse(player.isChangingQuality)
    }

    func testUnplayableReplacementKeepsExistingTrackAndPreference() async throws {
        let player = try makePlayer()
        let time = player.currentTimeSeconds
        player.resolveQualityURL = { _, _ in
            .success(URL(fileURLWithPath: "/tmp/setu-quality-missing-\(UUID().uuidString).m4a"))
        }
        let changed = await player.setAudioQuality(.hires)
        XCTAssertFalse(changed)
        XCTAssertEqual(player.audioQuality, .exhigh)
        XCTAssertEqual(player.currentTrack?.id, 7)
        XCTAssertEqual(player.currentTimeSeconds, time)
        XCTAssertFalse(player.isPlaying)
    }

    func testLateQualityResponseCannotRestoreStoppedPlayback() async throws {
        let player = try makePlayer()
        var response: CheckedContinuation<MusicURLResolution, Never>?
        player.resolveQualityURL = { _, _ in
            await withCheckedContinuation { response = $0 }
        }
        let change = Task { await player.setAudioQuality(.hires) }
        while response == nil { await Task.yield() }
        player.stop()
        response?.resume(returning: .success(URL(fileURLWithPath: "/tmp/setu-quality-test-unused-audio.m4a")))
        let changed = await change.value
        XCTAssertFalse(changed)
        XCTAssertNil(player.currentTrack)
        XCTAssertEqual(player.audioQuality, .exhigh)
        XCTAssertFalse(player.isChangingQuality)
    }

    func testNewTrackResolutionCancelsPendingQualityChange() async throws {
        let player = try makePlayer()
        var response: CheckedContinuation<MusicURLResolution, Never>?
        player.resolveQualityURL = { _, _ in
            await withCheckedContinuation { response = $0 }
        }
        let change = Task { await player.setAudioQuality(.lossless) }
        while response == nil { await Task.yield() }
        player.cancelPendingQualityChange()
        response?.resume(returning: .success(URL(fileURLWithPath: "/tmp/setu-quality-test-unused-audio.m4a")))
        let changed = await change.value
        XCTAssertFalse(changed)
        XCTAssertEqual(player.audioQuality, .exhigh)
        XCTAssertEqual(player.currentTrack?.id, 7)
    }
}
