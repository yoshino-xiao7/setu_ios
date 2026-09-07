import XCTest
@testable import SetuIOSApp

@MainActor
final class NowPlayingCoordinatorTests: XCTestCase {
    func testResolvedDurationBoundsElapsedAndRejectsNonfiniteTime() {
        let coordinator = NowPlayingCoordinator()
        let track = MusicPlaybackTrack(id: 7, title: "Title", artist: "Artist", album: "Album", coverURLString: nil,
                                       durationMilliseconds: 150_000, mvID: nil)
        coordinator.update(track: track, isPlaying: true, elapsed: 170, duration: 180)
        XCTAssertEqual(coordinator.metadata?.duration, 180)
        XCTAssertEqual(coordinator.metadata?.elapsed, 170)
        coordinator.update(track: track, isPlaying: false, elapsed: 200, duration: 180)
        XCTAssertEqual(coordinator.metadata?.elapsed, 180)
        coordinator.update(track: track, isPlaying: false, elapsed: .nan)
        XCTAssertNil(coordinator.metadata?.elapsed)
        XCTAssertEqual(coordinator.metadata?.duration, 150)
    }

    func testMetadataProjectionAndClear() {
        let coordinator = NowPlayingCoordinator()
        let track = MusicPlaybackTrack(id: 7, title: "Title", artist: "Artist", album: "Album", coverURLString: nil, durationMilliseconds: 180_000, mvID: nil)
        coordinator.update(track: track, isPlaying: true, elapsed: 12)
        XCTAssertEqual(coordinator.metadata, .init(title: "Title", artist: "Artist", album: "Album", duration: 180, elapsed: 12, playbackRate: 1))
        coordinator.clear()
        XCTAssertNil(coordinator.metadata)
    }
}
