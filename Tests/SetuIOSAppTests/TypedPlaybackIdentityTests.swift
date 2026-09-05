import AVFoundation
import XCTest
@testable import SetuIOSCore
@testable import SetuIOSApp

@MainActor
final class TypedPlaybackIdentityTests: XCTestCase {
    override func tearDown() { MusicV2URLProtocol.handler = nil; super.tearDown() }

    func testExactIdentityDomainsAndVersionedCodec() throws {
        let identities: [MusicPlaybackIdentity] = [.legacy(1), .canonical(.init(rawValue: "netease:track:1")),
            .canonical(.init(rawValue: "netease:track:01")), .canonical(.init(rawValue: "future:track:A%2Fb")),
            .canonical(.init(rawValue: "future:track:a%2Fb"))]
        XCTAssertEqual(Set(identities).count, identities.count)
        XCTAssertEqual(try JSONDecoder().decode([MusicPlaybackIdentity].self, from: JSONEncoder().encode(identities)), identities)
        XCTAssertEqual(try JSONDecoder().decode(MusicPlaybackIdentity.self, from: Data("123".utf8)), .legacy(123))
        XCTAssertThrowsError(try JSONDecoder().decode(MusicPlaybackIdentity.self, from: Data(#"{"version":99,"kind":"canonical","value":"x"}"#.utf8)))
        XCTAssertNil(identities[1].legacyID)
    }

    func testCanonicalQueueKeepsNextPreviousRandomAndExplicitNext() throws {
        var q = PlaybackQueue()
        q.tracks = try ["opaque:A", "opaque:a", "opaque:C"].map(typedTrack)
        q.currentIndex = 0
        XCTAssertEqual(q.nextForPreparation()?.id, .canonical(.init(rawValue: "opaque:a")))
        XCTAssertEqual(q.target(from: 1, offset: -1, isAuto: false), 0)
        q.mode = .random
        let target = q.target(from: 0, offset: 1, isAuto: false, random: { _ in 1 })
        XCTAssertEqual(target, 2)
        XCTAssertEqual(q.target(from: 0, offset: 1, isAuto: true, random: { _ in XCTFail(); return 0 }), target)
        q.prioritizeNext(q.tracks[1].id)
        XCTAssertEqual(q.nextForPreparation()?.id, q.tracks[1].id)
    }

    func testTypedResolutionDeduplicatesPreservesOpaqueAndNeverUsesLegacyFallback() async throws {
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            return .init(body: typedSourceResponse(request), headers: ["X-Setu-Playback-Contract": "3.0.0"])
        }
        let resolver = PlaybackURLResolver(client: musicTestClient(), v2: makeMusicV2Client())
        let first = MusicPlaybackIdentity.canonical(.init(rawValue: "future:track:A%2Fb"))
        async let a = resolver.resolve(trackID: first, quality: .standard)
        async let b = resolver.resolve(trackID: first, quality: .standard)
        let sources = try await [a, b]
        XCTAssertTrue(sources.allSatisfy { $0.trackID == first })
        XCTAssertEqual(capture.requests.count, 1)
        XCTAssertTrue(capture.requests[0].url!.absoluteString.contains("future%3Atrack%3AA%252Fb"))
        _ = try await resolver.resolve(trackID: .canonical(.init(rawValue: "future:track:a%2Fb")), quality: .standard)
        XCTAssertEqual(capture.requests.count, 2)
        _ = try await resolver.resolve(trackID: first, quality: .standard, force: true)
        XCTAssertEqual(capture.requests.count, 3)
        await resolver.reset()
        _ = try await resolver.resolve(trackID: first, quality: .standard)
        XCTAssertEqual(capture.requests.count, 4)
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            return .init(status: 503, body: Data(#"{"code":"UPSTREAM_UNAVAILABLE","message":"Unavailable","retryable":true,"traceId":null}"#.utf8))
        }
        do { _ = try await resolver.resolve(trackID: first, quality: .exhigh, force: true); XCTFail() } catch {}
        XCTAssertEqual(capture.requests.count, 5, "V2 failure must not invoke legacy fallback")
    }

    func testTypedPlayerEntryQualitySkipRetryAndUserReset() async throws {
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in capture.append(request); return .init(body: typedSourceResponse(request), headers: ["X-Setu-Playback-Contract": "3.0.0"]) }
        let player = MusicPlaybackController(persistsPlayback: false)
        defer { player.stop() }
        player.urlResolver = PlaybackURLResolver(client: musicTestClient(), v2: makeMusicV2Client())
        let tracks = try ["opaque:A", "opaque:B"].map(typedTrack)
        let played = await player.play(track: tracks[0], in: tracks, context: .album(id: "opaque:album", label: "Album"))
        player.pause()
        XCTAssertTrue(played)
        let engine = try XCTUnwrap(player.player)
        let changed = await player.setAudioQuality(.higher)
        XCTAssertFalse(changed, "Unplayable replacement must preserve the accepted quality")
        XCTAssertTrue(capture.requests.contains { $0.url!.query?.contains("allowFallback=false") == true })
        let local = try playbackWave()
        defer { try? FileManager.default.removeItem(at: local) }
        player.play(url: local, track: tracks[0], queueTracks: tracks)
        player.pause()
        player.resolveQualityURL = { track, _ in
            XCTAssertEqual(track.id, tracks[0].id)
            return .success(local)
        }
        let localChanged = await player.setAudioQuality(.higher)
        XCTAssertTrue(localChanged)
        player.resolveQualityURL = nil
        player.pause()
        await player.userSkip(by: 1); player.pause()
        XCTAssertEqual(player.currentTrack?.id, tracks[1].id)
        await player.retryCurrent(); player.pause()
        XCTAssertTrue(player.player === engine)
        XCTAssertTrue(capture.requests.allSatisfy { $0.url!.path.contains("/user/music/v2/tracks/") })
        XCTAssertTrue(capture.requests.contains { $0.url!.path.contains("opaque:B") })
        player.resetForUserChange()
        XCTAssertNil(player.currentTrack)
        XCTAssertTrue(player.queueTracks.isEmpty)
    }

    func testTypedFailureRecoveryKeepsIdentityAndDoesNotAddLegacyFallback() async throws {
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            return .init(status: 503, body: Data(#"{"code":"UPSTREAM_UNAVAILABLE","message":"Unavailable","retryable":true,"traceId":null}"#.utf8))
        }
        let player = MusicPlaybackController(persistsPlayback: false)
        defer { player.stop() }
        player.urlResolver = PlaybackURLResolver(client: musicTestClient(), v2: makeMusicV2Client())
        let local = try playbackWave()
        defer { try? FileManager.default.removeItem(at: local) }
        let track = try typedTrack("future:track:A%2Fb")
        player.play(url: local, track: track)
        let item = try XCTUnwrap(player.player?.currentItem)
        player.handleItemFailure(item, error: URLError(.timedOut))
        player.handleItemFailure(item, error: URLError(.timedOut))
        for _ in 0..<100 where player.playbackError == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNotNil(player.playbackError)
        XCTAssertFalse(player.isBuffering)
        XCTAssertEqual(capture.requests.count, 1)
        XCTAssertTrue(capture.requests[0].url!.absoluteString.contains("future%3Atrack%3AA%252Fb"))
        XCTAssertEqual(player.currentTrack?.id, track.id)
    }

    func testReplacementMediaFailureDoesNotStartAnotherForcedResolution() async throws {
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            return .init(body: typedSourceResponse(request), headers: ["X-Setu-Playback-Contract": "3.0.0"])
        }
        let player = MusicPlaybackController(persistsPlayback: false)
        defer { player.stop() }
        player.urlResolver = PlaybackURLResolver(client: musicTestClient(), v2: makeMusicV2Client())
        let local = try playbackWave()
        defer { try? FileManager.default.removeItem(at: local) }
        player.play(url: local, track: try typedTrack("netease:track:1"))
        let original = try XCTUnwrap(player.player?.currentItem)
        player.handleItemFailure(original, error: URLError(.timedOut))
        for _ in 0..<100 where player.player?.currentItem === original { try await Task.sleep(nanoseconds: 10_000_000) }
        let replacement = try XCTUnwrap(player.player?.currentItem)
        XCTAssertFalse(replacement === original)
        player.handleItemFailure(replacement, error: URLError(.timedOut))
        XCTAssertNotNil(player.playbackError)
        XCTAssertEqual(capture.requests.count, 1)
    }

    func testTypedResolutionResetRejectsOldUserInFlight() async throws {
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            Thread.sleep(forTimeInterval: 0.08)
            return .init(body: typedSourceResponse(request), headers: ["X-Setu-Playback-Contract": "3.0.0"])
        }
        let resolver = PlaybackURLResolver(client: musicTestClient(), v2: makeMusicV2Client())
        let id = MusicPlaybackIdentity.canonical(.init(rawValue: "opaque:owner"))
        let old = Task { try await resolver.resolve(trackID: id, quality: .standard) }
        for _ in 0..<100 where capture.requests.isEmpty { try await Task.sleep(nanoseconds: 1_000_000) }
        await resolver.reset()
        do { _ = try await old.value; XCTFail("Old user result must be discarded") } catch {}
        _ = try await resolver.resolve(trackID: id, quality: .standard)
        XCTAssertEqual(capture.requests.count, 2)
    }

    func testTypedPreparedNextRequiresExactIdentity() async throws {
        MusicV2URLProtocol.handler = { .init(body: typedSourceResponse($0), headers: ["X-Setu-Playback-Contract": "3.0.0"]) }
        let resolver = PlaybackURLResolver(client: musicTestClient(), v2: makeMusicV2Client())
        let url = try playbackWave()
        defer { try? FileManager.default.removeItem(at: url) }
        let preparer = NextItemPreparer(makeItem: { _ in AVPlayerItem(url: url) })
        let first = MusicPlaybackIdentity.canonical(.init(rawValue: "opaque:A"))
        await preparer.prepare(trackID: first, quality: .standard, resolver: resolver)
        let item = try XCTUnwrap(preparer.prepared?.item)
        XCTAssertNil(preparer.consume(trackID: .canonical(.init(rawValue: "opaque:a")), quality: .standard))
        XCTAssertTrue(preparer.consume(trackID: first, quality: .standard)?.item === item)
    }

    func testTypedSnapshotRoundTripOldIntCorruptionAndOwnerIsolation() async throws {
        let suite = "typed-snapshot-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlaybackSnapshotStore(enabled: true, preferences: defaults)
        let track = try typedTrack("future:track:A%2Fb")
        let snapshot = PlaybackSnapshotStore.Snapshot(userID: 9, track: track, context: .singleTrack(trackID: track.contextTrackID, label: nil), queueTracks: [track], currentQueueIndex: 0, currentTimeSeconds: 7, playMode: .loop, updatedAt: Date())
        store.save(snapshot); await store.waitForWrites()
        XCTAssertEqual(store.restore(for: 9)?.track.id, track.id)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        var old = try XCTUnwrap(json["track"] as? [String: Any]); old["id"] = 42
        json["track"] = old; json["queueTracks"] = [old]
        let key = PlaybackSnapshotStore.snapshotKey(userID: 9)
        defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: key)
        XCTAssertEqual(store.restore(for: 9)?.track.id, .legacy(42))
        XCTAssertEqual(store.restore(for: 9)?.currentTimeSeconds, 7)
        defaults.set(defaults.data(forKey: key), forKey: PlaybackSnapshotStore.snapshotKey(userID: 8))
        XCTAssertNil(store.restore(for: 8))
        old["id"] = ["version": 99, "kind": "canonical", "value": "bad"]
        json["track"] = old
        defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: key)
        XCTAssertNil(store.restore(for: 9))
    }
}

func typedTrack(_ id: String) throws -> MusicPlaybackTrack {
    MusicPlaybackTrack(track: try JSONDecoder().decode(MusicV2Track.self, from: Data(MusicV2Fixtures.track.replacingOccurrences(of: "netease:track:1", with: id).utf8)))
}

func typedSourceResponse(_ request: URLRequest) -> Data {
    let id = request.url!.pathComponents.dropLast().last!
    let level = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "level" }?.value ?? "standard"
    let object: [String: Any] = ["kind": "success", "source": ["trackId": id, "url": "https://example.invalid/audio.mp3", "requestedQuality": level, "actualQuality": level,
        "refreshAt": "2099-01-01T00:00:00Z", "sourceExpiresAt": NSNull(), "bitrate": NSNull(), "sizeBytes": NSNull(), "format": NSNull(), "notice": NSNull()]]
    return try! JSONSerialization.data(withJSONObject: object)
}
