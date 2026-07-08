import AVFoundation
import Foundation
import Observation
import SetuIOSCore

#if os(iOS)
import MediaPlayer
import UIKit
#endif

/// Queue playback behavior. Raw values match the backend playlist `playMode`.
enum MusicPlayMode: String, CaseIterable, Sendable {
    case sequence
    case loop
    case single
    case random

    init(playlistMode: String?) {
        switch playlistMode {
        case "random": self = .random
        case "loop": self = .loop
        case "single": self = .single
        default: self = .sequence
        }
    }

    var title: String {
        switch self {
        case .sequence: "顺序播放"
        case .loop: "列表循环"
        case .single: "单曲循环"
        case .random: "随机播放"
        }
    }

    var systemImage: String {
        switch self {
        case .sequence: "list.bullet"
        case .loop: "repeat"
        case .single: "repeat.1"
        case .random: "shuffle"
        }
    }
}

/// Result of resolving a fresh playback URL for a track.
enum MusicURLResolution: Sendable {
    case success(URL)
    case unavailable(String)
}

@MainActor
@Observable
final class MusicPlaybackController {
    private(set) var currentTrack: MusicPlaybackTrack?
    private(set) var queueName: String?
    private(set) var queueTracks: [MusicPlaybackTrack] = []
    private(set) var currentQueueIndex: Int?
    private(set) var isPlaying = false
    private(set) var message: String?
    private(set) var currentTimeSeconds: Double = 0
    private(set) var playMode: MusicPlayMode = .sequence
    private(set) var isBuffering = false
    private(set) var playbackError: String?

    /// Resolves a fresh, playable URL for a track. Set once by the app shell so the
    /// controller can advance the queue on its own (end-of-track auto-play, lock-screen
    /// and headphone next/previous). Upstream URLs can expire, so each advance re-resolves.
    @ObservationIgnored var resolveTrackURL: (@MainActor (MusicPlaybackTrack) async -> MusicURLResolution)?

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var itemObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var sessionObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var remoteCommandsConfigured = false
    #if os(iOS)
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var nowPlayingArtwork: MPMediaItemArtwork?
    @ObservationIgnored private var nowPlayingArtworkTrackID: Int?
    #endif

    var durationSeconds: Double {
        currentTrack?.durationSeconds ?? 0
    }

