import AVFoundation
import CoreVideo
import Foundation
import Network
import SetuIOSCore

// Direct-connect playback of a site MP4 has no adaptive variants, so a video track can
// starve while audio keeps the master clock running: the picture holds its last frame,
// the scrubber keeps moving, and `status` never becomes `.failed`. Everything below keeps
// rendition choice, buffering hints and stall recovery in one testable place.

struct HanimePlaybackBudget: Equatable {
    /// Highest video height allowed when playback starts; nil keeps the site's top rendition.
    var startHeightLimit: Int?
    /// Buffer target in seconds. A tighter target turns a silent video-only desync into a
    /// stall the watchdog can see. AVFoundation treats it as a hint.
    var forwardBufferSeconds: TimeInterval
    /// Peak bit rate applied to HLS items only; a single-rendition MP4 has nothing to switch to.
    var hlsPeakBitRate: Double
}

/// Mirror of `CloudVideoUploadPathMonitor`: cheap read-only snapshot, updated off-main.
final class HanimeNetworkProfile: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "icu.yukiryou.setuios.hanime-playback-path")
    private(set) var isExpensive = false

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.isExpensive = path.isExpensive || path.usesInterfaceType(.cellular)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

enum HanimeRenditionPolicy {
    static let cellularHeightLimit = 720
    /// Rank is the pixel height when the site exposes it; HLS without a height is 1,
    /// an unknown MP4 is 0. Anything <= 1 cannot be compared as a resolution.
    private static let knownHeightFloor = 1

    static func budget(isExpensiveNetwork: Bool) -> HanimePlaybackBudget {
        if isExpensiveNetwork {
            return HanimePlaybackBudget(
                startHeightLimit: cellularHeightLimit,
                forwardBufferSeconds: 8,
                hlsPeakBitRate: 2_600_000
            )
        }
        return HanimePlaybackBudget(
            startHeightLimit: nil,
            forwardBufferSeconds: 15,
            hlsPeakBitRate: 6_000_000
        )
    }

    static func pickStream(in streams: [HanimeStream], budget: HanimePlaybackBudget) -> HanimeStream? {
        guard let limit = budget.startHeightLimit else { return HanimeStream.preferred(in: streams) }
        let heights = streams.filter { $0.rank > knownHeightFloor && !$0.isHLS }
        if let capped = heights.filter({ $0.rank <= limit }).max(by: { $0.rank < $1.rank }) {
            return capped
        }
        // Only higher renditions exist: take the lowest one instead of the top rank.
        if let lowest = heights.min(by: { $0.rank < $1.rank }) {
            return lowest
        }
        return HanimeStream.preferred(in: streams)
    }

    /// Next rendition strictly below `stream`, skipping failed and already-tried sources.
    static func lowerStream(
        than stream: HanimeStream?,
        in streams: [HanimeStream],
        excluding skipped: Set<String>
    ) -> HanimeStream? {
        let candidates = streams.filter { !skipped.contains($0.id) && $0.id != stream?.id }
        guard let rank = stream?.rank, rank > knownHeightFloor else {
            // Nothing to compare against: any other source is still a change of origin.
            return candidates.min(by: { $0.rank < $1.rank })
        }
        return candidates
            .filter { $0.rank < rank }
            .max(by: { $0.rank < $1.rank })
    }

    static func apply(_ budget: HanimePlaybackBudget, to item: AVPlayerItem, isHLS: Bool) {
        if budget.forwardBufferSeconds > 0 {
            item.preferredForwardBufferDuration = budget.forwardBufferSeconds
        }
        guard isHLS, budget.hlsPeakBitRate > 0 else { return }
        item.preferredPeakBitRate = budget.hlsPeakBitRate
        item.preferredPeakBitRateForExpensiveNetworks = budget.hlsPeakBitRate
    }
}

enum HanimeRecoveryStep: Equatable {
    case switchTo(HanimeStream)
    case refreshLinks
    case giveUp

    /// Log-safe description: never leaks a signed direct link.
    var logLabel: String {
        switch self {
        case let .switchTo(stream): "switchTo(\(stream.quality))"
        case .refreshLinks: "refreshLinks"
        case .giveUp: "giveUp"
        }
    }
}

