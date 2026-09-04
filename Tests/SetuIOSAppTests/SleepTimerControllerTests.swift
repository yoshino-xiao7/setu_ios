import AVFoundation
import XCTest
@testable import SetuIOSApp

@MainActor
final class SleepTimerControllerTests: XCTestCase {
    func testEndOfTrackIsConsumedExactlyOnceAndCancelClearsIt() {
        let controller = SleepTimerController()
        controller.start(.endOfTrack) {}
        XCTAssertTrue(controller.consumeEndOfTrack())
        XCTAssertFalse(controller.consumeEndOfTrack())
        controller.start(.endOfTrack) {}
        controller.cancel()
        XCTAssertFalse(controller.consumeEndOfTrack())
    }

    func testDurationFiresThroughInjectedClock() async {
        let fired = expectation(description: "timer fired")
        let controller = SleepTimerController(sleep: { _ in })
        controller.start(.fifteenMinutes) { fired.fulfill() }
        await fulfillment(of: [fired], timeout: 1)
    }

    func testFadeRestoresVolumeAndCompletesAfterPause() async {
        let completed = expectation(description: "fade completed")
        let player = AVPlayer()
        player.volume = 0.64
        let controller = SleepTimerController(sleep: { _ in })

        controller.fadeOutAndPause(player: player) { completed.fulfill() }

        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(player.rate, 0)
        XCTAssertEqual(player.volume, 0.64, accuracy: 0.001)
    }

    func testCancelStopsFadeAndRestoresVolume() async {
        let completed = expectation(description: "cancelled fade must not complete")
        completed.isInverted = true
        let player = AVPlayer()
        player.volume = 0.72
        let controller = SleepTimerController(sleep: { _ in
            try await Task.sleep(nanoseconds: 1_000_000_000)
        })

        controller.fadeOutAndPause(player: player) { completed.fulfill() }
        await Task.yield()
        controller.cancel()

        await fulfillment(of: [completed], timeout: 0.05)
        XCTAssertEqual(player.volume, 0.72, accuracy: 0.001)
    }
}
