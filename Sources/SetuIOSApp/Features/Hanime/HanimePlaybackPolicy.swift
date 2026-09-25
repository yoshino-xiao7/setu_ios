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
            hlsPeakBitRate: 0
        )
    }

    /// A scraped m3u8 is only trustworthy when the path really ends in the playlist extension:
    /// the site also exposes truncated `/_hls/…` addresses with no suffix, which cannot play.
    static func playableHLSStream(in streams: [HanimeStream]) -> HanimeStream? {
        streams.first { $0.isHLS && $0.url.path.lowercased().hasSuffix(".m3u8") }
    }

    static func pickStream(in streams: [HanimeStream], budget: HanimePlaybackBudget) -> HanimeStream? {
        // The site's own player streams HLS and plays smoothly in Safari on the same link, while
        // our MP4 picks come from the download pages: files that are not interleaved for
        // streaming are what let audio run ahead of video bytes. So start on HLS whenever a
        // usable variant exists, and keep the MP4 renditions as the fallback ladder.
        if let hls = playableHLSStream(in: streams) { return hls }
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

    /// Next stream to try when playback is unhealthy. The iPad log settled the order: a freeze
    /// persisted with 60s of buffered media across 1080p, 720p and 480p, so the bitrate is not
    /// the problem — the file is. Prefer another URL at the same rank (the site exposes two
    /// mirrors per quality), then a lower rank, then anything else.
    static func alternativeStream(
        than stream: HanimeStream?,
        in streams: [HanimeStream],
        excluding skipped: Set<String>
    ) -> HanimeStream? {
        let candidates = streams.filter { !skipped.contains($0.id) && $0.id != stream?.id }
        guard let rank = stream?.rank, rank > knownHeightFloor else {
            return candidates.min(by: { $0.rank < $1.rank })
        }
        if let twin = candidates.first(where: { $0.rank == rank }) { return twin }
        return candidates
            .filter { $0.rank < rank }
            .max(by: { $0.rank < $1.rank }) ?? candidates.first
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

enum HanimeRenderingPolicy {
    /// One AVPlayer must only have one active AVKit rendering surface. Keeping the inline
    /// VideoPlayer alive behind a fullscreen AVPlayerViewController can reset the video decoder
    /// while the audio clock continues normally.
    static func showsInlinePlayer(isFullscreenPresented: Bool) -> Bool {
        !isFullscreenPresented
    }
}

enum HanimePlayerFailureDisposition: Equatable {
    case rebuildPlayer
    case tryAnotherSource

    static func classify(_ error: Error?) -> Self {
        let error = error as NSError?
        if error?.domain == AVFoundationErrorDomain,
           error?.code == AVError.Code.mediaServicesWereReset.rawValue {
            return .rebuildPlayer
        }
        return .tryAnotherSource
    }
}

/// Re-opening the same URL should not re-probe the MP4 header: that probe is exactly the
/// multi-second stretch where the scrubber and the total duration read as empty.
/// Only the most recent asset is kept, so stale signed links never pile up.
final class HanimeAssetCache {
    private var stored: (url: URL, asset: AVURLAsset)?

    func asset(for url: URL, options: [String: Any]?) -> AVURLAsset {
        if let stored, stored.url == url { return stored.asset }
        let created = AVURLAsset(url: url, options: options)
        stored = (url, created)
        return created
    }
}

enum HanimeRecoveryStep: Equatable {
    /// Re-open the byte stream in place with a seek: keeps the item, its duration and AVKit's
    /// controls alive. Rebuilding the item wipes the scrubber and the total time for seconds.
    case resumeInPlace
    case switchTo(HanimeStream)
    case refreshLinks
    case giveUp

    /// Log-safe description: never leaks a signed direct link.
    var logLabel: String {
        switch self {
        case .resumeInPlace: "resumeInPlace"
        case let .switchTo(stream): "switchTo(\(stream.quality))"
        case .refreshLinks: "refreshLinks"
        case .giveUp: "giveUp"
        }
    }
}

enum HanimeRecoveryPlan {
    /// Cheapest and least visible first, because the log showed a bitrate-independent freeze:
    /// 1. re-sync in place with a forward seek — keeps the item, duration and controls; a
    ///    backward seek walks straight back into the same bad sample (that loop is in the log).
    /// 2. another URL at the same rank — a different mirror is the most likely cure for a bad file.
    /// 3. a fresh direct link, then the lowest remaining rank.
    static func step(
        reason: HanimeRecoveryReason,
        current: HanimeStream?,
        streams: [HanimeStream],
        skipped: Set<String>,
        refreshed: Bool,
        canRefresh: Bool,
        canNudge: Bool
    ) -> HanimeRecoveryStep {
        if canNudge { return .resumeInPlace }
        if let alternative = HanimeRenditionPolicy.alternativeStream(
            than: current,
            in: streams,
            excluding: skipped
        ) {
            return .switchTo(alternative)
        }
        if canRefresh && !refreshed { return .refreshLinks }
        return .giveUp
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
    /// Video frames dropped inside this window; nil when the platform exposes no counter.
    var droppedVideoFrames: Int?
    var bufferedAheadSeconds: Double
}

enum HanimeRecoveryReason: Equatable {
    /// Clock runs and time advances, but no video frame is produced.
    case videoFrozen
    /// Clock runs, time advances, and no media bytes are arriving.
    case supplyStarved
    /// Video is displayed but frames keep getting dropped: decode can't keep up.
    case frameRateCollapse
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
        case .frameRateCollapse: "frameRateCollapse"
        case .clockStuck: "clockStuck"
        case .stalledTooLong: "stalledTooLong"
        }
    }
}

extension HanimeWatchdogAction {
    var logLabel: String {
        switch self {
        case .none: "none"
        case .healthy: "healthy"
        case .buffering: "buffering"
        case let .recover(reason, resumeAt):
            "recover(\(reason.logLabel) resume=\(String(format: "%.1f", resumeAt)))"
        }
    }
}

/// Windowed watchdog over `AVPlayerItem` samples. Only classifies; the view owns the retry
/// budget, so the counters restart on every dispatched recovery.
struct HanimePlaybackWatchdog {
    var sampleInterval: TimeInterval = 2
    /// Two *consecutive* empty windows (~4s) before acting. Device data: a self-healing hitch
    /// reads frames=0, then 1, then 0 again, so counting 2-in-3 windows would interrupt
    /// playback that recovers by itself. Keep the bar on continuity, not on density.
    var windowsBeforeRecovery = 2
    var stallTimeoutSeconds: TimeInterval = 12
    /// A dropped-frame burst is "卡" for the viewer but not an emergency: demand more
    /// evidence than for a hard freeze before interrupting playback.
    var collapseWindowsBeforeRecovery = 3
    var droppedFramesToCollapse = 24
    /// Guard against a window where nothing at all is known to be fetched ahead.
    private var minBufferedAhead: Double { max(sampleInterval * 1.5, 1) }

    private var previous: HanimePlaybackSample?
    private var lastHealthyPosition: Double?
    private var badWindows = 0
    private var stuckWindows = 0
    private var collapseWindows = 0
    private var waitingSince: TimeInterval?
    private var motionlessSince: TimeInterval?
    private var pendingBuffering = false
    /// Don't read "no frames" as a stall before the item has produced its first frame: after a
    /// recovery re-mount the next few windows legitimately have none, and both false positives in
    /// the iPad log started exactly there.
    private var armed = false

    mutating func reset(at positionSeconds: Double?) {
        previous = nil
        lastHealthyPosition = positionSeconds
        badWindows = 0
        stuckWindows = 0
        collapseWindows = 0
        waitingSince = nil
        motionlessSince = nil
        pendingBuffering = false
        armed = false
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
        // Arm only once playback demonstrably moves (a frame, or the clock advancing normally).
        if sample.renderedFrames ?? 0 >= 1 || advanced >= elapsed * 0.8 { armed = true }

        if advanced < elapsed * 0.4 {
            guard armed else {
                // Can't tell "still starting up" from "stuck" without evidence of motion, so use
                // the longer timeout instead of the 2-window rule. Without this, `clockStuck`
                // would be unreachable: it is by definition a clock that never advances.
                motionlessSince = motionlessSince ?? previous.at
                let motionless = sample.at - (motionlessSince ?? sample.at)
                guard motionless >= stallTimeoutSeconds else { return .none }
                motionlessSince = sample.at
                return .recover(.clockStuck, resumeAt: lastHealthyPosition ?? sample.positionSeconds)
            }
            motionlessSince = nil
            stuckWindows += 1
            badWindows = 0
            guard stuckWindows >= windowsBeforeRecovery else { return .buffering }
            stuckWindows = 0
            return .recover(.clockStuck, resumeAt: lastHealthyPosition ?? sample.positionSeconds)
        }
        motionlessSince = nil

        let frozen = sample.renderedFrames == 0
        let starving = sample.renderedFrames == nil && sample.bufferedAheadSeconds < minBufferedAhead
        guard frozen || starving else {
            // Nothing frozen, but a steady stream of dropped video frames is what a stalled
            // 1080p decode looks like to the viewer; only shedding resolution helps.
            if let dropped = sample.droppedVideoFrames, dropped >= droppedFramesToCollapse {
                collapseWindows += 1
                guard collapseWindows >= collapseWindowsBeforeRecovery else { return .none }
                collapseWindows = 0
                return .recover(.frameRateCollapse, resumeAt: lastHealthyPosition ?? sample.positionSeconds)
            }
            collapseWindows = 0
            badWindows = 0
            lastHealthyPosition = sample.positionSeconds
            pendingBuffering = false
            return .healthy
        }
        guard armed else { return .none }
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
    /// Attempts come back with time. The old "3 strikes and the watchdog stays off" was
    /// reproduced on iPad: after 05:33:10 the sampler never ran again, so every later stall
    /// (including one lasting 10+ seconds) went completely undetected.
    static let recoveryRechargeSeconds: TimeInterval = 90
    /// A freshly mounted item legitimately waits and produces no frames for several seconds, and
    /// every stall signal except this grace period used to fire inside it: three attempts burned
    /// in 45 seconds on iPad. Give a new item room to start before judging it.
    static let startupGraceSeconds: TimeInterval = 15

    let frames = HanimeVideoFrameProbe()
    private var watchdog = HanimePlaybackWatchdog(sampleInterval: HanimeStallMonitor.sampleInterval)
    private(set) var recoveries = 0
    private var droppedTotal: Int?
    private var lastRecoveryAt: TimeInterval?
    private(set) var mountedAt: TimeInterval?

    /// Monotonic clock, so a background pause never looks like a stalled window.
    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Called when a new item is installed; deliberately not touched by the sampler's own resets.
    func noteMount(now: TimeInterval) {
        mountedAt = now
    }

    func isWarmingUp(now: TimeInterval) -> Bool {
        guard let mountedAt else { return false }
        return now - mountedAt < Self.startupGraceSeconds
    }

    /// Per-window drop count from a cumulative counter; nil until two readings exist, and
    /// re-baselines whenever the log starts a new event or a new item was installed.
    func droppedDelta(current: Int?) -> Int? {
        defer { if let current { droppedTotal = current } }
        guard let current, let previous = droppedTotal, current >= previous else { return nil }
        return current - previous
    }

    /// false when the in-flight budget is spent; callers must back off and keep sampling.
    /// Only a dispatched recovery moves the clock — refreshing it on a refusal made the recharge
    /// unreachable and the watchdog sat at 3 strikes while the user watched a still image.
    func noteRecovery(now: TimeInterval) -> Bool {
        if let at = lastRecoveryAt, recoveries > 0, now - at >= Self.recoveryRechargeSeconds {
            recoveries -= 1
        }
        guard recoveries < Self.maxRecoveries else { return false }
        recoveries += 1
        lastRecoveryAt = now
        return true
    }

    func resetForNewPlayback(at positionSeconds: Double?) {
        droppedTotal = nil
        watchdog.reset(at: positionSeconds)
    }

    func resetBudget() {
        recoveries = 0
        lastRecoveryAt = nil
        mountedAt = nil
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
        detach()
        let created = AVPlayerItemVideoOutput(pixelBufferAttributes: Self.outputAttributes)
        item.add(created)
        output = created
        attachedItem = item
    }

    func detach() {
        if let attachedItem, let output {
            attachedItem.remove(output)
        }
        output = nil
        attachedItem = nil
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
    /// Cumulative dropped video frames, when the platform exposes it. `AVPlayerItem.accessLog`
    /// only became an async accessor on iOS 27; older systems simply lose this signal.
    static func droppedVideoFramesTotal(in item: AVPlayerItem) async -> Int? {
        guard #available(iOS 27.0, *) else { return nil }
        let event = await item.accessLog?.events.last
        let dropped = event?.numberOfDroppedVideoFrames ?? -1
        return dropped >= 0 ? dropped : nil
    }

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

#if os(iOS)
/// An intermittent stall cannot be reproduced on demand, so the debug lines are mirrored into
/// the app container: use the app normally, then pull the evidence afterwards with
///
///   xcrun devicectl device copy from --device <id> \
///     --domain-type appDataContainer --domain-identifier icu.yukiryou.setuios \
///     --source Documents/hanime-playback.log --destination .
///
/// Compiled for debug iOS builds only, and it never stores a signed direct link.
final class HanimePlaybackLogFile {
    static let shared = HanimePlaybackLogFile()

    static let fileName = "hanime-playback.log"

    private let queue = DispatchQueue(label: "icu.yukiryou.setuios.hanime-playback-logfile")
    private let maximumBytes = 256 * 1024
    private let formatter = ISO8601DateFormatter()
    private let url: URL?

    private init() {
        url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Self.fileName)
        guard let url else { return }
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        queue.async {
            self.append("session os=\(system) app=\(version)(\(build))", to: url)
        }
    }

    func append(_ line: String) {
        guard let url else { return }
        queue.async { self.append(line, to: url) }
    }

    private func append(_ line: String, to url: URL) {
        let text = "\(formatter.string(from: Date())) \(line)\n"
        write(Data(text.utf8), to: url)
    }

    private func write(_ data: Data, to url: URL) {
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? data.write(to: url)
            return
        }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            try? data.write(to: url)
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > maximumBytes { trim(url) }
    }

    /// Keep the newest half, cut on a line boundary so the file stays greppable.
    private func trim(_ url: URL) {
        guard let all = try? Data(contentsOf: url), all.count > maximumBytes / 2 else { return }
        let from = all.index(all.endIndex, offsetBy: -(all.count / 2))
        let cut = all[from...].firstIndex(of: UInt8(ascii: "\n")) ?? from
        try? all[all.index(after: cut)...].write(to: url)
    }
}
#endif