enum HanimeRecoveryPlan {
    /// Stall recovery ladder: shed resolution first (free, no extra site request), then ask
    /// for fresh direct links, then change source, and only then hand the failure to the user.
    static func step(
        current: HanimeStream?,
        streams: [HanimeStream],
        skipped: Set<String>,
        refreshed: Bool,
        canRefresh: Bool
    ) -> HanimeRecoveryStep {
        if let lower = HanimeRenditionPolicy.lowerStream(
            than: current,
            in: streams,
            excluding: skipped
        ) {
            return .switchTo(lower)
        }
        if canRefresh && !refreshed {
            return .refreshLinks
        }
        // Links were already refreshed: the remaining lever is a different source.
        let remaining = streams.filter { !skipped.contains($0.id) && $0.id != current?.id }
        guard let fallback = remaining.min(by: { $0.rank < $1.rank }) ?? remaining.first else {
            return .giveUp
        }
        return .switchTo(fallback)
    }
}

struct HanimePlaybackSample {
    var at: TimeInterval
    var positionSeconds: Double
    /// `timeControlStatus == .playing`.
    var isClockRunning: Bool
    /// `timeControlStatus == .waitingToPlayAtSpecifiedRate`; false for a user pause.
    var isWaitingToPlay: Bool
    /// Frames the video output produced in this window; nil when the signal is unavailable.
    var renderedFrames: Int?
    var bufferedAheadSeconds: Double
}

enum HanimeRecoveryReason: Equatable {
    /// Clock runs and time advances, but no video frame is produced.
    case videoFrozen
    /// Clock runs, time advances, and no media bytes are arriving.
    case supplyStarved
    /// Playing state is reported, yet the position does not advance.
    case clockStuck
    /// The system stall signal did not clear.
    case stalledTooLong
}

enum HanimeWatchdogAction: Equatable {
    /// Not enough evidence yet; leave the UI alone.
    case none
    /// Audio and clock are fine, nothing new to report.
    case healthy
    case buffering
    case recover(HanimeRecoveryReason, resumeAt: Double)
}

extension HanimeRecoveryReason {
    var logLabel: String {
        switch self {
        case .videoFrozen: "videoFrozen"
        case .supplyStarved: "supplyStarved"
        case .clockStuck: "clockStuck"
        case .stalledTooLong: "stalledTooLong"
        }
    }
}

/// Windowed watchdog over `AVPlayerItem` samples. Only classifies; the view owns the retry
/// budget, so the counters restart on every dispatched recovery.
struct HanimePlaybackWatchdog {
    var sampleInterval: TimeInterval = 2
    var windowsBeforeRecovery = 2
    var stallTimeoutSeconds: TimeInterval = 12
    /// Guard against a window where nothing at all is known to be fetched ahead.
    private var minBufferedAhead: Double { max(sampleInterval * 1.5, 1) }

    private var previous: HanimePlaybackSample?
    private var lastHealthyPosition: Double?
    private var badWindows = 0
    private var stuckWindows = 0
    private var waitingSince: TimeInterval?
    private var pendingBuffering = false

    mutating func reset(at positionSeconds: Double?) {
        previous = nil
        lastHealthyPosition = positionSeconds
        badWindows = 0
        stuckWindows = 0
        waitingSince = nil
        pendingBuffering = false
    }

    mutating func consume(_ sample: HanimePlaybackSample) -> HanimeWatchdogAction {
        defer { previous = sample }
        guard let previous else {
            if sample.isClockRunning { lastHealthyPosition = sample.positionSeconds }
            return pendingBuffering ? .buffering : .none
        }
        let elapsed = sample.at - previous.at
        guard elapsed > 0 else { return .none }
        let advanced = max(sample.positionSeconds - previous.positionSeconds, 0)

        guard sample.isClockRunning else {
            // A real system stall stops the clock as well; surface buffering and only act
            // after it refuses to clear. A user pause must never look like a stall.
            stuckWindows = 0
            badWindows = 0
            guard sample.isWaitingToPlay else {
                waitingSince = nil
                pendingBuffering = false
                return .healthy
            }
            waitingSince = waitingSince ?? previous.at
            pendingBuffering = true
            let waited = sample.at - (waitingSince ?? sample.at)
            guard waited >= stallTimeoutSeconds else { return .buffering }
            waitingSince = sample.at
            return .recover(.stalledTooLong, resumeAt: lastHealthyPosition ?? sample.positionSeconds)
        }
        waitingSince = nil

        if advanced < elapsed * 0.4 {
            stuckWindows += 1
            badWindows = 0
            guard stuckWindows >= windowsBeforeRecovery else { return .buffering }
            stuckWindows = 0
            return .recover(.clockStuck, resumeAt: lastHealthyPosition ?? sample.positionSeconds)
        }

        let frozen = sample.renderedFrames == 0
        let starving = sample.renderedFrames == nil && sample.bufferedAheadSeconds < minBufferedAhead
        guard frozen || starving else {
            badWindows = 0
            lastHealthyPosition = sample.positionSeconds
            pendingBuffering = false
            return .healthy
        }
        badWindows += 1
        guard badWindows >= windowsBeforeRecovery else { return .buffering }
        badWindows = 0
        return .recover(
            frozen ? .videoFrozen : .supplyStarved,
            resumeAt: lastHealthyPosition ?? sample.positionSeconds
        )
    }
}

