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

    func testFailedItemReResolvesOnceAndSecondFailureExitsBuffering() async throws {
        let (controller, tracks, url, counter) = try fixture()
        controller.play(url: url, track: tracks[0], queueTracks: tracks)
        let original = try XCTUnwrap(controller.player?.currentItem)
        let replaced = expectation(description: "recovery replaced item")
        let observer = try XCTUnwrap(controller.player).observe(\.currentItem, options: [.new]) { engine, _ in
            if let item = engine.currentItem, item !== original { replaced.fulfill() }
        }
        controller.handleItemFailure(original, error: URLError(.timedOut))
        controller.handleItemFailure(original, error: URLError(.timedOut)) // Duplicate notifications share one recovery.
        await fulfillment(of: [replaced], timeout: 3)
        observer.invalidate()
        let retried = try XCTUnwrap(controller.player?.currentItem)
        controller.handleItemFailure(retried, error: URLError(.cannotConnectToHost))
        XCTAssertNotNil(controller.playbackError); XCTAssertFalse(controller.isBuffering); XCTAssertFalse(controller.isPlaying)
        let count = await counter.count; XCTAssertEqual(count, 1)
    }

    func testRecoveryURLFailureShowsErrorWithoutLoop() async throws {
        let (controller, tracks, url, _) = try fixture()
        let counter = MusicTestCounter()
        controller.urlResolver = PlaybackURLResolver { _, _ in _ = await counter.next(); throw URLError(.notConnectedToInternet) }
        controller.play(url: url, track: tracks[0])
        let failed = expectation(description: "error published")
        withObservationTracking { _ = controller.playbackError } onChange: { failed.fulfill() }
        controller.handleItemFailure(try XCTUnwrap(controller.player?.currentItem), error: URLError(.timedOut))
        await fulfillment(of: [failed], timeout: 3)
        XCTAssertFalse(controller.isBuffering); XCTAssertFalse(controller.isPlaying)
        let count = await counter.count; XCTAssertEqual(count, 2, "One recovery with preferred + standard, no loop")
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

    func testSnapshotWritesKeepBothUserQueuesAndStopRevokesPendingWrite() async throws {
        let suite = "setu-snapshot-test-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let tracks = try playbackTracks(), url = try playbackWave()
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = MusicPlaybackController(preferences: preferences)
        controller.setSnapshotUserID(1)
        controller.play(url: url, track: tracks[0], queueTracks: tracks)
        controller.seek(to: 3)
        controller.savePlaybackSnapshot(userID: 1)
        controller.resetForUserChange()
        controller.setSnapshotUserID(2)
        controller.play(url: url, track: tracks[1], queueTracks: tracks)
        controller.seek(to: 4)
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

    func testInitialItemStatusFailurePublishesErrorAfterOneRetry() async throws {
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
        let count = await counter.count; XCTAssertEqual(count, 1)
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

func playbackWave() throws -> URL {
    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
    let bytes = 8_000 * 2 * 180
    data.append(Data("RIFF".utf8)); append(UInt32(36 + bytes)); data.append(Data("WAVEfmt ".utf8))
    append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(UInt32(8_000)); append(UInt32(16_000)); append(UInt16(2)); append(UInt16(16))
    data.append(Data("data".utf8)); append(UInt32(bytes)); data.append(Data(repeating: 0, count: bytes))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("setu-playback-\(UUID().uuidString).wav")
    try data.write(to: url); return url
}
