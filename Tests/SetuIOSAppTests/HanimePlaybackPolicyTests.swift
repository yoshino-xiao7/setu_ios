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

    func testStartsOnHLSTheWayTheSitePlayerDoes() {
        let mp4 = stream("1080p", "a")
        let hls = HanimeStream(
            quality: "HLS",
            url: URL(string: "https://vdownload.hembed.com/video/_hls/show.m3u8")!,
            isHLS: true
        )
        let wifi = HanimeRenditionPolicy.budget(isExpensiveNetwork: false)
        XCTAssertEqual(wifi.hlsPeakBitRate, 0, "Wi-Fi 不给 HLS 设码率上限，避免混淆结论")
        XCTAssertEqual(HanimeRenditionPolicy.pickStream(in: [mp4, hls], budget: wifi), hls)
    }

    func testFullscreenDetachesInlineRenderingSurface() {
        XCTAssertTrue(HanimeRenderingPolicy.showsInlinePlayer(isFullscreenPresented: false))
        XCTAssertFalse(
            HanimeRenderingPolicy.showsInlinePlayer(isFullscreenPresented: true),
            "同一个 AVPlayer 不能同时挂在小窗和全屏两个 AVKit 渲染面上"
        )
    }

    func testMediaServicesResetRebuildsPlayerInsteadOfLoweringQuality() {
        let reset = NSError(
            domain: AVFoundationErrorDomain,
            code: AVError.Code.mediaServicesWereReset.rawValue
        )
        XCTAssertEqual(HanimePlayerFailureDisposition.classify(reset), .rebuildPlayer)
        XCTAssertEqual(
            HanimePlayerFailureDisposition.classify(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)),
            .tryAnotherSource
        )
    }

    func testTruncatedHLSAddressIsNotPreferred() {
        let mp4 = stream("1080p", "a")
        let fake = HanimeStream(
            quality: "HLS",
            url: URL(string: "https://vdownload.hembed.com/video/_hls/show")!,
            isHLS: true
        )
        let wifi = HanimeRenditionPolicy.budget(isExpensiveNetwork: false)
        XCTAssertEqual(HanimeRenditionPolicy.pickStream(in: [mp4, fake], budget: wifi)?.url, mp4.url)
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

    func testAlternativeStreamPrefersAnotherFileAtTheSameRank() {
        let high = stream("1080p", "a")
        let mid = stream("720p", "b")
        let midTwin = stream("720p", "c")
        let low = stream("480p", "d")
        let streams = [high, mid, midTwin, low]
        // 真机日志：冻结时 60 秒缓冲充足且 720p/480p 同位都卡 —— 坏的是文件，不是码率。
        XCTAssertEqual(
            HanimeRenditionPolicy.alternativeStream(than: mid, in: streams, excluding: [])?.url,
            midTwin.url
        )
        XCTAssertEqual(
            HanimeRenditionPolicy.alternativeStream(than: mid, in: streams, excluding: [midTwin.id])?.quality,
            "480p", "没有同档备用镜像时才降清晰度"
        )
        XCTAssertNil(HanimeRenditionPolicy.alternativeStream(than: high, in: [high], excluding: []))
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

    func testFailedFallbackDoesNotUpgradeRendition() {
        let high = stream("1080p", "a")
        let mid = stream("720p", "b")
        let low = stream("480p", "c")
        // 刚因停滞降到 720p 后不要把用户弹回 1080p。
        XCTAssertEqual(
            HanimePlayerReload.nextPlayable(after: mid, in: [high, mid, low], excluding: [mid.id])?.quality,
            "480p"
        )
        // 更低档没了才允许回升，否则无片可播。
        XCTAssertEqual(
            HanimePlayerReload.nextPlayable(after: low, in: [high, mid, low], excluding: [low.id])?.quality,
            "1080p"
        )
    }

    // MARK: - Recovery ladder

    func testStallStartsWithInPlaceResyncNotATeardown() {
        let high = stream("1080p", "a")
        let mid = stream("720p", "b")
        let step = HanimeRecoveryPlan.step(
            reason: .videoFrozen,
            current: high,
            streams: [high, mid],
            skipped: [],
            refreshed: false,
            canRefresh: true,
            canNudge: true
        )
        XCTAssertEqual(step, .resumeInPlace, "任何停滞都先试不摧毁 UI 的原地重同步")
    }

    func testStallSwitchesTwinSourceAfterTheNudgeWasUsed() {
        let high = stream("1080p", "a")
        let twin = stream("1080p", "b")
        let step = HanimeRecoveryPlan.step(
            reason: .videoFrozen,
            current: high,
            streams: [high, twin],
            skipped: [high.id],
            refreshed: false,
            canRefresh: true,
            canNudge: false
        )
        XCTAssertEqual(step, .switchTo(twin), "重同步无效时先换同清晰度另一条源")
    }

    func testStallRefreshesLinksOnlyAfterEverySourceIsSpent() {
        let low = stream("480p", "a")
        let step = HanimeRecoveryPlan.step(
            reason: .stalledTooLong,
            current: low,
            streams: [low],
            skipped: [],
            refreshed: false,
            canRefresh: true,
            canNudge: false
        )
        XCTAssertEqual(step, .refreshLinks)
    }

    func testDecodeStallWithSingleRenditionNudgesBeforeRefreshing() {
        let only = stream("1080p", "a")
        let step = HanimeRecoveryPlan.step(
            reason: .videoFrozen,
            current: only,
            streams: [only],
            skipped: [],
            refreshed: false,
            canRefresh: true,
            canNudge: true
        )
        XCTAssertEqual(step, .resumeInPlace)
    }

    func testStallOnLowestRenditionRefreshesLinksOnce() {
        let low = stream("480p", "a")
        let step = HanimeRecoveryPlan.step(
            reason: .videoFrozen,
            current: low,
            streams: [low],
            skipped: [low.id],
            refreshed: false,
            canRefresh: true,
            canNudge: false
        )
        XCTAssertEqual(step, .refreshLinks)
    }

    func testRefreshedLinksSwitchSourceWhenStallsContinue() {
        let low = stream("480p", "a")
        let other = stream("480p", "b")
        let step = HanimeRecoveryPlan.step(
            reason: .videoFrozen,
            current: low,
            streams: [low, other],
            skipped: [low.id],
            refreshed: true,
            canRefresh: true,
            canNudge: false
        )
        XCTAssertEqual(step, .switchTo(other))
    }

    func testNoLeverLeftHandsFailureToUser() {
        let only = stream("480p", "a")
        let step = HanimeRecoveryPlan.step(
            reason: .videoFrozen,
            current: only,
            streams: [only],
            skipped: [only.id],
            refreshed: true,
            canRefresh: true,
            canNudge: false
        )
        XCTAssertEqual(step, .giveUp)
    }

    func testAssetCacheKeepsOneProbedAssetPerURL() {
        let cache = HanimeAssetCache()
        let first = URL(string: "https://cdn.example.invalid/a.mp4")!
        let second = URL(string: "https://cdn.example.invalid/b.mp4")!
        XCTAssertTrue(cache.asset(for: first, options: nil) === cache.asset(for: first, options: nil))
        XCTAssertFalse(cache.asset(for: second, options: nil) === cache.asset(for: first, options: nil))
        XCTAssertTrue(cache.asset(for: first, options: nil) === cache.asset(for: first, options: nil))
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

    func testNoFramesBeforePlaybackIsMovingIsNotAColdFreeze() {
        var watchdog = HanimePlaybackWatchdog()
        watchdog.consume(sample(at: 0, position: 10))
        // 重挂后的冷启动窗口：位置不动也没帧，不能当成 videoFrozen。
        for at in stride(from: 2.0, through: 10.0, by: 2.0) {
            XCTAssertEqual(watchdog.consume(sample(at: at, position: 10, frames: 0)), .none,
                           "startup with no motion yet @\(at)")
        }
        XCTAssertEqual(watchdog.consume(sample(at: 12, position: 10, frames: 0)),
                       .recover(.clockStuck, resumeAt: 10),
                       "a clock reporting .playing but never moving is still a stall")
    }

    func testMovingClockWithNoFramesIsAFreeze() {
        var watchdog = HanimePlaybackWatchdog()
        watchdog.consume(sample(at: 0, position: 10))
        XCTAssertEqual(watchdog.consume(sample(at: 2, position: 12, frames: 0)), .buffering)
        XCTAssertEqual(watchdog.consume(sample(at: 4, position: 14, frames: 0)),
                       .recover(.videoFrozen, resumeAt: 10))
    }

    func testRecoveryBudgetIsBounded() {
        let monitor = HanimeStallMonitor()
        for index in 1...HanimeStallMonitor.maxRecoveries {
            XCTAssertTrue(monitor.noteRecovery(now: Double(index)), "attempt \(index)")
        }
        // 回归用例：被拒绝的请求不能推动回充时钟，否则 backoff 永远等不到重试（iPad 日志里
        // recoveries=3 连报 90 秒，用户就对着静帧听了 90 秒音频）。
        for refusal in stride(from: 20.0, through: 90.0, by: 10.0) {
            XCTAssertFalse(monitor.noteRecovery(now: refusal), "budget spent @\(refusal)")
        }
        XCTAssertEqual(monitor.recoveries, HanimeStallMonitor.maxRecoveries)
        XCTAssertTrue(monitor.noteRecovery(now: 3 + HanimeStallMonitor.recoveryRechargeSeconds),
                      "a spent attempt comes back with time so the watchdog never dies")
        monitor.resetBudget()
        XCTAssertEqual(monitor.recoveries, 0)
        XCTAssertTrue(monitor.noteRecovery(now: 999))
    }
}
