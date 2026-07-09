import AVFoundation
import Foundation
import Observation
import SetuIOSCore

#if os(iOS)
import MediaPlayer
import UIKit
#endif

/// Queue playback behavior. Raw values match the backend playlist `playMode`.
enum MusicPlayMode: String, CaseIterable, Sendable, Codable {
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

enum MusicSleepTimerOption: String, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes
    case thirtyMinutes
    case sixtyMinutes
    case endOfTrack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fifteenMinutes: "15 分钟"
        case .thirtyMinutes: "30 分钟"
        case .sixtyMinutes: "60 分钟"
        case .endOfTrack: "播完本曲"
        }
    }

    var durationSeconds: UInt64? {
        switch self {
        case .fifteenMinutes: 15 * 60
        case .thirtyMinutes: 30 * 60
        case .sixtyMinutes: 60 * 60
        case .endOfTrack: nil
        }
    }
}

/// Result of resolving a fresh playback URL for a track.
enum MusicURLResolution: Sendable {
    case success(URL, notice: String? = nil)
    case unavailable(String)
}

private enum MusicPlaybackPersistence {
    static let legacySnapshotKey = "icu.yukiryou.setu.musicPlaybackSnapshot"

    static func snapshotKey(userID: Int) -> String {
        "\(legacySnapshotKey).user.\(userID)"
    }
}

private struct MusicPlaybackSnapshot: Codable {
    let userID: Int
    let track: MusicPlaybackTrack
    let queueName: String?
    let queueTracks: [MusicPlaybackTrack]
    let currentQueueIndex: Int?
    let currentTimeSeconds: Double
    let playMode: MusicPlayMode
    let updatedAt: Date
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
    private(set) var sleepTimerTitle: String?

