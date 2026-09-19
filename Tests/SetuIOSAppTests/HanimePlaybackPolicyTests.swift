import AVFoundation
import Foundation
import XCTest
@testable import SetuIOSApp
import SetuIOSCore

final class HanimePlaybackPolicyTests: XCTestCase {
    private func stream(_ quality: String, _ name: String, isHLS: Bool = false) -> HanimeStream {
        HanimeStream(quality: quality, url: URL(string: "https://cdn.example.invalid/\(name).mp4")!, isHLS: isHLS)
    }

    private func sample(
        at: TimeInterval,
        position: Double,
        playing: Bool = true,
        waiting: Bool = false,
        frames: Int? = 1,
        dropped: Int? = nil,
        ahead: Double = 30
    ) -> HanimePlaybackSample {
        HanimePlaybackSample(
            at: at,
            positionSeconds: position,
            isClockRunning: playing,
            isWaitingToPlay: waiting,
            renderedFrames: frames,
            droppedVideoFrames: dropped,
            bufferedAheadSeconds: ahead
        )
    }

    // MARK: - Start rendition

    func testWifiKeepsTopRendition() {
        let streams = [stream("1080p", "a"), stream("720p", "b"), stream("480p", "c")]
        let budget = HanimeRenditionPolicy.budget(isExpensiveNetwork: false)
        XCTAssertNil(budget.startHeightLimit)
        XCTAssertEqual(HanimeRenditionPolicy.pickStream(in: streams, budget: budget)?.quality, "1080p")
    }

    func testCellularStartsAtOrBelow720() {
        let streams = [stream("1080p", "a"), stream("720p", "b"), stream("480p", "c")]
        let budget = HanimeRenditionPolicy.budget(isExpensiveNetwork: true)
        let picked = HanimeRenditionPolicy.pickStream(in: streams, budget: budget)
        XCTAssertEqual(picked?.quality, "720p")
        XCTAssertLessThanOrEqual(picked?.rank ?? 0, HanimeRenditionPolicy.cellularHeightLimit)
    }

    func testCellularFallsBackToLowestWhenNothingFits() {
        let streams = [stream("1080p", "a"), stream("2160p", "b")]
        let budget = HanimeRenditionPolicy.budget(isExpensiveNetwork: true)
        XCTAssertEqual(HanimeRenditionPolicy.pickStream(in: streams, budget: budget)?.quality, "1080p")
    }

    func testUnknownRanksStillPlay() {
        let streams = [stream("MP4", "a"), stream("HLS", "b", isHLS: true)]
        let budget = HanimeRenditionPolicy.budget(isExpensiveNetwork: true)
        XCTAssertNotNil(HanimeRenditionPolicy.pickStream(in: streams, budget: budget))
    }

    func testLowerStreamOnlyStrictlyLowerAndNotSkipped() {
        let high = stream("1080p", "a")
        let mid = stream("720p", "b")
        let low = stream("480p", "c")
        let streams = [high, mid, low]
        XCTAssertEqual(HanimeRenditionPolicy.lowerStream(than: high, in: streams, excluding: [])?.quality, "720p")
        XCTAssertEqual(
            HanimeRenditionPolicy.lowerStream(than: high, in: streams, excluding: [mid.id])?.quality,
            "480p"
        )
        XCTAssertNil(HanimeRenditionPolicy.lowerStream(than: low, in: streams, excluding: []))
    }

    func testBudgetCapsBitRateForHLSOnly() {
        let budget = HanimeRenditionPolicy.budget(isExpensiveNetwork: true)
        let mediaURL = URL(string: "https://cdn.example.invalid/x.mp4")!
        let mp4 = AVPlayerItem(url: mediaURL)
        HanimeRenditionPolicy.apply(budget, to: mp4, isHLS: false)
        XCTAssertEqual(mp4.preferredForwardBufferDuration, budget.forwardBufferSeconds)
        XCTAssertEqual(mp4.preferredPeakBitRate, 0, "single-rendition MP4 must not be throttled")

        let hls = AVPlayerItem(url: mediaURL)
        HanimeRenditionPolicy.apply(budget, to: hls, isHLS: true)
        XCTAssertEqual(hls.preferredPeakBitRate, budget.hlsPeakBitRate)
        XCTAssertEqual(hls.preferredPeakBitRateForExpensiveNetworks, budget.hlsPeakBitRate)
    }

