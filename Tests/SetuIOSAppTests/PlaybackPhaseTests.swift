import XCTest
@testable import SetuIOSApp

@MainActor
final class PlaybackPhaseTests: XCTestCase {
    func testDerivesAllLowFrequencyStatesWithoutPayloads() {
        XCTAssertEqual(PlaybackPhase.derive(hasTrack: false, isBuffering: false, isPlaying: false, hasError: false), .idle)
        XCTAssertEqual(PlaybackPhase.derive(hasTrack: true, isBuffering: true, isPlaying: true, hasError: false), .loading)
        XCTAssertEqual(PlaybackPhase.derive(hasTrack: true, isBuffering: false, isPlaying: true, hasError: false), .playing)
        XCTAssertEqual(PlaybackPhase.derive(hasTrack: true, isBuffering: false, isPlaying: false, hasError: false), .paused)
        XCTAssertEqual(PlaybackPhase.derive(hasTrack: true, isBuffering: false, isPlaying: false, hasError: true), .failed)
    }

    func testBandwidthDowngradeRequiresReceivingAndHasFiniteLadder() {
        var policy = PlaybackDowngradePolicy()
        XCTAssertFalse(policy.shouldDowngrade(now: 20, waitingSince: 0, receiving: false))
        XCTAssertFalse(policy.shouldDowngrade(now: 7, waitingSince: 0, receiving: true))
        XCTAssertTrue(policy.shouldDowngrade(now: 8, waitingSince: 0, receiving: true))
        XCTAssertEqual(policy.takeNext(after: "hires"), "exhigh")
        XCTAssertEqual(policy.takeNext(after: "exhigh"), "standard")
        XCTAssertNil(policy.takeNext(after: "hires"))
    }

    func testRepeatedStallsExpireAndShortStallsDoNotQualify() {
        var policy = PlaybackDowngradePolicy()
        policy.endedStall(start: 0, end: 0.5)
        policy.endedStall(start: 1, end: 3)
        policy.endedStall(start: 4, end: 6)
        XCTAssertFalse(policy.shouldDowngrade(now: 7, waitingSince: 7, receiving: true))
        policy.endedStall(start: 7, end: 9)
        XCTAssertTrue(policy.shouldDowngrade(now: 10, waitingSince: 10, receiving: true))
        XCTAssertFalse(policy.shouldDowngrade(now: 40, waitingSince: 40, receiving: true))
        XCTAssertNil(policy.takeNext(after: "unknown"))
    }

    func testControllerRetainsFineGrainedObservablePlaybackProperties() {
        let controller = MusicPlaybackController(persistsPlayback: false)

        _ = controller.isPlaying
        _ = controller.isBuffering
        _ = controller.currentTimeSeconds
        _ = controller.playbackError
        _ = controller.currentTrack
        _ = controller.currentQueueIndex
        _ = controller.playMode
        XCTAssertEqual(controller.phase, .idle)
    }
}