    /// Resolves a fresh, playable URL for a track. Set once by the app shell so the
    /// controller can advance the queue on its own (end-of-track auto-play, lock-screen
    /// and headphone next/previous). Upstream URLs can expire, so each advance re-resolves.
    @ObservationIgnored var resolveTrackURL: (@MainActor (MusicPlaybackTrack) async -> MusicURLResolution)?
    /// Records playback history for tracks that start without a visible view, such as
    /// end-of-track auto-play.
    @ObservationIgnored var recordPlaybackHistory: (@MainActor (MusicPlaybackTrack) async -> Void)?

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var itemObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var sessionObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var remoteCommandsConfigured = false
    @ObservationIgnored private var sleepTimerTask: Task<Void, Never>?
    @ObservationIgnored private var resumeTask: Task<Void, Never>?
    @ObservationIgnored private var snapshotUserID: Int?
    @ObservationIgnored private var lastSnapshotWriteDate: Date?
    @ObservationIgnored private var pausesAtEndOfCurrentTrack = false
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
        resumeTask?.cancel()
        #if os(iOS)
        artworkTask?.cancel()
        #endif
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
    }

    // MARK: - Playback entry points

    func setSnapshotUserID(_ userID: Int?) {
        snapshotUserID = userID
        UserDefaults.standard.removeObject(forKey: MusicPlaybackPersistence.legacySnapshotKey)
    }

    func restorePlaybackSnapshotIfNeeded(for userID: Int) {
        snapshotUserID = userID
        guard currentTrack == nil else { return }
        let key = MusicPlaybackPersistence.snapshotKey(userID: userID)
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        guard let snapshot = try? JSONDecoder().decode(MusicPlaybackSnapshot.self, from: data) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        guard snapshot.userID == userID else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }

        let restoredQueue = snapshot.queueTracks.isEmpty ? [snapshot.track] : snapshot.queueTracks
        currentTrack = snapshot.track
        queueName = snapshot.queueName
        queueTracks = restoredQueue
        if let index = snapshot.currentQueueIndex, restoredQueue.indices.contains(index) {
            currentQueueIndex = index
        } else {
            syncCurrentQueueIndex()
        }
        let maxResumeTime = snapshot.track.durationSeconds > 0 ? snapshot.track.durationSeconds : snapshot.currentTimeSeconds
        currentTimeSeconds = min(max(snapshot.currentTimeSeconds, 0), max(maxResumeTime, 0))
        playMode = snapshot.playMode
        isPlaying = false
        isBuffering = false
        playbackError = nil
        message = "已恢复上次播放"
        resetNowPlayingArtwork()
        updateNowPlaying(elapsed: currentTimeSeconds)
        loadNowPlayingArtwork(for: snapshot.track)
    }

    func savePlaybackSnapshot(userID: Int? = nil) {
        persistPlaybackSnapshot(userID: userID ?? snapshotUserID)
    }

    func showMessage(_ text: String) {
        message = text
    }

    func play(
        url: URL,
        track: MusicPlaybackTrack,
        queueName: String? = nil,
        queueTracks: [MusicPlaybackTrack] = [],
        playMode: MusicPlayMode? = nil,
        notice: String? = nil
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
        load(url: url, track: track, index: index, notice: notice)
    }

    func pause() {
        player?.pause()
        isPlaying = false
        message = currentTrack.map { "已暂停 \($0.title)" }
        updateNowPlaying()
        persistPlaybackSnapshot()
    }

    func resume() {
        if player == nil {
            resumeRestoredCurrentTrack()
            return
        }
        player?.play()
        isPlaying = true
        message = currentTrack.map { "正在播放 \($0.title)" }
        updateNowPlaying()
        persistPlaybackSnapshot()
    }

    func toggle() {
        isPlaying ? pause() : resume()
    }

    func stop() {
        clearCurrentPlayback(clearPersistedSnapshot: true)
    }

    func resetForUserChange() {
        clearCurrentPlayback(clearPersistedSnapshot: false)
    }

    private func clearCurrentPlayback(clearPersistedSnapshot: Bool) {
        player?.pause()
        resumeTask?.cancel()
        resumeTask = nil
        removeTimeObserver()
        removeItemObservers()
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
        cancelSleepTimer()
        cancelArtworkTask()
        clearNowPlaying()
        if clearPersistedSnapshot {
            clearPlaybackSnapshot()
        }
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let boundedSeconds = min(max(seconds, 0), max(durationSeconds, 0))
        currentTimeSeconds = boundedSeconds
        player.seek(to: CMTime(seconds: boundedSeconds, preferredTimescale: 600))
        updateNowPlaying(elapsed: boundedSeconds)
        persistPlaybackSnapshot()
    }

    func setPlayMode(_ mode: MusicPlayMode) {
        playMode = mode
        message = mode.title
        persistPlaybackSnapshot()
    }

    func cyclePlayMode() {
        let all = MusicPlayMode.allCases
        guard let index = all.firstIndex(of: playMode) else { return }
        setPlayMode(all[(index + 1) % all.count])
    }

    func startSleepTimer(_ option: MusicSleepTimerOption) {
        cancelSleepTimer()
        sleepTimerTitle = option.title
        message = "睡眠定时：\(option.title)"
        if let durationSeconds = option.durationSeconds {
            sleepTimerTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: durationSeconds * 1_000_000_000)
                } catch {
                    return
                }
                await MainActor.run {
                    self?.pauseForSleepTimer()
                }
            }
        } else {
            pausesAtEndOfCurrentTrack = true
        }
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        pausesAtEndOfCurrentTrack = false
        sleepTimerTitle = nil
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
        case .success(let url, let notice):
            load(url: url, track: track, index: currentQueueIndex, notice: notice)
        case .unavailable(let reason):
            playbackError = reason
            isPlaying = false
            updateNowPlaying()
            persistPlaybackSnapshot()
        }
    }

    func queuedTrack(offsetBy offset: Int) -> MusicPlaybackTrack? {
        guard let currentQueueIndex else { return nil }
        let nextIndex = currentQueueIndex + offset
        guard queueTracks.indices.contains(nextIndex) else { return nil }
        return queueTracks[nextIndex]
    }

    func moveQueueTracks(from source: IndexSet, to destination: Int) {
        guard !source.isEmpty else { return }
        let moving = source.sorted().compactMap { queueTracks.indices.contains($0) ? queueTracks[$0] : nil }
        for index in source.sorted(by: >) where queueTracks.indices.contains(index) {
            queueTracks.remove(at: index)
        }
        let removedBeforeDestination = source.filter { $0 < destination }.count
        let insertionIndex = min(max(destination - removedBeforeDestination, 0), queueTracks.count)
        queueTracks.insert(contentsOf: moving, at: insertionIndex)
        syncCurrentQueueIndex()
        message = "已调整播放队列"
        persistPlaybackSnapshot()
    }

    func removeQueuedTrack(_ track: MusicPlaybackTrack) {
        if track.id == currentTrack?.id {
            stop()
            message = "已从队列移除当前歌曲"
            return
        }
        queueTracks.removeAll { $0.id == track.id }
        syncCurrentQueueIndex()
        message = "已移除 \(track.title)"
        persistPlaybackSnapshot()
    }

    func clearUpcomingTracks() {
        guard let currentTrack else {
            queueTracks = []
            currentQueueIndex = nil
            clearPlaybackSnapshot()
            return
        }
        queueTracks = [currentTrack]
        currentQueueIndex = 0
        message = "已清空待播队列"
        persistPlaybackSnapshot()
    }

    func playNext(_ track: MusicPlaybackTrack) {
        guard let currentQueueIndex else { return }
        guard track.id != currentTrack?.id else { return }
        queueTracks.removeAll { $0.id == track.id && $0.id != currentTrack?.id }
        let insertionIndex = min(currentQueueIndex + 1, queueTracks.count)
        queueTracks.insert(track, at: insertionIndex)
        syncCurrentQueueIndex()
        message = "下一首播放：\(track.title)"
        persistPlaybackSnapshot()
    }

    // MARK: - Queue advancement

    private func resumeRestoredCurrentTrack() {
        guard resumeTask == nil else { return }
        guard currentTrack != nil else { return }
        guard resolveTrackURL != nil else {
            message = "播放器尚未准备好"
            return
        }
        resumeTask = Task { [weak self] in
            await self?.resolveAndResumeCurrentTrack()
        }
    }

    private func resolveAndResumeCurrentTrack() async {
        defer { resumeTask = nil }
        guard let track = currentTrack, let resolveTrackURL else { return }

        configureAudioSession()
        configureRemoteCommands()
        configureSessionObservers()

        let resumeTime = currentTimeSeconds
        isBuffering = true
        playbackError = nil
        message = "正在恢复播放 \(track.title)"
        let resolution = await resolveTrackURL(track)
        isBuffering = false

        switch resolution {
        case .success(let url, let notice):
            let index = currentQueueIndex ?? queueTracks.firstIndex { $0.id == track.id }
            load(url: url, track: track, index: index, notice: notice ?? "继续播放 \(track.title)")
            if resumeTime > 0 {
                seek(to: resumeTime)
            }
        case .unavailable(let reason):
            playbackError = reason
            isPlaying = false
            message = reason
            updateNowPlaying()
            persistPlaybackSnapshot()
        }
    }

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
            case .success(let url, let notice):
                load(url: url, track: track, index: index, notice: notice)
                if isAuto {
                    await recordPlaybackHistory?(track)
                }
                return
            case .unavailable(let reason):
                message = "跳过无法播放：\(track.title)"
                playbackError = reason
                currentQueueIndex = index
            }
        }
        isPlaying = false
        updateNowPlaying()
        persistPlaybackSnapshot()
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
        persistPlaybackSnapshot()
    }

    private func playbackEndReached() async {
        if pausesAtEndOfCurrentTrack {
            pauseForSleepTimer()
            return
        }
        if playMode == .single {
            seek(to: 0)
            player?.play()
            isPlaying = true
            updateNowPlaying(elapsed: 0)
            persistPlaybackSnapshot()
        } else {
            await advance(by: 1, isAuto: true)
        }
    }

    // MARK: - Player item lifecycle

    private func load(url: URL, track: MusicPlaybackTrack, index: Int?, notice: String? = nil) {
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
        message = notice ?? "正在播放 \(track.title)"
        addTimeObserver()
        addItemObservers(for: item)
        resetNowPlayingArtwork()
        updateNowPlaying(elapsed: 0)
        loadNowPlayingArtwork(for: track)
        nextPlayer.play()
        persistPlaybackSnapshot()
    }

    private func pauseForSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        pausesAtEndOfCurrentTrack = false
        sleepTimerTitle = nil
        sleepTimerTask = Task { [weak self] in
            await self?.fadeOutAndPauseForSleepTimer()
        }
    }

    private func fadeOutAndPauseForSleepTimer() async {
        let originalVolume = player?.volume ?? 1
        for step in stride(from: 8, through: 1, by: -1) {
            player?.volume = originalVolume * Float(step) / 8
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                player?.volume = originalVolume
                return
            }
        }
        player?.pause()
        player?.volume = originalVolume
        sleepTimerTask = nil
        isPlaying = false
        isBuffering = false
        message = "睡眠定时已暂停播放"
        updateNowPlaying()
        persistPlaybackSnapshot()
    }

    private func syncCurrentQueueIndex() {
        guard let currentTrack else {
            currentQueueIndex = nil
            return
        }
        currentQueueIndex = queueTracks.firstIndex { $0.id == currentTrack.id }
    }

    private func persistPlaybackSnapshot(userID: Int? = nil, throttled: Bool = false) {
        guard let targetUserID = userID ?? snapshotUserID else { return }
        guard let currentTrack else {
            clearPlaybackSnapshot(userID: targetUserID)
            return
        }

        let now = Date()
        if throttled,
           let lastSnapshotWriteDate,
           now.timeIntervalSince(lastSnapshotWriteDate) < 3 {
            return
        }
        lastSnapshotWriteDate = now

        let snapshot = MusicPlaybackSnapshot(
            userID: targetUserID,
            track: currentTrack,
            queueName: queueName,
            queueTracks: queueTracks.isEmpty ? [currentTrack] : queueTracks,
            currentQueueIndex: currentQueueIndex,
            currentTimeSeconds: currentTimeSeconds,
            playMode: playMode,
            updatedAt: now
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: MusicPlaybackPersistence.snapshotKey(userID: targetUserID))
    }

    private func clearPlaybackSnapshot(userID: Int? = nil) {
        lastSnapshotWriteDate = nil
        guard let targetUserID = userID ?? snapshotUserID else { return }
        UserDefaults.standard.removeObject(forKey: MusicPlaybackPersistence.snapshotKey(userID: targetUserID))
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
                self.persistPlaybackSnapshot(throttled: true)
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
                self.persistPlaybackSnapshot()
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

struct MusicPlaybackTrack: Identifiable, Sendable, Codable {
    let id: Int
    let title: String
    let artist: String
    let album: String
    let coverURLString: String?
    let durationMilliseconds: Int
    /// Netease MV id when the track has one; enables in-app MV playback from the player.
    let mvID: Int?

    var durationSeconds: Double {
        Double(durationMilliseconds) / 1000
    }

    var hasMV: Bool {
        (mvID ?? 0) > 0
    }

    init(song: MusicSong) {
        id = song.id
        title = song.name
        artist = song.artistNames.isEmpty ? "未知歌手" : song.artistNames
        album = song.albumName
        coverURLString = song.coverURLString
        durationMilliseconds = song.durationMilliseconds
        mvID = song.mv
    }

    init(song: PlaylistSong) {
        id = song.songId
        title = song.songName
        artist = song.artistName
        album = song.albumName ?? "未知专辑"
        coverURLString = song.coverUrl
        durationMilliseconds = song.duration ?? 0
        mvID = nil
    }

    init(record: MusicHistoryRecord) {
        id = record.songId
        title = record.songName
        artist = record.artistName
        album = record.albumName ?? "未知专辑"
        coverURLString = record.coverUrl
        durationMilliseconds = record.duration ?? 0
        mvID = nil
    }
}