    // MARK: - Recovery ladder

    func testFirstStallShedsResolutionWithoutNewRequests() {
        let high = stream("1080p", "a")
        let mid = stream("720p", "b")
        let step = HanimeRecoveryPlan.step(
            current: high,
            streams: [high, mid],
            skipped: [],
            refreshed: false,
            canRefresh: true
        )
        XCTAssertEqual(step, .switchTo(mid))
    }

    func testStallOnLowestRenditionRefreshesLinksOnce() {
        let low = stream("480p", "a")
        let step = HanimeRecoveryPlan.step(
            current: low,
            streams: [low],
            skipped: [low.id],
            refreshed: false,
            canRefresh: true
        )
        XCTAssertEqual(step, .refreshLinks)
    }

    func testRefreshedLinksSwitchSourceWhenStallsContinue() {
        let low = stream("480p", "a")
        let other = stream("480p", "b")
        let step = HanimeRecoveryPlan.step(
            current: low,
            streams: [low, other],
            skipped: [low.id],
            refreshed: true,
            canRefresh: true
        )
        XCTAssertEqual(step, .switchTo(other))
    }

    func testNoLeverLeftHandsFailureToUser() {
        let only = stream("480p", "a")
        let step = HanimeRecoveryPlan.step(
            current: only,
            streams: [only],
            skipped: [only.id],
            refreshed: true,
            canRefresh: true
        )
        XCTAssertEqual(step, .giveUp)
    }

    func testSustainedFrameDropsDowngradeRendition() {
        var watchdog = HanimePlaybackWatchdog()
        watchdog.consume(sample(at: 0, position: 10))
        // Not frozen: video keeps producing frames but half of them are dropped.
        XCTAssertEqual(watchdog.consume(sample(at: 2, position: 12, dropped: 30)), .none)
        XCTAssertEqual(watchdog.consume(sample(at: 4, position: 14, dropped: 30)), .none)
        XCTAssertEqual(
            watchdog.consume(sample(at: 6, position: 16, dropped: 30)),
            .recover(.frameRateCollapse, resumeAt: 10)
        )
    }

    func testShortDropBurstDoesNotInterruptPlayback() {
        var watchdog = HanimePlaybackWatchdog()
        watchdog.consume(sample(at: 0, position: 10))
        XCTAssertEqual(watchdog.consume(sample(at: 2, position: 12, dropped: 40)), .none)
        XCTAssertEqual(watchdog.consume(sample(at: 4, position: 14, dropped: 40)), .none)
        XCTAssertEqual(watchdog.consume(sample(at: 6, position: 16)), .healthy)
        XCTAssertEqual(watchdog.consume(sample(at: 8, position: 18, dropped: 40)), .none)
    }

    func testSmallFrameDropCountStaysHealthy() {
        var watchdog = HanimePlaybackWatchdog()
        watchdog.consume(sample(at: 0, position: 10))
        for at in stride(from: 2.0, through: 8.0, by: 2.0) {
            XCTAssertEqual(watchdog.consume(sample(at: at, position: 10 + at, dropped: 5)), .healthy)
        }
    }

    // MARK: - Drop counter delta

    func testDroppedDeltaNeedsTwoReadingsAndRebaselines() {
        let monitor = HanimeStallMonitor()
        XCTAssertNil(monitor.droppedDelta(current: 10))
        XCTAssertEqual(monitor.droppedDelta(current: 26), 16)
        XCTAssertNil(monitor.droppedDelta(current: 4), "a new log event restarts the counter")
        XCTAssertEqual(monitor.droppedDelta(current: 9), 5)
        XCTAssertNil(monitor.droppedDelta(current: nil))
        monitor.resetForNewPlayback(at: nil)
        XCTAssertNil(monitor.droppedDelta(current: 9), "a new item needs a fresh baseline")
    }

    // MARK: - Watchdog

    func testClockRunningWithoutVideoFramesRecoversAtLastHealthyPosition() {
        var watchdog = HanimePlaybackWatchdog()
        XCTAssertEqual(
            watchdog.consume(sample(at: 0, position: 20)),
            .none,
            "first window only seeds the comparison"
        )
        XCTAssertEqual(watchdog.consume(sample(at: 2, position: 22)), .healthy)
        XCTAssertEqual(watchdog.consume(sample(at: 4, position: 24, frames: 0)), .buffering)
        let action = watchdog.consume(sample(at: 6, position: 26, frames: 0))
        XCTAssertEqual(action, .recover(.videoFrozen, resumeAt: 22), "resume where video was last good, not where audio drifted")
    }

