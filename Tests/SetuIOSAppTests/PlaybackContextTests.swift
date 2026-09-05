import XCTest
@testable import SetuIOSApp

@MainActor
final class PlaybackContextTests: XCTestCase {
    func testSourceIdentityIgnoresPresentationLabel() {
        let lhs = PlaybackContext.playlist(id: .provider(.canonical(.init(rawValue: "provider:playlist:001"))), label: "旧标题")
        let rhs = PlaybackContext.playlist(id: .provider(.canonical(.init(rawValue: "provider:playlist:001"))), label: "新标题")
        XCTAssertEqual(lhs, rhs)
        XCTAssertNotEqual(lhs, .playlist(id: .provider(.canonical(.init(rawValue: "provider:playlist:1"))), label: "旧标题"))
    }

    func testTypedCapabilitiesPreventPreviousForRadioAndSingleTrack() {
        let source = PlaybackContext.DiscoverySource.sharedAlgorithmic()
        XCTAssertFalse(PlaybackContext.radio(sessionID: "session-01", source: source, label: nil).allowsPrevious)
        XCTAssertFalse(PlaybackContext.singleTrack(trackID: .canonical(.init(rawValue: "provider:track:0007")), label: nil).allowsPrevious)
        XCTAssertTrue(PlaybackContext.search(query: "test", scope: .tracks, label: nil).allowsPrevious)
    }

    func testContextDisablesControllerAndRemotePreviousAndClearsOnUserSwitch() {
        let remote = RemoteCommandCoordinator()
        let controller = MusicPlaybackController(persistsPlayback: false, remoteCommandCoordinator: remote)
        let tracks = [1, 2].map {
            MusicPlaybackTrack(id: $0, title: "Song \($0)", artist: "Artist", album: "Album", coverURLString: nil, durationMilliseconds: 1_000, mvID: nil)
        }
        controller.play(
            url: URL(fileURLWithPath: "/private/tmp/nonexistent-playback-fixture"),
            track: tracks[1],
            context: .singleTrack(trackID: .canonical(.init(rawValue: "provider:track:0002")), label: nil),
            queueTracks: tracks
        )
        XCTAssertFalse(controller.canPlayPrevious)
        XCTAssertFalse(remote.previousEnabled)
        controller.resetForUserChange()
        XCTAssertNil(controller.context)
        XCTAssertTrue(remote.previousEnabled)
    }
}
