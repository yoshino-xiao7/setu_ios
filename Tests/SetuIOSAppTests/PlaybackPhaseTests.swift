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