    var playbackProgress: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(max(currentTimeSeconds / durationSeconds, 0), 1)
    }

    var canPlayNext: Bool {
        guard let currentQueueIndex, !queueTracks.isEmpty else { return false }
        switch playMode {
        case .loop, .random:
            return queueTracks.count > 1
        case .sequence, .single:
            return currentQueueIndex + 1 < queueTracks.count
        }
    }

    var canPlayPrevious: Bool {
        guard let currentQueueIndex, !queueTracks.isEmpty else { return false }
        switch playMode {
        case .loop, .random:
            return queueTracks.count > 1
        case .sequence, .single:
            return currentQueueIndex > 0
        }
    }

    deinit {
        let center = NotificationCenter.default
        for token in itemObservers { center.removeObserver(token) }
        for token in sessionObservers { center.removeObserver(token) }
        #if os(iOS)
        artworkTask?.cancel()
        #endif
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
    }

    // MARK: - Playback entry points

    func play(
        url: URL,
        track: MusicPlaybackTrack,
        queueName: String? = nil,
        queueTracks: [MusicPlaybackTrack] = [],
        playMode: MusicPlayMode? = nil
    ) {
        configureAudioSession()
        configureRemoteCommands()
        configureSessionObservers()

        let nextQueue = queueTracks.isEmpty ? [track] : queueTracks
        self.queueName = queueName
        self.queueTracks = nextQueue
        if let playMode {
            self.playMode = playMode
        }
        let index = nextQueue.firstIndex { $0.id == track.id }
        load(url: url, track: track, index: index)
    }

    func pause() {
        player?.pause()
        isPlaying = false
        message = currentTrack.map { "已暂停 \($0.title)" }
        updateNowPlaying()
    }

    func resume() {
        guard player != nil else { return }
        player?.play()
        isPlaying = true
        message = currentTrack.map { "正在播放 \($0.title)" }
        updateNowPlaying()
    }

    func toggle() {
        isPlaying ? pause() : resume()
    }

    func stop() {
        player?.pause()
        player = nil
        currentTrack = nil
        queueName = nil
        queueTracks = []
        currentQueueIndex = nil
        isPlaying = false
        isBuffering = false
        playbackError = nil
        currentTimeSeconds = 0
        message = nil
        cancelArtworkTask()
        removeTimeObserver()
        removeItemObservers()
        clearNowPlaying()
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let boundedSeconds = min(max(seconds, 0), max(durationSeconds, 0))
        currentTimeSeconds = boundedSeconds
        player.seek(to: CMTime(seconds: boundedSeconds, preferredTimescale: 600))
        updateNowPlaying(elapsed: boundedSeconds)
    }

    func setPlayMode(_ mode: MusicPlayMode) {
        playMode = mode
        message = mode.title
    }

    func cyclePlayMode() {
        let all = MusicPlayMode.allCases
        guard let index = all.firstIndex(of: playMode) else { return }
        setPlayMode(all[(index + 1) % all.count])
    }

    /// User-initiated skip (in-app buttons, lock screen, headphones). Honors the play mode.
    func userSkip(by offset: Int) async {
        await advance(by: offset, isAuto: false)
    }

    /// Re-resolve the current track's URL and reload it. Recovers from an expired/broken
    /// upstream URL (the "重新获取播放地址" path).
    func retryCurrent() async {
        guard let track = currentTrack, let resolveTrackURL else { return }
        isBuffering = true
        let resolution = await resolveTrackURL(track)
        isBuffering = false
        switch resolution {
        case .success(let url):
            load(url: url, track: track, index: currentQueueIndex)
        case .unavailable(let reason):
            playbackError = reason
            isPlaying = false
            updateNowPlaying()
        }
    }

    func queuedTrack(offsetBy offset: Int) -> MusicPlaybackTrack? {
        guard let currentQueueIndex else { return nil }
        let nextIndex = currentQueueIndex + offset
        guard queueTracks.indices.contains(nextIndex) else { return nil }
        return queueTracks[nextIndex]
    }

    // MARK: - Queue advancement

    private func advance(by offset: Int, isAuto: Bool) async {
        guard let resolveTrackURL, let start = currentQueueIndex, !queueTracks.isEmpty else { return }
        var probeIndex = start
        let maxAttempts = queueTracks.count
        var attempts = 0
        // Probe forward past unplayable tracks so one bad URL doesn't stall the queue.
        while attempts < maxAttempts {
            attempts += 1
            guard let index = targetIndex(from: probeIndex, offset: offset, isAuto: isAuto) else {
                if isAuto { finishAtEndOfQueue() }
                return
            }
            probeIndex = index
            let track = queueTracks[index]
            isBuffering = true
            let resolution = await resolveTrackURL(track)
            isBuffering = false
            switch resolution {
            case .success(let url):
                load(url: url, track: track, index: index)
                return
            case .unavailable(let reason):
                message = "跳过无法播放：\(track.title)"
                playbackError = reason
                currentQueueIndex = index
            }
        }
        isPlaying = false
        updateNowPlaying()
    }

    private func targetIndex(from index: Int, offset: Int, isAuto: Bool) -> Int? {
        guard !queueTracks.isEmpty else { return nil }
        switch playMode {
        case .random:
            if queueTracks.count == 1 { return isAuto ? nil : index }
            var next = index
            while next == index {
                next = Int.random(in: 0..<queueTracks.count)
            }
            return next
        case .loop:
            let count = queueTracks.count
            let raw = index + offset
            return ((raw % count) + count) % count
        case .sequence, .single:
            let raw = index + offset
            return queueTracks.indices.contains(raw) ? raw : nil
        }
    }

    private func finishAtEndOfQueue() {
        isPlaying = false
        currentTimeSeconds = durationSeconds
        updateNowPlaying(elapsed: durationSeconds)
    }

    private func playbackEndReached() async {
        if playMode == .single {
            seek(to: 0)
            player?.play()
            isPlaying = true
            updateNowPlaying(elapsed: 0)
        } else {
            await advance(by: 1, isAuto: true)
        }
    }

    // MARK: - Player item lifecycle

    private func load(url: URL, track: MusicPlaybackTrack, index: Int?) {
        removeTimeObserver()
        removeItemObservers()

        let item = AVPlayerItem(url: url)
        let nextPlayer = AVPlayer(playerItem: item)
        player = nextPlayer
        currentTrack = track
        currentQueueIndex = index
        isPlaying = true
        isBuffering = true
        playbackError = nil
        currentTimeSeconds = 0
        message = "正在播放 \(track.title)"
        addTimeObserver()
        addItemObservers(for: item)
        resetNowPlayingArtwork()
        updateNowPlaying(elapsed: 0)
        loadNowPlayingArtwork(for: track)
        nextPlayer.play()
    }

    private func addTimeObserver() {
        guard let player else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = max(0, time.seconds)
                if seconds > self.currentTimeSeconds + 0.01 {
                    self.isBuffering = false
                }
                self.currentTimeSeconds = seconds
                self.updateNowPlaying(elapsed: seconds)
            }
        }
    }

    private func removeTimeObserver() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }

    private func addItemObservers(for item: AVPlayerItem) {
        let center = NotificationCenter.default
        let end = center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.playbackEndReached() }
        }
        let failed = center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self else { return }
                let reason = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
                self.playbackError = reason ?? "播放失败，请重试"
                self.isBuffering = false
                self.isPlaying = false
                self.updateNowPlaying()
            }
        }
        let stalled = center.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isBuffering = true }
        }
        itemObservers = [end, failed, stalled]
    }

    private func removeItemObservers() {
        let center = NotificationCenter.default
        for token in itemObservers {
            center.removeObserver(token)
        }
        itemObservers = []
    }

    // MARK: - Audio session, interruptions & route changes

    private func configureAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            message = "音频会话配置失败：\(error.localizedDescription)"
        }
        #endif
    }

    private func configureSessionObservers() {
        #if os(iOS)
        guard sessionObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let interruption = center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
        }
        let route = center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.handleRouteChange(note) }
        }
        sessionObservers = [interruption, route]
        #endif
    }

    #if os(iOS)
    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            if isPlaying { pause() }
        case .ended:
            if let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                if options.contains(.shouldResume) {
                    resume()
                }
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let rawReason = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }
        // Headphones/Bluetooth removed: pause instead of blasting the speaker.
        if reason == .oldDeviceUnavailable {
            pause()
        }
    }
    #endif

    // MARK: - Now Playing & remote commands

    private func updateNowPlaying(elapsed: Double? = nil) {
        #if os(iOS)
        guard let currentTrack else {
            clearNowPlaying()
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentTrack.title,
            MPMediaItemPropertyArtist: currentTrack.artist,
            MPMediaItemPropertyAlbumTitle: currentTrack.album,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if currentTrack.durationSeconds > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = currentTrack.durationSeconds
        }
        if nowPlayingArtworkTrackID == currentTrack.id, let nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = nowPlayingArtwork
        }
        if let elapsed {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, elapsed)
        } else if let player {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, player.currentTime().seconds)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #endif
    }

    private func clearNowPlaying() {
        #if os(iOS)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #endif
    }

    private func resetNowPlayingArtwork() {
        #if os(iOS)
        artworkTask?.cancel()
        artworkTask = nil
        nowPlayingArtwork = nil
        nowPlayingArtworkTrackID = nil
        #endif
    }

    private func cancelArtworkTask() {
        #if os(iOS)
        artworkTask?.cancel()
        artworkTask = nil
        nowPlayingArtwork = nil
        nowPlayingArtworkTrackID = nil
        #endif
    }

    private func loadNowPlayingArtwork(for track: MusicPlaybackTrack) {
        #if os(iOS)
        guard let urlString = secureURLString(track.coverURLString, artworkSize: .lockScreen),
              let url = URL(string: urlString) else { return }
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            do {
                let data = try await RemoteArtworkLoader.shared.data(from: url)
                guard !Task.isCancelled, let image = UIImage(data: data) else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                await MainActor.run {
                    guard let self, self.currentTrack?.id == track.id else { return }
                    self.nowPlayingArtwork = artwork
                    self.nowPlayingArtworkTrackID = track.id
                    self.updateNowPlaying()
                }
            } catch {
                // Missing artwork should never interrupt playback.
            }
        }
        #endif
    }

    private func configureRemoteCommands() {
        #if os(iOS)
        guard !remoteCommandsConfigured else { return }
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        commandCenter.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.userSkip(by: 1) }
            return .success
        }
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in await self?.userSkip(by: -1) }
            return .success
        }
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: positionEvent.positionTime) }
            return .success
        }

        remoteCommandsConfigured = true
        #endif
    }
}

struct MusicPlaybackTrack: Identifiable, Sendable {
    let id: Int
    let title: String
    let artist: String
    let album: String
    let coverURLString: String?
    let durationMilliseconds: Int

    var durationSeconds: Double {
        Double(durationMilliseconds) / 1000
    }

    init(song: MusicSong) {
        id = song.id
        title = song.name
        artist = song.artistNames.isEmpty ? "未知歌手" : song.artistNames
        album = song.albumName
        coverURLString = song.coverURLString
        durationMilliseconds = song.durationMilliseconds
    }

    init(song: PlaylistSong) {
        id = song.songId
        title = song.songName
        artist = song.artistName
        album = song.albumName ?? "未知专辑"
        coverURLString = song.coverUrl
        durationMilliseconds = song.duration ?? 0
    }

    init(record: MusicHistoryRecord) {
        id = record.songId
        title = record.songName
        artist = record.artistName
        album = record.albumName ?? "未知专辑"
        coverURLString = record.coverUrl
        durationMilliseconds = record.duration ?? 0
    }
}
