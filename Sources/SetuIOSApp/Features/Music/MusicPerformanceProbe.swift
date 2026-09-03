#if DEBUG
import Foundation
import SwiftUI
import AVFoundation
import os

/// Count-only diagnostics for local tests; no song, account, URL or credential data.
final class MusicPerformanceProbe: @unchecked Sendable {
    static let shared = MusicPerformanceProbe()
    // P0 permits signpost names here only. These are NOT emitted until the
    // corresponding call sites are authorized; never treat them as samples.
    enum SignpostName {
        static let musicHomeFirstPaint: StaticString = "MusicHomeFirstPaint"
        static let userNextIntent: StaticString = "UserNextIntent"
        static let queueTarget: StaticString = "QueueTarget"
        static let preparedItemLookup: StaticString = "PreparedItemLookup"
        static let playbackURL: StaticString = "PlaybackURL"
        static let playerItem: StaticString = "PlayerItem"
        static let replaceItem: StaticString = "ReplaceItem"
        static let sessionActivate: StaticString = "SessionActivate"
        static let playerStatus: StaticString = "PlayerStatus"
        static let firstPlayable: StaticString = "FirstPlayable"
        // First media-time progress is a proxy, not proof of audible output.
        static let firstFrame: StaticString = "FirstFrame"
        // Reserved for independently synchronized output capture only.
        static let audioOutputObserved: StaticString = "AudioOutputObserved"
    }
    private let lock = NSLock()
    private var players = 0
    private var parses = 0
    private var mvDetails = 0
    var playerCount: Int { lock.withLock { players } }
    var parseCount: Int { lock.withLock { parses } }
    var mvDetailCount: Int { lock.withLock { mvDetails } }
    func playerCreated() { lock.withLock { players += 1 } }
    func playerReleased() { lock.withLock { players -= 1 } }
    func lyricParsed() { lock.withLock { parses += 1 } }
    func mvDetailRequested() { lock.withLock { mvDetails += 1 } }
}

/// P0.1 diagnostics only. Never reads tracks/URLs or writes playback state.
/// MainActor matches the existing controller callbacks; no new observers/timers.
@MainActor
final class MusicPlaybackDiagnostics {
    private let log = OSLog(subsystem: "icu.yukiryou.setuios", category: "MusicPlaybackP01")
    private var id: OSSignpostID?
    private var queuedTransition = false

    private func start(_ name: StaticString, value: Int32 = 0) {
        finish("DiagnosticSuperseded")
        guard log.signpostsEnabled else { return }
        let nextID = OSSignpostID(log: log)
        id = nextID
        os_signpost(.begin, log: log, name: "PlaybackSegments", signpostID: nextID)
        mark(name, value: value)
    }

    func nextRequested(offset: Int, automatic: Bool) {
        // 1 = user next, -1 = user previous, 2 = automatic; no track identifiers.
        start("NextTrackRequested", value: automatic ? 2 : offset > 0 ? 1 : -1)
    }

    func queueResolved() {
        if id == nil { start("QueueRetryStarted") }
        queuedTransition = true
        mark("QueueResolved")
    }

    func transitionStarted() {
        if !queuedTransition { start("NonQueueTransition") }
        queuedTransition = false
        mark("TransitionStarted")
    }

    func mark(_ name: StaticString, value: Int32 = 0) {
        guard let id else { return }
        os_signpost(.event, log: log, name: name, signpostID: id, "%{public}d", value)
    }

    func preparedMiss(forced: Bool) {
        // force short-circuits consume in the original condition, so it is not a miss.
        if forced { mark("PreparedLookupBypassed") }
        else { mark("PreparedMiss") }
    }

    func itemReady(reused: Bool, status: AVPlayerItem.Status) {
        // Constructed/reused object, NOT a claim that AVPlayerItem is readyToPlay.
        mark("PlayerItemReady", value: reused ? 1 : 0)
        itemStatus(status)
    }

    func itemStatus(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay: mark("PlayerReady")
        case .unknown: mark("PlayerItemUnknown")
        case .failed: mark("PlayerItemFailed")
        @unknown default: mark("PlayerItemStatusUnknown")
        }
    }

    func playerStatus(_ status: AVPlayer.TimeControlStatus, waitingReason: AVPlayer.WaitingReason?) {
        switch status {
        case .waitingToPlayAtSpecifiedRate:
            mark("PlayerWaiting")
            if waitingReason == .toMinimizeStalls { mark("WaitingToMinimizeStalls") }
            else if waitingReason == .evaluatingBufferingRate { mark("WaitingEvaluatingBuffering") }
            else if waitingReason == .noItemToPlay { mark("WaitingNoItem") }
            else { mark("WaitingReasonUnknown") }
        case .paused: mark("PlayerPaused")
        case .playing: mark("PlayerPlayingState")
        @unknown default: mark("PlayerStateUnknown")
        }
    }

    func replaceBegin(installing: Bool) {
        guard let id else { return }
        mark("ReplaceCurrentItemBegin", value: installing ? 1 : 0)
        os_signpost(.begin, log: log, name: "ReplaceCurrentItem", signpostID: id)
    }

    func replaceEnd(installing: Bool) {
        guard let id else { return }
        os_signpost(.end, log: log, name: "ReplaceCurrentItem", signpostID: id)
        mark("ReplaceCurrentItemEnd", value: installing ? 1 : 0)
    }

    func playing() {
        mark("TrackPlaying")
        finish("DiagnosticCompleted")
    }

    func finish(_ reason: StaticString) {
        guard let id else { return }
        mark(reason)
        os_signpost(.end, log: log, name: "PlaybackSegments", signpostID: id)
        self.id = nil
        queuedTransition = false
    }
}

final class MusicMiniPlayerLifetime: ObservableObject {
    let id = UUID()
    init() { MusicPerformanceProbe.shared.playerCreated() }
    deinit { MusicPerformanceProbe.shared.playerReleased() }
    var diagnosticValue: String { "instances=\(MusicPerformanceProbe.shared.playerCount);identity=\(id)" }
}
#endif