/// Owns the stall machinery for one player view. Callers stay on the main actor; it is a
/// reference type so per-window bookkeeping does not invalidate the SwiftUI view.
final class HanimeStallMonitor {
    static let sampleInterval: TimeInterval = 2
    static let maxRecoveries = 3
    /// Resume slightly behind the last healthy position: audio may have drifted ahead.
    static let rewindSeconds: TimeInterval = 2

    let frames = HanimeVideoFrameProbe()
    private var watchdog = HanimePlaybackWatchdog(sampleInterval: HanimeStallMonitor.sampleInterval)
    private(set) var recoveries = 0

    /// Monotonic clock, so a background pause never looks like a stalled window.
    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// false once the budget is spent, so the caller hands the failure to the user.
    func noteRecovery() -> Bool {
        guard recoveries < Self.maxRecoveries else { return false }
        recoveries += 1
        return true
    }

    func resetForNewPlayback(at positionSeconds: Double?) {
        watchdog.reset(at: positionSeconds)
    }

    func resetBudget() {
        recoveries = 0
        watchdog.reset(at: nil)
    }

    func consume(_ sample: HanimePlaybackSample) -> HanimeWatchdogAction {
        watchdog.consume(sample)
    }
}

/// Counts rendered frames for one sampling window. A tiny `AVPlayerItemVideoOutput` is the
/// only public way to ask "is video actually arriving" while AVKit keeps rendering the item.
final class HanimeVideoFrameProbe {
    private static let outputAttributes: [String: Any] = [
        kCVPixelBufferWidthKey as String: 16,
        kCVPixelBufferHeightKey as String: 9,
    ]

    private var output: AVPlayerItemVideoOutput?
    private weak var attachedItem: AVPlayerItem?

    /// One output per item; `suppressesPlayerRendering` stays off so AVKit keeps drawing.
    func attach(to item: AVPlayerItem) {
        guard attachedItem !== item else { return }
        let created = AVPlayerItemVideoOutput(pixelBufferAttributes: Self.outputAttributes)
        item.add(created)
        output = created
        attachedItem = item
    }

    /// nil when the signal is unavailable, so the watchdog falls back to supply signals.
    func framesInWindow(itemTime: CMTime) -> Int? {
        guard let item = attachedItem, let output,
              item.status == .readyToPlay, item.presentationSize.width > 1 else { return nil }
        guard output.hasNewPixelBuffer(forItemTime: itemTime) else { return 0 }
        output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        return 1
    }
}

enum HanimePlaybackProbe {
    /// Seconds of media already fetched ahead of the playhead.
    static func bufferedAheadSeconds(in item: AVPlayerItem) -> Double {
        let now = item.currentTime().seconds
        guard now.isFinite else { return 0 }
        let end = item.loadedTimeRanges
            .map { $0.timeRangeValue }
            .filter { $0.isValid }
            .reduce(-Double.infinity) { max($0, $1.start.seconds + $1.duration.seconds) }
        guard end.isFinite else { return 0 }
        return max(end - now, 0)
    }

    #if DEBUG && os(iOS)
    /// Diagnostics only. Reports counters, never the signed direct link.
    static func accessLogSummary(for item: AVPlayerItem) async -> String {
        guard #available(iOS 27.0, *) else { return "accessLog=n/a" }
        let event = await item.accessLog?.events.last
        guard let event else { return "accessLog=none" }
        return "stalls=\(event.numberOfStalls) dropped=\(event.numberOfDroppedVideoFrames) "
            + "requests=\(event.numberOfMediaRequests) observedKbps=\(Int(event.observedBitrate / 1000)) "
            + "indicatedKbps=\(Int(event.indicatedBitrate / 1000)) "
            + "downloadedSeconds=\(Int(event.segmentsDownloadedDuration))"
    }
    #endif
}
