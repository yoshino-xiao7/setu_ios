import AVFoundation
import Observation
import XCTest
@testable import SetuIOSCore
@testable import SetuIOSApp

@MainActor
final class MusicPlaybackControllerTests: XCTestCase {
    private func fixture() throws -> (MusicPlaybackController, [MusicPlaybackTrack], URL, MusicTestCounter) {
        let url = try playbackWave()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let count = MusicTestCounter()
        let controller = MusicPlaybackController(persistsPlayback: false)
        controller.urlResolver = PlaybackURLResolver { ids, quality in
            _ = await count.next(); return try playbackResponse(ids: ids, quality: quality, url: url)
        }
        addTeardownBlock { await MainActor.run { controller.stop() } }
        return (controller, try playbackTracks(), url, count)
    }

    private func waitForSeek(_ controller: MusicPlaybackController) async {
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { !controller.isSeeking }
        }, object: nil)
        await fulfillment(of: [completed], timeout: 5)
        XCTAssertNil(controller.playbackError)
    }

    func testLyricSeekDoesNotPublishTargetBeforeAudioConfirms() async throws {
        let (controller, tracks, url, _) = try fixture()
        controller.play(url: url, track: tracks[0])
        let engine = try XCTUnwrap(controller.player)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { engine.currentItem?.status == .readyToPlay }
        }, object: nil)
        await fulfillment(of: [ready], timeout: 5)
        controller.pause()
        let confirmed = controller.currentTimeSeconds
        controller.seek(to: 120) // Same entry point as the lyric selection guide.
        XCTAssertEqual(controller.currentTimeSeconds, confirmed, "Do not move lyrics before audio seek completes")
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                abs(controller.currentTimeSeconds - 120) < 0.1 && abs(engine.currentTime().seconds - 120) < 0.1
            }
        }, object: nil)
        await fulfillment(of: [completed], timeout: 5)
        XCTAssertFalse(controller.isPlaying)
    }

    func testLatestLyricSeekWinsAndTrackReplacementCancelsOldSeek() async throws {
        let (controller, tracks, url, _) = try fixture()
        controller.play(url: url, track: tracks[0])
        controller.pause()
        controller.seek(to: 120)
        controller.seek(to: 45)
        await waitForSeek(controller)
        XCTAssertEqual(controller.currentTimeSeconds, 45, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(controller.player).currentTime().seconds, 45, accuracy: 0.1)
        XCTAssertFalse(controller.isPlaying)
        controller.seek(to: 100)
        controller.play(url: url, track: tracks[1])
        controller.pause()
        await Task.yield()
        XCTAssertEqual(controller.currentTrack?.id, tracks[1].id)
        XCTAssertFalse(controller.isSeeking)
        XCTAssertNil(controller.playbackError)
        XCTAssertLessThan(controller.currentTimeSeconds, 1)
    }

    func testActualAudioDurationReplacesShorterCatalogDuration() async throws {
        let url = try playbackWave() // Actual audio is 180 seconds.
        defer { try? FileManager.default.removeItem(at: url) }
        let coordinator = NowPlayingCoordinator()
        let controller = MusicPlaybackController(persistsPlayback: false, nowPlayingCoordinator: coordinator)
        defer { controller.stop() }
        let track = MusicPlaybackTrack(id: 99, title: "Duration", artist: "", album: "", coverURLString: nil,
                                       durationMilliseconds: 150_000, mvID: nil)
        controller.play(url: url, track: track)
        let engine = try XCTUnwrap(controller.player)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { engine.currentItem?.status == .readyToPlay }
        }, object: nil)
        await fulfillment(of: [ready], timeout: 5)
        controller.pause()
        controller.seek(to: 170)
        await waitForSeek(controller)
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { controller.currentTimeSeconds >= 169 }
        }, object: nil)
        await fulfillment(of: [advanced], timeout: 5)
        XCTAssertEqual(controller.durationSeconds, 180, accuracy: 0.01)
        XCTAssertLessThanOrEqual(controller.currentTimeSeconds, controller.durationSeconds)
        XCTAssertEqual(coordinator.metadata?.duration, 180)
        controller.seek(to: 175)
        await waitForSeek(controller)
        XCTAssertEqual(controller.currentTimeSeconds, 175)
        controller.stop()
        XCTAssertEqual(controller.durationSeconds, 0)
    }

    func testDurationResetsOnReplacementAndStallKeepsPlaybackStopped() async throws {
        let longURL = try playbackWave()
        let shortURL = try playbackWave(seconds: 60)
        defer {
            try? FileManager.default.removeItem(at: longURL)
            try? FileManager.default.removeItem(at: shortURL)
        }
        let coordinator = NowPlayingCoordinator()
        let controller = MusicPlaybackController(persistsPlayback: false, nowPlayingCoordinator: coordinator)
        defer { controller.stop() }
        let first = MusicPlaybackTrack(id: 98, title: "Long", artist: "", album: "", coverURLString: nil,
                                       durationMilliseconds: 300_000, mvID: nil)
        controller.play(url: longURL, track: first)
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { controller.durationSeconds == 180 }
        }, object: nil)
        await fulfillment(of: [loaded], timeout: 5)
        let next = MusicPlaybackTrack(id: 99, title: "Short", artist: "", album: "", coverURLString: nil,
                                      durationMilliseconds: 90_000, mvID: nil)
        controller.play(url: shortURL, track: next)
        XCTAssertEqual(controller.durationSeconds, 90, "New item uses its own catalog fallback")
        let replaced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { controller.durationSeconds == 60 }
        }, object: nil)
        await fulfillment(of: [replaced], timeout: 5)
        controller.pause()
        controller.seek(to: 70)
        await waitForSeek(controller)
        XCTAssertEqual(controller.currentTimeSeconds, 60)
        controller.seek(to: .infinity)
        XCTAssertEqual(controller.currentTimeSeconds, 60)
        controller.seek(to: 10)
        await waitForSeek(controller)
        let item = try XCTUnwrap(controller.player?.currentItem)
        for _ in 0..<3 {
            NotificationCenter.default.post(name: .AVPlayerItemPlaybackStalled, object: item)
        }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(controller.playbackError, "Stale stalled notifications while paused must not create a failure")
        XCTAssertFalse(controller.isPlaying)
        XCTAssertFalse(controller.isBuffering)
        XCTAssertEqual(controller.player?.rate, 0)
        XCTAssertEqual(coordinator.metadata?.playbackRate, 0)
        XCTAssertEqual(coordinator.metadata?.duration, 60)
        XCTAssertLessThanOrEqual(controller.currentTimeSeconds, controller.durationSeconds)
    }

    func testPlaybackActivatesAudioSessionAndAdvancesTime() async throws {
        let (controller, tracks, _, _) = try fixture()
        _ = await controller.play(track: tracks[0], in: [tracks[0]])
        let engine = try XCTUnwrap(controller.player)
        // Exercise the real session and AVPlayer, including device-only category validation.
        // A populated currentItem or the controller's playback intent cannot prove playback.
        let startedOrFailed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                MainActor.assumeIsolated {
                    controller.playbackError != nil || engine.currentTime().seconds > 0.1
                }
            }, object: nil
        )
        await fulfillment(of: [startedOrFailed], timeout: 10)
        XCTAssertNil(controller.playbackError)
        XCTAssertEqual(engine.timeControlStatus, .playing)
        XCTAssertGreaterThan(engine.currentTime().seconds, 0.1)
    }

    func testOnePlayerAcrossTracksPauseSeekQualityAndStop() async throws {
        let (controller, tracks, url, _) = try fixture()
        controller.play(url: url, track: tracks[0], queueTracks: tracks)
        let engine = try XCTUnwrap(controller.player)
        controller.pause(); controller.seek(to: 2); controller.resume()
        await controller.userSkip(by: 1)
        XCTAssertTrue(controller.player === engine)
        controller.pause()
        let changed = await controller.setAudioQuality(.higher)
        XCTAssertTrue(changed); XCTAssertTrue(controller.player === engine)
        controller.stop(); XCTAssertTrue(controller.player === engine); XCTAssertNil(engine.currentItem)
        controller.play(url: url, track: tracks[2]); XCTAssertTrue(controller.player === engine)
    }

    func testPreparedNextReusesExactItemAndSendsZeroURLRequests() async throws {
        let (controller, tracks, _, counter) = try fixture()
        _ = await controller.play(track: tracks[0], in: tracks)
        let resolver = try XCTUnwrap(controller.urlResolver)
        await controller.nextItemPreparer.prepare(trackID: 2, quality: .exhigh, resolver: resolver)
        let prepared = try XCTUnwrap(controller.nextItemPreparer.prepared)
        let before = await counter.count
        await controller.userSkip(by: 1)
        let after = await counter.count
        XCTAssertEqual(controller.currentTrack?.id, 2)
        XCTAssertTrue(controller.player?.currentItem === prepared.item)
        XCTAssertEqual(after, before, "Prepared hit must not even call URL transport")
    }

    func testUnpreparedNextUsesReliableSlowPath() async throws {
        let (controller, tracks, url, counter) = try fixture()
        controller.play(url: url, track: tracks[0], queueTracks: tracks)
        await controller.userSkip(by: 1)
        XCTAssertEqual(controller.currentTrack?.id, 2)
        XCTAssertNotNil(controller.player?.currentItem)
        let count = await counter.count; XCTAssertEqual(count, 1)
    }

    func testQueueEditsInvalidateChangedTargetButSeekKeepsPreparedItem() async throws {
        let (controller, tracks, url, _) = try fixture()
        controller.play(url: url, track: tracks[0], queueTracks: tracks)
        let resolver = try XCTUnwrap(controller.urlResolver)
        await controller.nextItemPreparer.prepare(trackID: 2, quality: .exhigh, resolver: resolver)
        let item = controller.nextItemPreparer.prepared?.item
        controller.seek(to: 1)
        XCTAssertTrue(controller.nextItemPreparer.prepared?.item === item)
        controller.removeQueuedTrack(tracks[1])
        XCTAssertNotEqual(controller.nextItemPreparer.prepared?.trackID, 2)
        controller.clearUpcomingTracks()
        XCTAssertNil(controller.nextItemPreparer.prepared)
        XCTAssertEqual(controller.queueTracks.map(\.id), [1])
    }

    func testPlayNextAndReorderUseNewTarget() async throws {
        let (controller, tracks, url, _) = try fixture()
        controller.play(url: url, track: tracks[0], queueTracks: tracks, playMode: .random)
        controller.playNext(tracks[2])
        await controller.userSkip(by: 1)
        XCTAssertEqual(controller.currentTrack?.id, 3)
        controller.setPlayMode(.sequence)
        controller.moveQueueTracks(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(controller.queueTracks.map(\.id), [2, 1, 3])
        await controller.userSkip(by: -1)
        XCTAssertEqual(controller.currentTrack?.id, 1)
        controller.removeQueuedTrack(tracks[0])
        XCTAssertNil(controller.currentTrack); XCTAssertNil(controller.player?.currentItem)
    }

    func testRandomPreparationMatchesActualNextItem() async throws {
        let (controller, tracks, url, _) = try fixture()
        controller.play(url: url, track: tracks[0], queueTracks: tracks, playMode: .random)
        controller.prepareNextIfNeeded()
        // Joining the same preparation is deterministic even if the URL request is still in flight.
        // Await the controller's owned preparation rather than guessing a random index.
        await controller.waitForNextPreparation()
        let prepared = try XCTUnwrap(controller.nextItemPreparer.prepared)
        await controller.userSkip(by: 1)
        XCTAssertEqual(controller.currentTrack?.id, prepared.trackID)
        XCTAssertTrue(controller.player?.currentItem === prepared.item)
    }

    func testSingleRepeatKeepsItemAndMakesNoURLRequest() async throws {
        let (controller, tracks, url, counter) = try fixture()
        controller.play(url: url, track: tracks[0], queueTracks: tracks, playMode: .single)
        let item = controller.player?.currentItem
        await controller.playbackEndReached()
        XCTAssertEqual(controller.currentTrack?.id, 1)
        XCTAssertTrue(controller.player?.currentItem === item)
        let count = await counter.count; XCTAssertEqual(count, 0)
        XCTAssertNil(controller.nextItemPreparer.prepared)
    }

    func testQualityChangeInvalidatesOldPreparedItem() async throws {
        let (controller, tracks, url, _) = try fixture()
        controller.play(url: url, track: tracks[0], queueTracks: tracks)
        await controller.nextItemPreparer.prepare(trackID: 2, quality: .exhigh, resolver: try XCTUnwrap(controller.urlResolver))
        let oldItem = controller.nextItemPreparer.prepared?.item
        controller.pause()
        let changed = await controller.setAudioQuality(.lossless)
        XCTAssertTrue(changed)
        XCTAssertNil(controller.nextItemPreparer.prepared)
        await controller.userSkip(by: 1)
        XCTAssertFalse(controller.player?.currentItem === oldItem)
        XCTAssertEqual(controller.audioQuality, .lossless)
    }

    func testFastNextAndPreviousRejectLateResolution() async throws {
        let (controller, tracks, url, _) = try fixture()
        let started = expectation(description: "B resolving"), gate = MusicTestGate()
        controller.urlResolver = PlaybackURLResolver { ids, quality in
            if ids == [2] { started.fulfill(); await gate.wait() }
            return try playbackResponse(ids: ids, quality: quality, url: url)
        }
        controller.play(url: url, track: tracks[0], queueTracks: tracks)
        let first = Task { await controller.userSkip(by: 1) }
        await fulfillment(of: [started], timeout: 2)
        await controller.userSkip(by: 1)
        XCTAssertEqual(controller.currentTrack?.id, 3)
        let item = controller.player?.currentItem
        await gate.open(); await first.value
        XCTAssertEqual(controller.currentTrack?.id, 3); XCTAssertTrue(controller.player?.currentItem === item)
        await controller.userSkip(by: -1)
        XCTAssertEqual(controller.currentTrack?.id, 2)
    }

    func testDirectSelectionSupersedesPreloadAndOldPlayRequest() async throws {
        let (controller, tracks, url, _) = try fixture()
        let started = expectation(description: "A resolving"), gate = MusicTestGate()
        controller.urlResolver = PlaybackURLResolver { ids, quality in
            if ids == [1] { started.fulfill(); await gate.wait() }
            return try playbackResponse(ids: ids, quality: quality, url: url)
        }
        let old = Task { await controller.play(track: tracks[0], in: tracks) }
        await fulfillment(of: [started], timeout: 2)
        _ = await controller.play(track: tracks[2], in: tracks)
        await gate.open(); let oldSucceeded = await old.value
        XCTAssertFalse(oldSucceeded); XCTAssertEqual(controller.currentTrack?.id, 3)
    }

    func testUserSwitchRejectsOldResolutionAndHistory() async throws {
        let (controller, tracks, url, _) = try fixture()
        let started = expectation(description: "old user"), gate = MusicTestGate()
        controller.urlResolver = PlaybackURLResolver { ids, quality in
            started.fulfill(); await gate.wait(); return try playbackResponse(ids: ids, quality: quality, url: url)
        }
        var history: [MusicPlaybackIdentity] = []
        controller.recordPlaybackHistory = { history.append($0.id) }
        let old = Task { await controller.play(track: tracks[0], in: tracks) }
        await fulfillment(of: [started], timeout: 2)
        controller.resetForUserChange()
        await gate.open(); let result = await old.value
        XCTAssertFalse(result); XCTAssertNil(controller.currentTrack); XCTAssertTrue(history.isEmpty)
        XCTAssertNil(controller.urlResolver)
    }

    func testHistoryIsAsynchronousAndDoesNotBlockNext() async throws {
        let (controller, tracks, _, _) = try fixture()
        let gate = MusicTestGate(), started = expectation(description: "history started")
        controller.recordPlaybackHistory = { track in
            if track.id == 1 { started.fulfill(); await gate.wait() }
        }
        let success = await controller.play(track: tracks[0], in: tracks)
        XCTAssertTrue(success)
        await fulfillment(of: [started], timeout: 2)
        await controller.userSkip(by: 1)
        XCTAssertEqual(controller.currentTrack?.id, 2)
        await gate.open()
    }

    func testTransientFailureReusesURLWithoutResolvingAndHasBoundedRetry() async throws {
        let (controller, tracks, url, counter) = try fixture()
        controller.play(url: url, track: tracks[0], queueTracks: [tracks[0]])
        let original = try XCTUnwrap(controller.player?.currentItem)
        controller.handleItemFailure(original, error: URLError(.timedOut))
        controller.handleItemFailure(original, error: URLError(.timedOut))
        let replaced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { controller.player?.currentItem !== original }
        }, object: nil)
        await fulfillment(of: [replaced], timeout: 3)
        controller.handleItemFailure(try XCTUnwrap(controller.player?.currentItem), error: URLError(.cannotConnectToHost))
        XCTAssertNotNil(controller.playbackError); XCTAssertFalse(controller.isBuffering); XCTAssertFalse(controller.isPlaying)
        let count = await counter.count; XCTAssertEqual(count, 0)
    }

    func testExpiredSourceRefreshFailureExitsWithoutLoop() async throws {
        let (controller, tracks, url, _) = try fixture()
        let counter = MusicTestCounter()
        controller.urlResolver = PlaybackURLResolver { _, _ in _ = await counter.next(); throw URLError(.notConnectedToInternet) }
        controller.play(url: url, track: tracks[0])
        let failed = expectation(description: "error published")
        withObservationTracking { _ = controller.playbackError } onChange: { failed.fulfill() }
        let expired = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse, userInfo: ["HTTPStatusCode": 403])
        controller.handleItemFailure(try XCTUnwrap(controller.player?.currentItem), error: expired)
        await fulfillment(of: [failed], timeout: 3)
        XCTAssertFalse(controller.isBuffering); XCTAssertFalse(controller.isPlaying)
        let count = await counter.count; XCTAssertEqual(count, 2, "Resolver's existing preferred + standard attempts, no controller loop")
    }

    func testAddressResolutionSurvivesFiveSecondsAndPauseRejectsLateResult() async throws {
        let clock = PlaybackManualClock(), gate = MusicTestGate()
        let url = try playbackWave(); defer { try? FileManager.default.removeItem(at: url) }
        let controller = MusicPlaybackController(persistsPlayback: false, timing: clock.timing)
        defer { controller.stop() }
        controller.urlResolver = PlaybackURLResolver { ids, quality in
            await gate.wait(); return try playbackResponse(ids: ids, quality: quality, url: url)
        }
        let track = try playbackTracks()[0]
        let pending = Task { await controller.play(track: track, in: [track]) }
        await waitForClock(clock)
        clock.advance(6)
        await Task.yield()
        XCTAssertNil(controller.playbackError)
        XCTAssertTrue(controller.isBuffering)
        controller.pause()
        await gate.open()
        _ = await pending.value
        XCTAssertFalse(controller.isPlaying)
        XCTAssertNil(controller.player?.currentItem)
    }

    func testAddressResolutionTimesOutAtIndependentBudgetAndRejectsLateSuccess() async throws {
        let clock = PlaybackManualClock(), gate = MusicTestGate()
        let url = try playbackWave(); defer { try? FileManager.default.removeItem(at: url) }
        let controller = MusicPlaybackController(persistsPlayback: false, timing: clock.timing)
        defer { controller.stop() }
        controller.urlResolver = PlaybackURLResolver { ids, quality in
            await gate.wait(); return try playbackResponse(ids: ids, quality: quality, url: url)
        }
        let track = try playbackTracks()[0]
        let pending = Task { await controller.play(track: track, in: [track]) }
        await waitForClock(clock)
        clock.advance(20)
        let outcome = await pending.value
        XCTAssertFalse(outcome)
        XCTAssertEqual(controller.playbackError, "播放地址获取超时，请重试")
        await gate.open()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(controller.player?.currentItem)
        XCTAssertFalse(controller.isPlaying)
    }

    func testAutomaticDowngradeUsesLowerQualityWithoutChangingPreference() async throws {
        let (controller, tracks, url, _) = try fixture()
        _ = await controller.setAudioQuality(.hires)
        _ = await controller.play(track: tracks[0], in: [tracks[0]])
        XCTAssertTrue(controller.beginAutomaticDowngrade())
        let lower = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { controller.actualQualityTitle == MusicAudioQuality.exhigh.title }
        }, object: nil)
        await fulfillment(of: [lower], timeout: 3)
        XCTAssertEqual(controller.audioQuality, .hires)
        XCTAssertTrue(controller.beginAutomaticDowngrade())
        let standard = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { controller.actualQualityTitle == MusicAudioQuality.standard.title }
        }, object: nil)
        await fulfillment(of: [standard], timeout: 3)
        XCTAssertFalse(controller.beginAutomaticDowngrade())
        XCTAssertEqual(controller.audioQuality, .hires)
        _ = url
    }

    func testLoadingProgressPreventsPrematureRebuildAndTotalBudgetStillExpires() async throws {
        let clock = PlaybackManualClock()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("progress-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = MusicAudioCache(directory: folder, transport: { _ in AsyncThrowingStream { _ in } })
        let controller = MusicPlaybackController(persistsPlayback: false, audioAssets: CachedAudioAssetFactory(cache: cache), timing: clock.timing)
        defer { controller.stop() }
        controller.play(url: URL(string: "https://audio.example/slow.wav")!, track: try playbackTracks()[0])
        let original = try XCTUnwrap(controller.player?.currentItem)
        await waitForClock(clock)
        clock.advance(6)
        XCTAssertFalse(controller.checkLoadingProgress(original, networkBytes: 1024))
        XCTAssertTrue(controller.player?.currentItem === original)
        clock.advance(14)
        XCTAssertFalse(controller.checkLoadingProgress(original, networkBytes: 1024))
        XCTAssertNil(controller.playbackError)
        clock.advance(40)
        XCTAssertTrue(controller.checkLoadingProgress(original, networkBytes: 2048))
        XCTAssertEqual(controller.playbackError, "播放准备超时，请重试")
        XCTAssertFalse(controller.isPlaying)
    }

    func testPauseCancelsPendingSeekWithoutPublishingTarget() async throws {
        let (controller, tracks, url, _) = try fixture()
        controller.play(url: url, track: tracks[0])
        controller.pause()
        let confirmed = controller.currentTimeSeconds
        controller.seek(to: 100)
        controller.pause()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(controller.isSeeking)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.currentTimeSeconds, confirmed)
    }

    func testLoadingIntentDoesNotAdvanceLockScreenRate() throws {
        let coordinator = NowPlayingCoordinator()
        let controller = MusicPlaybackController(persistsPlayback: false, nowPlayingCoordinator: coordinator)
        defer { controller.stop() }
        controller.play(url: URL(string: "https://audio.example/unavailable.flac")!, track: try playbackTracks()[0])
        XCTAssertTrue(controller.isPlaying)
        XCTAssertFalse(controller.isActuallyPlaying)
        XCTAssertEqual(coordinator.metadata?.playbackRate, 0)
    }

    /// Requires an explicit loopback fixture URL. Results distinguish state readiness from audible output.
    func testControlledSourceRoutes() async throws {
        guard let address = ProcessInfo.processInfo.environment["SETU_CONTINUITY_URL"], let url = URL(string: address),
              url.host == "127.0.0.1" else { throw XCTSkip("Run scripts/serve-music-continuity.py and set SETU_CONTINUITY_URL") }
        let duration = Double(ProcessInfo.processInfo.environment["SETU_CONTINUITY_DURATION"] ?? "40") ?? 40
        let fullPlayback = ProcessInfo.processInfo.environment["SETU_CONTINUITY_FULL"] == "1"
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("continuity-routes.json")
        let track = MusicPlaybackTrack(id: 99001, title: "Controlled fixture", artist: "", album: "", coverURLString: nil,
                                       durationMilliseconds: Int(duration * 1000), mvID: nil)
        var results: [[String: Any]] = []
        for route in ["direct", "cold", "partial", "complete"] {
            for iteration in 0..<5 {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("continuity-route-\(UUID())")
                let cache = MusicAudioCache(directory: folder, capacity: 256 * 1024 * 1024)
                let assets = route == "direct" ? nil : CachedAudioAssetFactory(cache: cache)
                let controller = MusicPlaybackController(persistsPlayback: false, audioAssets: assets)
                defer { controller.stop(); try? FileManager.default.removeItem(at: folder) }
                controller.urlResolver = PlaybackURLResolver { ids, quality in try playbackResponse(ids: ids, quality: quality, url: url) }
                let key = "anonymous|\(track.id)|\(controller.audioQuality.rawValue)"
                if route == "partial" || route == "complete" {
                    let id = try await cache.open(.init(key: key, url: url, quality: controller.audioQuality.rawValue))
                    if route == "partial" {
                        await cache.configure(capacity: 256 * 1024 * 1024, prefetchAllowed: true)
                        try await cache.prefetch(id, limit: 512 * 1024)
                    } else { _ = try await cache.completeFile(id) }
                    await cache.release(id)
                }
                let start = ProcessInfo.processInfo.systemUptime
                let selected = route == "complete" ? (await cache.cachedSource(key: key))?.0 ?? url : url
                // This matrix starts at an already resolved URL. The resolver's HTTPS
                // normalization must not rewrite the loopback HTTP fixture endpoint.
                controller.play(url: selected, track: track, queueTracks: [track], playMode: .sequence)
                while !controller.isActuallyPlaying, controller.playbackError == nil,
                      ProcessInfo.processInfo.systemUptime - start < 65 {
                    try await Task.sleep(for: .milliseconds(20))
                }
                let latency = ProcessInfo.processInfo.systemUptime - start
                XCTAssertNil(controller.playbackError, "\(route) iteration \(iteration)")
                XCTAssertTrue(controller.isActuallyPlaying)
                guard controller.playbackError == nil, controller.isActuallyPlaying else { return }
                var stalls = 0, lastBuffering = false
                let until = ProcessInfo.processInfo.systemUptime + (fullPlayback && route == "cold" && iteration == 0 ? duration + 2 : 1)
                while ProcessInfo.processInfo.systemUptime < until, controller.playbackError == nil,
                      controller.currentTimeSeconds < duration - 0.1 {
                    if controller.isBuffering && !lastBuffering { stalls += 1 }
                    lastBuffering = controller.isBuffering
                    XCTAssertLessThanOrEqual(controller.currentTimeSeconds, controller.durationSeconds)
                    XCTAssertLessThanOrEqual(controller.rawMediaTimeSeconds, controller.durationSeconds + 0.5)
                    try await Task.sleep(for: .milliseconds(250))
                }
                XCTAssertNil(controller.playbackError)
                XCTAssertEqual(stalls, 0, "Adequate controlled bandwidth must sustain playback")
                results.append(["route": route, "iteration": iteration, "loadToPlayingSeconds": latency,
                                "stalls": stalls, "position": controller.currentTimeSeconds,
                                "error": controller.playbackError as Any? ?? NSNull(), "audibleOutputVerified": false])
                try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: output)
                controller.stop()
            }
        }
        let direct = results.filter { $0["route"] as? String == "direct" }.compactMap { $0["loadToPlayingSeconds"] as? Double }.sorted()[2]
        for route in ["cold", "partial", "complete"] {
            let median = results.filter { $0["route"] as? String == route }.compactMap { $0["loadToPlayingSeconds"] as? Double }.sorted()[2]
            XCTAssertLessThanOrEqual(median - direct, 1, "State readiness overhead for \(route)")
        }
    }

    private func waitForClock(_ clock: PlaybackManualClock) async {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in clock.waiterCount > 0 }, object: nil)
        await fulfillment(of: [ready], timeout: 2)
    }

    func testSlowPreloadDoesNotBlockNextAndLatePreparedItemIsDiscarded() async throws {
        let (controller, tracks, url, _) = try fixture()
        let gate = MusicTestGate(), started = expectation(description: "asset preparation")
        let preparer = NextItemPreparer { source in
            started.fulfill(); await gate.wait(); return AVPlayerItem(url: source)
        }
        let resolver = try XCTUnwrap(controller.urlResolver)
        let preparation = Task { await preparer.prepare(trackID: 2, quality: .exhigh, resolver: resolver) }
        await fulfillment(of: [started], timeout: 2)
        controller.play(url: url, track: tracks[0], queueTracks: tracks)
        await controller.userSkip(by: 1)
        XCTAssertEqual(controller.currentTrack?.id, 2)
        preparer.invalidate()
        await gate.open(); await preparation.value
        XCTAssertNil(preparer.prepared)
    }

    func testRestoredSnapshotKeepsConfirmedMediaDurationBeyondCatalog() async throws {
        let suite = "continuity-duration-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let url = try playbackWave(); defer { try? FileManager.default.removeItem(at: url) }
        let controller = MusicPlaybackController(preferences: preferences)
        defer { controller.stop() }
        let track = MusicPlaybackTrack(id: 9990, title: "Duration fixture", artist: "", album: "", coverURLString: nil,
                                       durationMilliseconds: 150000, mvID: nil)
        controller.setSnapshotUserID(51)
        controller.play(url: url, track: track); controller.pause()
        controller.seek(to: 170); await waitForSeek(controller)
        controller.savePlaybackSnapshot(userID: 51); await controller.waitForSnapshotWrites()
        let restored = MusicPlaybackController(preferences: preferences)
        defer { restored.stop() }
        restored.restorePlaybackSnapshotIfNeeded(for: 51)
        XCTAssertEqual(restored.durationSeconds, 180, accuracy: 0.01)
        XCTAssertEqual(restored.currentTimeSeconds, 170, accuracy: 0.01)
    }

    func testLegacySnapshotPreservesCheckpointUntilMediaDurationIsKnown() async throws {
        let suite = "continuity-legacy-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let track = MusicPlaybackTrack(id: 9990, title: "Duration fixture", artist: "", album: "", coverURLString: nil,
                                       durationMilliseconds: 150000, mvID: nil)
        let snapshot = PlaybackSnapshotStore.Snapshot(userID: 51, track: track,
            context: .unknown(reason: .legacySnapshot, label: nil), queueTracks: [track],
            currentQueueIndex: 0, currentTimeSeconds: 170, playMode: .sequence, updatedAt: Date())
        preferences.set(try JSONEncoder().encode(snapshot), forKey: PlaybackSnapshotStore.snapshotKey(userID: 51))
        let controller = MusicPlaybackController(preferences: preferences)
        defer { controller.stop() }
        controller.restorePlaybackSnapshotIfNeeded(for: 51)
        controller.savePlaybackSnapshot(userID: 51); await controller.waitForSnapshotWrites()
        let data = try XCTUnwrap(preferences.data(forKey: PlaybackSnapshotStore.snapshotKey(userID: 51)))
        let saved = try JSONDecoder().decode(PlaybackSnapshotStore.Snapshot.self, from: data)
        XCTAssertEqual(saved.currentTimeSeconds, 170)
        XCTAssertNil(saved.mediaDurationSeconds)
    }

    func testSnapshotWritesKeepBothUserQueuesAndStopRevokesPendingWrite() async throws {
        let suite = "setu-snapshot-test-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let tracks = try playbackTracks(), url = try playbackWave()
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = MusicPlaybackController(preferences: preferences)
        controller.setSnapshotUserID(1)
        controller.play(url: url, track: tracks[0], queueTracks: tracks)
        controller.pause()
        controller.seek(to: 3)
        await waitForSeek(controller)
        controller.savePlaybackSnapshot(userID: 1)
        controller.resetForUserChange()
        controller.setSnapshotUserID(2)
        controller.play(url: url, track: tracks[1], queueTracks: tracks)
        controller.pause()
        controller.seek(to: 4)
        await waitForSeek(controller)
        controller.savePlaybackSnapshot(userID: 2)
        await controller.waitForSnapshotWrites()
        let restoredA = MusicPlaybackController(preferences: preferences)
        restoredA.restorePlaybackSnapshotIfNeeded(for: 1)
        let restoredB = MusicPlaybackController(preferences: preferences)
        restoredB.restorePlaybackSnapshotIfNeeded(for: 2)
        XCTAssertEqual(restoredA.currentTrack?.id, 1)
        XCTAssertEqual(restoredA.currentTimeSeconds, 3)
        XCTAssertEqual(restoredB.currentTrack?.id, 2)
        XCTAssertEqual(restoredB.currentTimeSeconds, 4)
        controller.seek(to: 5); controller.stop()
        await controller.waitForSnapshotWrites()
        let stopped = MusicPlaybackController(preferences: preferences)
        stopped.restorePlaybackSnapshotIfNeeded(for: 2)
        XCTAssertNil(stopped.currentTrack)
    }

    func testMissingLocalFileFailsWithoutRefreshingRemoteURL() async throws {
        let (controller, tracks, _, _) = try fixture()
        let missing = URL(fileURLWithPath: "/tmp/setu-missing-\(UUID().uuidString).wav")
        let counter = MusicTestCounter()
        controller.urlResolver = PlaybackURLResolver { ids, quality in
            _ = await counter.next(); return try playbackResponse(ids: ids, quality: quality, url: missing)
        }
        controller.play(url: missing, track: tracks[0])
        let failed = expectation(description: "initial AVPlayerItem.status failed")
        withObservationTracking { _ = controller.playbackError } onChange: { failed.fulfill() }
        await fulfillment(of: [failed], timeout: 5)
        XCTAssertNotNil(controller.playbackError)
        XCTAssertFalse(controller.isBuffering)
        let count = await counter.count; XCTAssertEqual(count, 0)
    }

    func testPendingHistoryForSameTrackIsCoalesced() async throws {
        let (controller, tracks, _, _) = try fixture()
        let gate = MusicTestGate(), started = expectation(description: "history")
        var writes = 0
        controller.recordPlaybackHistory = { _ in writes += 1; started.fulfill(); await gate.wait() }
        _ = await controller.play(track: tracks[0], in: tracks)
        await fulfillment(of: [started], timeout: 2)
        _ = await controller.play(track: tracks[0], in: tracks)
        XCTAssertEqual(writes, 1)
        await gate.open()
    }

    func testPausedWhileResolvingDoesNotAutoplayOnLateResponse() async throws {
        let (controller, tracks, url, _) = try fixture()
        let gate = MusicTestGate(), started = expectation(description: "resolve")
        controller.urlResolver = PlaybackURLResolver { ids, quality in
            started.fulfill(); await gate.wait(); return try playbackResponse(ids: ids, quality: quality, url: url)
        }
        let request = Task { await controller.play(track: tracks[0], in: tracks) }
        await fulfillment(of: [started], timeout: 2)
        controller.pause()
        await gate.open(); _ = await request.value
        XCTAssertFalse(controller.isPlaying); XCTAssertFalse(controller.isBuffering)
    }

    func testPreloadFailureAndExpiryAreSafeMisses() async throws {
        let resolver = PlaybackURLResolver { ids, quality in try playbackResponse(ids: ids, quality: quality) }
        let preparer = NextItemPreparer { _ in throw URLError(.timedOut) }
        await preparer.prepare(trackID: 2, quality: .exhigh, resolver: resolver)
        XCTAssertNil(preparer.consume(trackID: 2, quality: .exhigh))
        let (_, _, url, _) = try fixture()
        let usable = NextItemPreparer { _ in AVPlayerItem(url: url) }
        await usable.prepare(trackID: 2, quality: .exhigh, resolver: resolver)
        XCTAssertNotNil(usable.prepared)
        XCTAssertNil(usable.consume(trackID: 2, quality: .lossless))
        XCTAssertNil(usable.consume(trackID: 2, quality: .exhigh, now: Date().addingTimeInterval(601)))
    }
}

