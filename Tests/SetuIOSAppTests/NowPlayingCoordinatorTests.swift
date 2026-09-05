import XCTest
@testable import SetuIOSApp

@MainActor
final class NowPlayingCoordinatorTests: XCTestCase {
    func testMetadataProjectionAndClear() {
        let coordinator = NowPlayingCoordinator()
        let track = MusicPlaybackTrack(id: 7, title: "Title", artist: "Artist", album: "Album", coverURLString: nil, durationMilliseconds: 180_000, mvID: nil)
        coordinator.update(track: track, isPlaying: true, elapsed: 12)
        XCTAssertEqual(coordinator.metadata, .init(title: "Title", artist: "Artist", album: "Album", duration: 180, elapsed: 12, playbackRate: 1))
        coordinator.clear()
        XCTAssertNil(coordinator.metadata)
    }
}
