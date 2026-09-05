#if DEBUG && os(iOS)
import AVFoundation
import MediaPlayer
import SwiftUI

/// Opt-in, read-only hardware acceptance telemetry. Never configures or overrides audio routes.
/// Only enabled with the isolated v1 fixture launch arguments; no credentials or real-library data.
struct AirPlayHardwareAudit: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let player: MusicPlaybackController
    let lyrics: NowPlayingLyricsModel
    @State private var json = "{}"
    @State private var routeEvents = 0
    @State private var lastReason = 0
    @State private var playerIDs: Set<String> = []
    private var enabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-ui-testing-airplay-hardware") && args.contains("-ui-testing-root-player")
    }
    func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) {
            if enabled {
                Text("AirPlay hardware audit")
                    .font(.system(size: 1)).frame(width: 2, height: 2)
                    .accessibilityIdentifier("airplay.audit").accessibilityValue(json)
                    .task(id: colorScheme) {
                        while !Task.isCancelled {
                            snapshot()
                            try? await Task.sleep(nanoseconds: 500_000_000)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
                        routeEvents += 1
                        lastReason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.intValue ?? 0
                        snapshot()
                    }
            }
        }
    }
    private func snapshot() {
        let audio = AVAudioSession.sharedInstance()
        let av = player.player
        if let av { playerIDs.insert(String(describing: ObjectIdentifier(av))) }
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        let elapsed = av?.currentTime().seconds ?? player.currentTimeSeconds
        let finite = elapsed.isFinite ? elapsed : 0
        let nowElapsed = (info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber)?.doubleValue ?? -1
        let lyricIndex: Int
        if case .loaded(let lines) = lyrics.state { lyricIndex = LyricParser.activeIndex(in: lines, at: finite) ?? -1 }
        else { lyricIndex = -1 }
        let payload: [String: Any] = [
            "appearance": colorScheme == .dark ? "dark" : "light",
            "route": audio.currentRoute.outputs.map { $0.portType.rawValue },
            "targetMac": audio.currentRoute.outputs.contains { $0.portType == .airPlay && $0.portName == "雪涼的MacBook Neo" },
            "routeEvents": routeEvents, "routeReason": lastReason,
            "track": player.currentTrack?.id.legacyID ?? -1,
            "queue": player.queueTracks.compactMap { $0.id.legacyID },
            "index": player.currentQueueIndex ?? -1,
            "phase": String(describing: player.phase), "playing": player.isPlaying,
            "time": finite, "controllerTime": player.currentTimeSeconds,
            "rate": av?.rate ?? 0, "buffering": player.isBuffering,
            "error": player.playbackError != nil,
            "avPlayerInstancesObserved": playerIDs.count,
            "miniInstances": MusicPerformanceProbe.shared.playerCount,
            "titleMatches": (info[MPMediaItemPropertyTitle] as? String) == player.currentTrack?.title,
            "artistMatches": (info[MPMediaItemPropertyArtist] as? String) == player.currentTrack?.artist,
            "nowPlayingElapsed": nowElapsed,
            "sleepTimer": player.sleepTimerTitle != nil,
            "parses": MusicPerformanceProbe.shared.parseCount, "lyricIndex": lyricIndex,
            "urlRequests": AirPlayFixtureCounters.urlRequests
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) else { return }
        json = value
        print("AIRPLAY_AUDIT " + value)
    }
}

/// Counts only the opt-in fixture URL endpoint, never request bodies or URLs.
enum AirPlayFixtureCounters {
    private static let lock = NSLock()
    private static var count = 0
    static var urlRequests: Int { lock.withLock { count } }
    static func requested() { lock.withLock { count += 1 } }
}
#endif