func playbackWave(seconds: Int = 180) throws -> URL {
    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
    let bytes = 8_000 * 2 * seconds
    data.append(Data("RIFF".utf8)); append(UInt32(36 + bytes)); data.append(Data("WAVEfmt ".utf8))
    append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(UInt32(8_000)); append(UInt32(16_000)); append(UInt16(2)); append(UInt16(16))
    data.append(Data("data".utf8)); append(UInt32(bytes)); data.append(Data(repeating: 0, count: bytes))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("setu-playback-\(UUID().uuidString).wav")
    try data.write(to: url); return url
}

private final class PlaybackManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: Double = 0
    private var waiters: [UUID: (Double, CheckedContinuation<Void, Error>)] = [:]
    var waiterCount: Int { lock.withLock { waiters.count } }
    var timing: PlaybackTiming {
        PlaybackTiming(now: { self.lock.withLock { self.time } }, sleep: { try await self.sleep($0) })
    }
    func advance(_ seconds: Double) {
        let ready: [CheckedContinuation<Void, Error>] = lock.withLock {
            time += seconds
            let ready = waiters.filter { $0.value.0 <= time }
            for key in ready.keys { waiters[key] = nil }
            return ready.values.map { $0.1 }
        }
        ready.forEach { $0.resume() }
    }
    private func sleep(_ seconds: Double) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if Task.isCancelled { lock.unlock(); continuation.resume(throwing: CancellationError()) }
                else { waiters[id] = (time + seconds, continuation); lock.unlock() }
            }
        } onCancel: {
            let waiter = self.lock.withLock { self.waiters.removeValue(forKey: id) }
            waiter?.1.resume(throwing: CancellationError())
        }
    }
}
