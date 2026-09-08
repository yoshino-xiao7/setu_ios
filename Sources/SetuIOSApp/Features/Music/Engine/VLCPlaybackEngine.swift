#if canImport(MobileVLCKit)
import Foundation
import MobileVLCKit

@MainActor
final class VLCPlaybackEngine: NSObject, MusicPlaybackEngine, VLCMediaPlayerDelegate {
    private var player: VLCMediaPlayer?
    private var mediaID = UUID()
    private var seekID = UUID()
    private var observedTimeRevision = 0
    private(set) var snapshot: MusicEngineSnapshot?
    var onChange: ((MusicEngineSnapshot) -> Void)?
    var volume: Float {
        get { Float(player?.audio?.volume ?? 100) / 100 }
        set { player?.audio?.volume = Int32(min(1, max(0, newValue)) * 100) }
    }

    func load(url: URL, mediaID: UUID) {
        stop()
        self.mediaID = mediaID
        let next = VLCMediaPlayer(options: ["--no-video", "--no-video-title-show"])
        next.delegate = self
        next.media = VLCMedia(url: url)
        player = next
        publish(state: .opening)
    }
    func play() { player?.play() }
    func pause() { player?.pause(); publish(state: .paused) }
    func stop() {
        seekID = UUID()
        let old = player
        player = nil
        old?.delegate = nil
        old?.stop()
        snapshot = nil
    }

    func seek(toMilliseconds target: Int64) async throws {
        guard let player, player.isSeekable else { throw VLCSeekError.notSeekable }
        let operation = UUID(), media = mediaID
        seekID = operation
        let bounded = max(0, min(target, Int64(Int32.max)))
        let revision = observedTimeRevision
        player.time = VLCTime(int: Int32(bounded))
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            guard self.player === player, mediaID == media, seekID == operation else { throw CancellationError() }
            if observedTimeRevision > revision, player.isPlaying || player.state == .paused,
               Int64(player.time.intValue) >= bounded - 200,
               Int64(player.time.intValue) <= bounded + 1000 {
                publish()
                return
            }
            if player.state == .error { throw VLCSeekError.failed }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw VLCSeekError.timedOut
    }

    nonisolated func mediaPlayerStateChanged(_ notification: Notification) {
        guard let source = notification.object as? VLCMediaPlayer else { return }
        Task { @MainActor [weak self, weak source] in
            guard let self, let source, self.player === source else { return }
            self.publish()
        }
    }
    nonisolated func mediaPlayerTimeChanged(_ notification: Notification) {
        guard let source = notification.object as? VLCMediaPlayer else { return }
        Task { @MainActor [weak self, weak source] in
            guard let self, let source, self.player === source else { return }
            self.observedTimeRevision += 1
            self.publish()
        }
    }
    private func publish(state override: MusicEngineSnapshot.State? = nil) {
        guard let player else { return }
        let state: MusicEngineSnapshot.State
        if let override { state = override }
        // VLCKit 3 caches buffering notifications in `state`; isPlaying queries libVLC itself.
        else if player.isPlaying { state = .playing }
        else {
            switch player.state {
            case .opening: state = .opening
            case .buffering: state = .buffering
            case .playing: state = .playing
            case .paused: state = .paused
            case .ended: state = .ended
            case .error: state = .failed
            default: state = .idle
            }
        }
        let previous = snapshot?.mediaID == mediaID ? snapshot?.positionMilliseconds ?? 0 : 0
        let position = state == .playing || state == .paused || state == .ended
            ? max(0, Int64(player.time.intValue)) : previous
        let value = MusicEngineSnapshot(mediaID: mediaID, state: state, positionMilliseconds: position,
            durationMilliseconds: max(0, Int64(player.media?.length.intValue ?? 0)), seekable: player.isSeekable)
        snapshot = value
        onChange?(value)
    }
    enum VLCSeekError: Error { case notSeekable, failed, timedOut }
}
#endif