    func testFrameArrivalClearsStallSuspicion() {
        var watchdog = HanimePlaybackWatchdog()
        watchdog.consume(sample(at: 0, position: 10))
        watchdog.consume(sample(at: 2, position: 12, frames: 0))
        XCTAssertEqual(watchdog.consume(sample(at: 4, position: 14, frames: 1)), .healthy)
        XCTAssertEqual(watchdog.consume(sample(at: 6, position: 16, frames: 0)), .buffering)
    }

    func testMissingFramesSignalFallsBackToBufferSupply() {
        var watchdog = HanimePlaybackWatchdog()
        watchdog.consume(sample(at: 0, position: 40, frames: nil))
        watchdog.consume(sample(at: 2, position: 42, frames: nil, ahead: 0.2))
        XCTAssertEqual(
            watchdog.consume(sample(at: 4, position: 44, frames: nil, ahead: 0.1)),
            .recover(.supplyStarved, resumeAt: 40)
        )
    }

    func testHealthyBufferSupplyIsNotAStall() {
        var watchdog = HanimePlaybackWatchdog()
        watchdog.consume(sample(at: 0, position: 40, frames: nil))
        XCTAssertEqual(watchdog.consume(sample(at: 2, position: 42, frames: nil, ahead: 25)), .healthy)
        XCTAssertEqual(watchdog.consume(sample(at: 4, position: 44, frames: nil, ahead: 23)), .healthy)
    }

    func testWaitingToPlayRecoversOnlyAfterTimeout() {
        var watchdog = HanimePlaybackWatchdog(stallTimeoutSeconds: 6)
        watchdog.consume(sample(at: 0, position: 10))
        for at in stride(from: 2.0, through: 4.0, by: 2.0) {
            XCTAssertEqual(
                watchdog.consume(sample(at: at, position: 10, playing: false, waiting: true)),
                .buffering
            )
        }
        let action = watchdog.consume(sample(at: 6, position: 10, playing: false, waiting: true))
        XCTAssertEqual(action, .recover(.stalledTooLong, resumeAt: 10))
    }

    func testUserPauseNeverLooksLikeAStall() {
        var watchdog = HanimePlaybackWatchdog(stallTimeoutSeconds: 4)
        watchdog.consume(sample(at: 0, position: 10))
        for at in stride(from: 2.0, through: 20.0, by: 2.0) {
            XCTAssertEqual(
                watchdog.consume(sample(at: at, position: 10, playing: false, waiting: false)),
                .healthy
            )
        }
    }

    func testPlayingClockThatDoesNotAdvanceRecovers() {
        var watchdog = HanimePlaybackWatchdog()
        watchdog.consume(sample(at: 0, position: 30))
        XCTAssertEqual(watchdog.consume(sample(at: 2, position: 30.2)), .buffering)
        XCTAssertEqual(
            watchdog.consume(sample(at: 4, position: 30.4)),
            .recover(.clockStuck, resumeAt: 30)
        )
    }

    func testResetStopsCarryingOldEvidence() {
        var watchdog = HanimePlaybackWatchdog()
        watchdog.consume(sample(at: 0, position: 5))
        watchdog.consume(sample(at: 2, position: 7, frames: 0))
        watchdog.reset(at: nil)
        XCTAssertEqual(watchdog.consume(sample(at: 4, position: 9, frames: 0)), .none)
        XCTAssertEqual(watchdog.consume(sample(at: 6, position: 11, frames: 0)), .buffering)
    }

    func testRecoveryBudgetIsBounded() {
        let monitor = HanimeStallMonitor()
        for _ in 1...HanimeStallMonitor.maxRecoveries {
            XCTAssertTrue(monitor.noteRecovery())
        }
        XCTAssertFalse(monitor.noteRecovery(), "recovery loops must end in a visible failure")
        XCTAssertEqual(monitor.recoveries, HanimeStallMonitor.maxRecoveries)
        monitor.resetBudget()
        XCTAssertEqual(monitor.recoveries, 0)
        XCTAssertTrue(monitor.noteRecovery())
    }
}
