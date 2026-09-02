import XCTest
@testable import SetuIOSApp
@testable import SetuIOSCore

final class MusicPlaybackQueueTests: XCTestCase {
    func testSequenceLoopAndSingleTargets() throws {
        var queue = PlaybackQueue(); queue.tracks = try playbackTracks(); queue.currentIndex = 0
        XCTAssertEqual(queue.nextForPreparation()?.id, 2)
        queue.currentIndex = 1; XCTAssertEqual(queue.nextForPreparation()?.id, 3)
        queue.currentIndex = 2; XCTAssertNil(queue.nextForPreparation())
        queue.mode = .loop; XCTAssertEqual(queue.nextForPreparation()?.id, 1)
        queue.mode = .single; XCTAssertNil(queue.nextForPreparation())
        XCTAssertEqual(queue.target(from: 2, offset: 1, isAuto: true), 2)
        XCTAssertEqual(queue.target(from: 1, offset: 1, isAuto: false), 2)
    }

    func testRandomPreparedTargetIsConsumedWithoutAnotherDraw() throws {
        var queue = PlaybackQueue(); queue.tracks = try playbackTracks(); queue.currentIndex = 0; queue.mode = .random
        let first = queue.target(from: 0, offset: 1, isAuto: true, random: { _ in 1 })
        XCTAssertEqual(first, 2)
        let next = queue.target(from: 0, offset: 1, isAuto: false, random: { _ in XCTFail("Must use pending target"); return 0 })
        XCTAssertEqual(next, first)
        queue.currentIndex = next
        XCTAssertNil(queue.pendingRandomIndex)
    }

    func testQueueEditInvalidatesRandomAndPlayNextOverridesIt() throws {
        var queue = PlaybackQueue(); queue.tracks = try playbackTracks(); queue.currentIndex = 0; queue.mode = .random
        _ = queue.nextForPreparation()
        queue.tracks.removeLast(); XCTAssertNil(queue.pendingRandomIndex)
        queue.prioritizeNext(2); XCTAssertEqual(queue.nextForPreparation()?.id, 2)
        queue.tracks = [queue.tracks[0]]; XCTAssertNil(queue.nextForPreparation())
    }
}

func playbackTracks() throws -> [MusicPlaybackTrack] {
    let songs = try JSONDecoder().decode([MusicSong].self, from: Data("[{\"id\":1,\"name\":\"A\",\"duration\":180000},{\"id\":2,\"name\":\"B\",\"duration\":180000},{\"id\":3,\"name\":\"C\",\"duration\":180000}]".utf8))
    return songs.map(MusicPlaybackTrack.init(song:))
}
