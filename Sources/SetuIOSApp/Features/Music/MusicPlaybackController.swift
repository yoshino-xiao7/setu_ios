import AVFoundation
import Foundation
import Observation
import os
import SetuIOSCore

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
    case unavailable(UserFacingError)

    static func unavailable(_ message: String) -> Self {
        .unavailable(UserFacingError(message: message))
    }
}

@MainActor
@Observable
final class MusicPlaybackController {
    private(set) var currentTrack: MusicPlaybackTrack?
    private(set) var context: PlaybackContext?
    var queueName: String? { context?.label }
    private var queue = PlaybackQueue()
    private(set) var queueTracks: [MusicPlaybackTrack] {
        get { queue.tracks }
        set { queue.tracks = newValue }
    }
    private(set) var currentQueueIndex: Int? {
        get { queue.currentIndex }
        set { queue.currentIndex = newValue }
    }
    private(set) var isPlaying = false
    private(set) var feedback: SetuFeedback? {
        didSet { scheduleFeedbackDismissal() }
    }
    private(set) var currentTimeSeconds: Double = 0
    private(set) var playMode: MusicPlayMode {
        get { queue.mode }
        set { queue.mode = newValue }
    }
    private(set) var isBuffering = false
    private(set) var playbackError: String?
    private(set) var sleepTimerTitle: String?
    private(set) var audioQuality: MusicAudioQuality
    private(set) var isChangingQuality = false

    @ObservationIgnored var urlResolver: PlaybackURLResolver?
    /// An explicit quality change must not silently fall back on a failed request.
    @ObservationIgnored var resolveQualityURL: (@MainActor (MusicPlaybackTrack, MusicAudioQuality) async -> MusicURLResolution)?
    /// Records playback history for tracks that start without a visible view, such as
    /// end-of-track auto-play.
    @ObservationIgnored var recordPlaybackHistory: (@MainActor (MusicPlaybackTrack) async -> Void)?

    @ObservationIgnored private(set) var player: AVPlayer?
    @ObservationIgnored let nextItemPreparer = NextItemPreparer()
    @ObservationIgnored private var transitionID = UUID()
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var currentSource: ResolvedPlaybackURL?
    @ObservationIgnored private var recoveryCount = 0
    @ObservationIgnored private var recoveryTask: Task<Void, Never>?
    @ObservationIgnored private var preparationTask: Task<Void, Never>?
    @ObservationIgnored private var preparationDelay: Task<Void, Never>?
    @ObservationIgnored private var itemLoadDeadline: Date?
    @ObservationIgnored private var loadingTimeout: Task<Void, Never>?
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var keepUpObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored private var audioSessionReady = false
    @ObservationIgnored private var audioSessionNeedsReactivation = false
    @ObservationIgnored private var audioSessionRevision = UUID()
    @ObservationIgnored private var audioSessionTask: Task<Void, Never>?
    #if os(iOS)
    @ObservationIgnored private let audioSession = PlaybackAudioSession()
    #endif
    @ObservationIgnored private var stalledCount = 0
    @ObservationIgnored private var historyInFlightIDs: Set<Int> = []
    @ObservationIgnored private var interruptedPlayback = false
    @ObservationIgnored private var historyTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let playbackLog = OSLog(subsystem: "icu.yukiryou.setuios", category: "MusicPlayback")
    @ObservationIgnored private var transitionSignpost: OSSignpostID?
    #if DEBUG // P0.1 instrumentation
    @ObservationIgnored private let playbackDiagnostics = MusicPlaybackDiagnostics()
    #endif // P0.1 instrumentation
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var itemObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var sessionObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var feedbackDismissTask: Task<Void, Never>?
    @ObservationIgnored private var resumeTask: Task<Void, Never>?
    @ObservationIgnored private let persistsPlayback: Bool
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let snapshotStore: PlaybackSnapshotStore
    @ObservationIgnored private let nowPlayingCoordinator: NowPlayingCoordinator
    @ObservationIgnored private let remoteCommandCoordinator: RemoteCommandCoordinator
    @ObservationIgnored private let sleepTimerController: SleepTimerController
    @ObservationIgnored private var qualityChangeID = UUID()

    init(
        persistsPlayback: Bool = true,
        preferences: UserDefaults = .standard,
        snapshotStore: PlaybackSnapshotStore? = nil,
        nowPlayingCoordinator: NowPlayingCoordinator? = nil,
        remoteCommandCoordinator: RemoteCommandCoordinator? = nil,
        sleepTimerController: SleepTimerController? = nil
    ) {
        self.persistsPlayback = persistsPlayback
        self.preferences = preferences
        self.snapshotStore = snapshotStore ?? PlaybackSnapshotStore(enabled: persistsPlayback, preferences: preferences)
        self.nowPlayingCoordinator = nowPlayingCoordinator ?? NowPlayingCoordinator()
        self.remoteCommandCoordinator = remoteCommandCoordinator ?? RemoteCommandCoordinator()
        self.sleepTimerController = sleepTimerController ?? SleepTimerController()
        audioQuality = persistsPlayback
            ? preferences.string(forKey: PlaybackSnapshotStore.audioQualityKey).flatMap(MusicAudioQuality.init(rawValue:)) ?? .exhigh
            : .exhigh
    }

    var phase: PlaybackPhase {
        .derive(
            hasTrack: currentTrack != nil,
            isBuffering: isBuffering,
            isPlaying: isPlaying,
            hasError: playbackError != nil
        )
    }

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
        guard context?.allowsPrevious != false else { return false }
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
        feedbackDismissTask?.cancel()
        recoveryTask?.cancel(); preparationTask?.cancel(); preparationDelay?.cancel()
        loadingTimeout?.cancel(); audioSessionTask?.cancel()
        for task in historyTasks.values { task.cancel() }
        itemStatusObservation?.invalidate(); keepUpObservation?.invalidate(); timeControlObservation?.invalidate()
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
    }

    // MARK: - Playback entry points

    func setSnapshotUserID(_ userID: Int?) {
        snapshotStore.setUserID(userID)
    }

    func restorePlaybackSnapshotIfNeeded(for userID: Int) {
        guard currentTrack == nil else { return }
        guard let snapshot = snapshotStore.restore(for: userID) else { return }

        let restoredQueue = snapshot.queueTracks.isEmpty ? [snapshot.track] : snapshot.queueTracks
        currentTrack = snapshot.track
        context = snapshot.context
        updateRemoteCapabilities()
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
        feedback = .success("已恢复上次播放")
        resetNowPlayingArtwork()
        updateNowPlaying(elapsed: currentTimeSeconds)
        loadNowPlayingArtwork(for: snapshot.track)
    }

    func savePlaybackSnapshot(userID: Int? = nil) {
        persistPlaybackSnapshot(userID: userID ?? snapshotStore.userID)
    }

    func showFeedback(_ value: SetuFeedback) {
        feedback = value
    }

    private func scheduleFeedbackDismissal() {
        feedbackDismissTask?.cancel()
        guard let feedback else {
            feedbackDismissTask = nil
            return
        }

        let delay: UInt64?
        switch feedback {
        case .success, .info:
            delay = 3_000_000_000
        case .warning:
            delay = 5_000_000_000
        case .error, .failure:
            delay = nil
        }
        guard let delay else { return }
        feedbackDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            self?.feedback = nil
        }
    }

    /// All visible and remote playback entries use this path. History never blocks it.
    @discardableResult
    func play(track: MusicPlaybackTrack, in tracks: [MusicPlaybackTrack] = [],
              context: PlaybackContext? = nil, playMode: MusicPlayMode? = nil) async -> Bool {
        self.context = context ?? .singleTrack(trackID: .legacyProvider(track.id), label: nil)
        updateRemoteCapabilities()
        queueTracks = tracks.isEmpty ? [track] : tracks
        if let playMode { self.playMode = playMode }
        nextItemPreparer.invalidate()
        return await transition(to: track, index: queueTracks.firstIndex { $0.id == track.id }) == true
    }

    // Direct URL entry remains useful for local playback fixtures.
    func play(url: URL, track: MusicPlaybackTrack, context: PlaybackContext? = nil,
              queueTracks: [MusicPlaybackTrack] = [], playMode: MusicPlayMode? = nil, notice: String? = nil) {
        beginTransition()
        self.context = context ?? .singleTrack(trackID: .legacyProvider(track.id), label: nil)
        updateRemoteCapabilities()
        self.queueTracks = queueTracks.isEmpty ? [track] : queueTracks
        if let playMode { self.playMode = playMode }
        currentSource = nil
        nextItemPreparer.invalidate()
        load(url: url, track: track, index: self.queueTracks.firstIndex { $0.id == track.id }, notice: notice)
    }

    private func beginTransition() {
        transitionID = UUID()
        resumeTask?.cancel(); resumeTask = nil
        cancelPendingQualityChange()
        recoveryTask?.cancel(); recoveryTask = nil
        audioSessionTask?.cancel(); audioSessionTask = nil
        preparationTask?.cancel(); preparationDelay?.cancel(); loadingTimeout?.cancel()
        recoveryCount = 0
        itemLoadDeadline = nil
        endTransitionMeasurement()
        let id = OSSignpostID(log: playbackLog)
        transitionSignpost = id
        os_signpost(.begin, log: playbackLog, name: "TrackTransition", signpostID: id)
        #if DEBUG // P0.1 instrumentation
        playbackDiagnostics.transitionStarted()
        #endif // P0.1 instrumentation
    }

    private func endTransitionMeasurement() {
        if let id = transitionSignpost {
            os_signpost(.end, log: playbackLog, name: "TrackTransition", signpostID: id)
            transitionSignpost = nil
        }
    }

    @discardableResult
    private func transition(to track: MusicPlaybackTrack, index: Int?, force: Bool = false,
                            resumeAt: Double = 0, autoplay: Bool = true, recordHistory: Bool = true) async -> Bool? {
        beginTransition()
        let ticket = transitionID
        // Commit the intent before awaiting: consecutive next taps advance from the last intent.
        #if DEBUG // P0.1 instrumentation
        playbackDiagnostics.mark("TransitionIntentCommitted")
        #endif // P0.1 instrumentation
        player?.pause()
        removeItemObservers()
        #if DEBUG // P0.1 instrumentation
        playbackDiagnostics.replaceBegin(installing: false)
        #endif // P0.1 instrumentation
        player?.replaceCurrentItem(with: nil)
        #if DEBUG // P0.1 instrumentation
        playbackDiagnostics.replaceEnd(installing: false)
        #endif // P0.1 instrumentation
        currentTrack = track
        currentQueueIndex = index
        currentTimeSeconds = resumeAt
        isPlaying = autoplay; isBuffering = autoplay; playbackError = nil
        currentSource = nil
        feedback = .info("正在准备播放")
        #if DEBUG // P0.1 instrumentation
        playbackDiagnostics.mark("PreparedLookupStarted")
        #endif // P0.1 instrumentation
        if !force, let prepared = nextItemPreparer.consume(trackID: track.id, quality: audioQuality) {
            #if DEBUG // P0.1 instrumentation
            playbackDiagnostics.mark("PreparedHit")
            #endif // P0.1 instrumentation
            currentSource = prepared.source
            os_signpost(.event, log: playbackLog, name: "PreparedItemHit")
            #if DEBUG // P0.1 instrumentation
            playbackDiagnostics.mark("PlaybackSourceReady", value: 1)
            #endif // P0.1 instrumentation
            load(url: prepared.source.url, track: track, index: index, notice: prepared.source.notice,
                 resumeAt: resumeAt, autoplay: autoplay, preparedItem: prepared.item)
            if recordHistory { enqueueHistory(track) }
            return true
        }
        #if DEBUG // P0.1 instrumentation
        playbackDiagnostics.preparedMiss(forced: force)
        #endif // P0.1 instrumentation
        nextItemPreparer.invalidate()
        guard let urlResolver else { failPlayback(UserFacingError(message: "播放器尚未准备好")); return false }
        do {
            #if DEBUG // P0.1 instrumentation
            playbackDiagnostics.mark("PlaybackSourceResolveStarted")
            #endif // P0.1 instrumentation
            let source = try await urlResolver.resolve(trackID: track.id, quality: audioQuality, force: force)
            guard transitionID == ticket, !Task.isCancelled else { return nil }
            currentSource = source
            #if DEBUG // P0.1 instrumentation
            playbackDiagnostics.mark("PlaybackSourceReady", value: 0)
            #endif // P0.1 instrumentation
            load(url: source.url, track: track, index: index, notice: source.notice, resumeAt: resumeAt, autoplay: autoplay && isPlaying)
            if recordHistory { enqueueHistory(track) }
            return true
        } catch {
            guard transitionID == ticket else { return nil }
            failPlayback((error as? UserFacingError ?? UserFacingErrorMapper.map(error)))
            return false
        }
    }

    private func enqueueHistory(_ track: MusicPlaybackTrack) {
        guard let recordPlaybackHistory, historyInFlightIDs.insert(track.id).inserted else { return }
        let owner = sessionID, id = UUID()
        historyTasks[id] = Task { [weak self] in
            guard self?.sessionID == owner, !Task.isCancelled else { return }
            await recordPlaybackHistory(track)
            self?.historyTasks[id] = nil
            if self?.sessionID == owner { self?.historyInFlightIDs.remove(track.id) }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        isBuffering = false
        loadingTimeout?.cancel()
        feedback = currentTrack.map { .info("已暂停 \($0.title)") }
        updateNowPlaying()
        persistPlaybackSnapshot()
    }

    func resume() {
        if player?.currentItem == nil || player?.currentItem?.status == .failed || currentSource.map({ !$0.isValid(at: Date()) }) == true {
            resumeRestoredCurrentTrack()
            return
        }
        isPlaying = true
        if let item = player?.currentItem { playWhenSessionReady(item) }
        observeTimeControlStatus()
        if let item = player?.currentItem {
            if item.isPlaybackLikelyToKeepUp { prepareNextIfNeeded() }
            else { schedulePreparationFallback(for: item) }
        }
        feedback = currentTrack.map { .success("正在播放 \($0.title)") }
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
        sessionID = UUID()
        for task in historyTasks.values { task.cancel() }
        historyTasks.removeAll()
        historyInFlightIDs.removeAll()
        let oldResolver = urlResolver
        urlResolver = nil
        Task { await oldResolver?.reset() }
        clearCurrentPlayback(clearPersistedSnapshot: false)
    }

    private func clearCurrentPlayback(clearPersistedSnapshot: Bool) {
        beginTransition()
        nextItemPreparer.invalidate()
        currentSource = nil
        endTransitionMeasurement()
        #if DEBUG // P0.1 instrumentation
        playbackDiagnostics.finish("PlaybackStopped")
        #endif // P0.1 instrumentation
        player?.pause()
        resumeTask?.cancel()
        resumeTask = nil
        removeItemObservers()
        player?.replaceCurrentItem(with: nil)
        currentTrack = nil
        context = nil
        updateRemoteCapabilities()
        queueTracks = []
        currentQueueIndex = nil
        isPlaying = false
        isBuffering = false
        playbackError = nil
        currentTimeSeconds = 0
        feedback = nil
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
        queueDidChange()
        feedback = .info(mode.title)
        persistPlaybackSnapshot()
    }

    /// Called before a new track resolves or replaces the current item, so a late
    /// quality response cannot bring back the previous track or a stopped session.
    func cancelPendingQualityChange() {
        qualityChangeID = UUID()
        isChangingQuality = false
    }

    @discardableResult
    func setAudioQuality(_ quality: MusicAudioQuality) async -> Bool {
        guard quality != audioQuality else {
            cancelPendingQualityChange()
            return true
        }
        let requestID = UUID()
        qualityChangeID = requestID
        guard let track = currentTrack else {
            commitAudioQuality(quality)
            isChangingQuality = false
            return true
        }
        guard resolveQualityURL != nil || urlResolver != nil else {
            isChangingQuality = false
            feedback = .error("播放器尚未准备好，请稍后重试")
            return false
        }
        isChangingQuality = true
        defer { if qualityChangeID == requestID { isChangingQuality = false } }
        let resolution: MusicURLResolution
        var source: ResolvedPlaybackURL?
        if let resolveQualityURL {
            resolution = await resolveQualityURL(track, quality)
        } else if let urlResolver {
            do {
                let value = try await urlResolver.resolve(trackID: track.id, quality: quality, allowsFallback: false)
                source = value
                resolution = .success(value.url, notice: value.notice)
            } catch { resolution = .unavailable((error as? UserFacingError ?? UserFacingErrorMapper.map(error))) }
        } else { return false }
        guard qualityChangeID == requestID, currentTrack?.id == track.id, !Task.isCancelled else { return false }
        switch resolution {
        case .success(let url, let notice):
            // Keep the existing player alive while checking the replacement source.
            // This also catches an unsupported audio format before replacing playback.
            let asset = AVURLAsset(url: url)
            do {
                guard try await asset.load(.isPlayable) else {
                    throw MusicQualityError.unplayable
                }
            } catch {
                guard qualityChangeID == requestID, !Task.isCancelled else { return false }
                feedback = .error("新音质暂时无法播放，已保留原来的播放状态")
                return false
            }
            guard qualityChangeID == requestID, currentTrack?.id == track.id, !Task.isCancelled else { return false }
            let resumeTime = currentTimeSeconds
            let shouldPlay = isPlaying
            beginTransition()
            commitAudioQuality(quality)
            currentSource = source
            nextItemPreparer.invalidate()
            load(url: url, track: track, index: currentQueueIndex, notice: notice,
                 resumeAt: resumeTime, autoplay: shouldPlay, preparedItem: AVPlayerItem(asset: asset))
            feedback = notice.map(SetuFeedback.warning) ?? .success("已切换为\(quality.title)音质")
            return true
        case .unavailable(let reason):
            feedback = .failure(reason)
            return false
        }
    }

    private func commitAudioQuality(_ quality: MusicAudioQuality) {
        audioQuality = quality
        if persistsPlayback {
            preferences.set(quality.rawValue, forKey: PlaybackSnapshotStore.audioQualityKey)
        }
    }

    func cyclePlayMode() {
        let all = MusicPlayMode.allCases
        guard let index = all.firstIndex(of: playMode) else { return }
        setPlayMode(all[(index + 1) % all.count])
    }

    func startSleepTimer(_ option: MusicSleepTimerOption) {
        cancelSleepTimer()
        sleepTimerTitle = option.title
        feedback = .success("睡眠定时：\(option.title)")
        sleepTimerController.start(option) { [weak self] in
            self?.pauseForSleepTimer()
        }
    }

    func cancelSleepTimer() {
        sleepTimerController.cancel()
        sleepTimerTitle = nil
    }

    /// User-initiated skip (in-app buttons, lock screen, headphones). Honors the play mode.
    func userSkip(by offset: Int) async {
        await advance(by: offset, isAuto: false)
    }

    /// Re-resolve the current track's URL and reload it. Recovers from an expired/broken
    /// upstream URL (the "重新获取播放地址" path).
    func retryCurrent() async {
        guard let track = currentTrack else { return }
        await transition(to: track, index: currentQueueIndex, force: true, resumeAt: currentTimeSeconds, recordHistory: false)
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
        queueDidChange()
        feedback = .success("已调整播放队列")
        persistPlaybackSnapshot()
    }

    func removeQueuedTrack(_ track: MusicPlaybackTrack) {
        if track.id == currentTrack?.id {
            stop()
            feedback = .success("已从队列移除当前歌曲")
            return
        }
        queueTracks.removeAll { $0.id == track.id }
        syncCurrentQueueIndex()
        queueDidChange()
        feedback = .success("已移除 \(track.title)")
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
        queueDidChange()
        feedback = .success("已清空待播队列")
        persistPlaybackSnapshot()
    }

    func playNext(_ track: MusicPlaybackTrack) {
        guard let currentQueueIndex else { return }
        guard track.id != currentTrack?.id else { return }
        queueTracks.removeAll { $0.id == track.id && $0.id != currentTrack?.id }
        syncCurrentQueueIndex()
        let insertionIndex = min((self.currentQueueIndex ?? currentQueueIndex) + 1, queueTracks.count)
        queueTracks.insert(track, at: insertionIndex)
        syncCurrentQueueIndex()
        queue.prioritizeNext(track.id)
        queueDidChange()
        feedback = .success("下一首播放：\(track.title)")
        persistPlaybackSnapshot()
    }

    // MARK: - Queue advancement

    private func resumeRestoredCurrentTrack() {
        guard resumeTask == nil, let track = currentTrack, let resolver = urlResolver else { return }
        beginTransition()
        let ticket = transitionID, position = currentTimeSeconds, quality = audioQuality
        let force = player?.currentItem?.status == .failed
        isPlaying = true; isBuffering = true; playbackError = nil
        resumeTask = Task { [weak self] in
            do {
                let source = try await resolver.resolve(trackID: track.id, quality: quality, force: force)
                guard let self, self.transitionID == ticket, !Task.isCancelled else { return }
                self.resumeTask = nil
                self.currentSource = source
                self.load(url: source.url, track: track, index: self.currentQueueIndex, notice: source.notice,
                          resumeAt: position, autoplay: self.isPlaying)
            } catch {
                guard let self, self.transitionID == ticket else { return }
                self.resumeTask = nil
                self.failPlayback(error as? UserFacingError ?? UserFacingErrorMapper.map(error))
            }
        }
    }

    private func advance(by offset: Int, isAuto: Bool) async {
        #if DEBUG // P0.1 instrumentation
        playbackDiagnostics.nextRequested(offset: offset, automatic: isAuto)
        #endif // P0.1 instrumentation
        guard let start = currentQueueIndex, !queueTracks.isEmpty else { return }
        var probe = start
        for _ in 0..<queueTracks.count {
            #if DEBUG // P0.1 instrumentation
            playbackDiagnostics.mark("QueueLookupStarted")
            #endif // P0.1 instrumentation
            guard let index = queue.target(from: probe, offset: offset, isAuto: isAuto) else {
                if isAuto { finishAtEndOfQueue() }
                return
            }
            let track = queueTracks[index]
            #if DEBUG // P0.1 instrumentation
            playbackDiagnostics.queueResolved()
            #endif // P0.1 instrumentation
            // Each transition publishes the target synchronously before suspension.
            let expectedSession = sessionID
            guard let succeeded = await transition(to: track, index: index) else { return }
            guard sessionID == expectedSession, currentTrack?.id == track.id else { return }
            if succeeded { return }
            // A replacement intent, cancellation or authentication error stops probing.
            guard !Task.isCancelled, playbackError != nil else { return }
            if case .failure(let reason) = feedback, reason.action == .signIn { return }
            probe = index
        }
        isPlaying = false; isBuffering = false
        updateNowPlaying(); persistPlaybackSnapshot()
    }

    private func finishAtEndOfQueue() {
        isPlaying = false
        isBuffering = false
        loadingTimeout?.cancel()
        currentTimeSeconds = durationSeconds
        updateNowPlaying(elapsed: durationSeconds)
        persistPlaybackSnapshot()
    }

    func playbackEndReached() async {
        if sleepTimerController.consumeEndOfTrack() {
            pauseForSleepTimer()
            return
        }
        if playMode == .single {
            seek(to: 0)
            isPlaying = true
            if let item = player?.currentItem { playWhenSessionReady(item) }
            updateNowPlaying(elapsed: 0)
            persistPlaybackSnapshot()
        } else {
            await advance(by: 1, isAuto: true)
        }
    }

    // MARK: - Player item lifecycle

    private func load(url: URL, track: MusicPlaybackTrack, index: Int?, notice: String? = nil,
                      resumeAt: Double = 0, autoplay: Bool = true, preparedItem: AVPlayerItem? = nil) {
        cancelPendingQualityChange()
        configureRemoteCommands()
        configureSessionObservers()
        ensurePlayer()
        loadingTimeout?.cancel(); loadingTimeout = nil
        guard let player else { return }
        player.pause()
        removeItemObservers()
        #if DEBUG // P0.1 instrumentation
        playbackDiagnostics.mark("PlayerItemCreationStarted")
        #endif // P0.1 instrumentation
        let item = preparedItem ?? AVPlayerItem(url: url)
        #if DEBUG // P0.1 instrumentation
        playbackDiagnostics.itemReady(reused: preparedItem != nil, status: item.status)
        playbackDiagnostics.replaceBegin(installing: true)
        #endif // P0.1 instrumentation
        player.replaceCurrentItem(with: item)
        #if DEBUG // P0.1 instrumentation
        playbackDiagnostics.replaceEnd(installing: true)
        #endif // P0.1 instrumentation
        currentTrack = track
        currentQueueIndex = index
        isPlaying = autoplay
        isBuffering = autoplay
        playbackError = nil
        currentTimeSeconds = resumeAt
        feedback = notice.map(SetuFeedback.warning) ?? .success("正在播放 \(track.title)")
        addItemObservers(for: item)
        stalledCount = 0
        resetNowPlayingArtwork()
        updateNowPlaying(elapsed: resumeAt)
        loadNowPlayingArtwork(for: track)
        if resumeAt > 0 {
            player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600)) { [weak self, weak item] finished in
                Task { @MainActor in
                    guard finished, let self, let item, self.player?.currentItem === item else { return }
                    if self.isPlaying { self.playWhenSessionReady(item) }
                }
            }
        } else if autoplay {
            playWhenSessionReady(item)
        }
        schedulePreparationFallback(for: item)
        if autoplay { startLoadingTimeout(for: item) }
        persistPlaybackSnapshot()
    }

    private func ensurePlayer() {
        guard player == nil else { return }
        let player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player
        addTimeObserver()
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.observeTimeControlStatus() }
        }
    }

    func observeTimeControlStatus() {
        guard let player, player.currentItem != nil, playbackError == nil else { return }
        #if DEBUG // P0.1 instrumentation
        playbackDiagnostics.playerStatus(player.timeControlStatus, waitingReason: player.reasonForWaitingToPlay)
        #endif // P0.1 instrumentation
        isBuffering = isPlaying && player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if player.timeControlStatus == .playing {
            isBuffering = false
            loadingTimeout?.cancel(); loadingTimeout = nil
            itemLoadDeadline = nil
            os_signpost(.event, log: playbackLog, name: "TrackPlaying")
            #if DEBUG // P0.1 instrumentation
            playbackDiagnostics.playing()
            #endif // P0.1 instrumentation
            endTransitionMeasurement()
        } else if isBuffering, let item = player.currentItem, loadingTimeout == nil {
            startLoadingTimeout(for: item)
        }
    }

    private func schedulePreparationFallback(for item: AVPlayerItem) {
        preparationDelay?.cancel()
        preparationDelay = Task { [weak self, weak item] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            guard let self, let item, self.player?.currentItem === item,
                  self.isPlaying, self.player?.timeControlStatus == .playing else { return }
            self.prepareNextIfNeeded()
        }
    }

    func prepareNextIfNeeded() {
        guard isPlaying, let track = queue.nextForPreparation(), let urlResolver else { return }
        let preparer = nextItemPreparer, quality = audioQuality
        preparationTask?.cancel()
        preparationTask = Task { await preparer.prepare(trackID: track.id, quality: quality, resolver: urlResolver) }
    }

    func waitForNextPreparation() async { await preparationTask?.value }

    private func queueDidChange() {
        let next = queue.nextForPreparation()
        nextItemPreparer.invalidate(unlessTrackID: next?.id, quality: audioQuality)
        if player?.currentItem?.isPlaybackLikelyToKeepUp == true { prepareNextIfNeeded() }
    }

    private func startLoadingTimeout(for item: AVPlayerItem) {
        loadingTimeout?.cancel()
        if itemLoadDeadline == nil { itemLoadDeadline = Date().addingTimeInterval(10) }
        let remaining = max(0, itemLoadDeadline?.timeIntervalSinceNow ?? 10)
        let delay = UInt64(min(recoveryCount == 0 ? 5 : 10, remaining) * 1_000_000_000)
        loadingTimeout = Task { [weak self, weak item] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard let self, let item, self.player?.currentItem === item, self.isPlaying else { return }
            self.loadingTimeout = nil
            self.handleItemFailure(item, error: URLError(.timedOut))
        }
    }

    func handleItemFailure(_ item: AVPlayerItem, error: Error?) {
        guard player?.currentItem === item, recoveryTask == nil, playbackError == nil else { return }
        loadingTimeout?.cancel(); loadingTimeout = nil
        guard recoveryCount == 0, let resolver = urlResolver, let track = currentTrack else {
            failPlayback(UserFacingErrorMapper.map(error ?? UserFacingError(message: "播放失败，请重新获取播放地址")))
            return
        }
        let nsError = error as NSError?
        let recoverable = nsError?.domain == NSURLErrorDomain || nsError?.domain == AVFoundationErrorDomain
            || currentSource.map { !$0.isValid(at: Date()) } == true
        guard recoverable else { failPlayback(UserFacingErrorMapper.map(error ?? UserFacingError(message: "音源无法播放"))); return }
        recoveryCount += 1
        let ticket = transitionID, position = currentTimeSeconds, shouldPlay = isPlaying, quality = audioQuality
        isBuffering = shouldPlay
        nextItemPreparer.invalidate()
        if itemLoadDeadline == nil { itemLoadDeadline = Date().addingTimeInterval(10) }
        let remaining = UInt64(max(0, itemLoadDeadline?.timeIntervalSinceNow ?? 10) * 1_000_000_000)
        loadingTimeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: remaining) } catch { return }
            guard let self, self.transitionID == ticket else { return }
            self.transitionID = UUID()
            self.recoveryTask?.cancel(); self.recoveryTask = nil
            self.failPlayback(UserFacingError(message: "播放地址刷新超时，请重试"))
        }
        recoveryTask = Task { [weak self] in
            do {
                let source = try await resolver.resolve(trackID: track.id, quality: quality, force: true)
                guard let self, self.transitionID == ticket, !Task.isCancelled else { return }
                self.currentSource = source
                self.recoveryTask = nil
                self.load(url: source.url, track: track, index: self.currentQueueIndex, notice: source.notice,
                          resumeAt: position, autoplay: shouldPlay && self.isPlaying)
            } catch {
                guard let self, self.transitionID == ticket else { return }
                self.recoveryTask = nil
                self.failPlayback((error as? UserFacingError ?? UserFacingErrorMapper.map(error)))
            }
        }
    }

    private func failPlayback(_ error: UserFacingError) {
        #if DEBUG // P0.1 instrumentation
        playbackDiagnostics.finish("DiagnosticFailed")
        #endif // P0.1 instrumentation
        player?.pause()
        preparationTask?.cancel(); preparationDelay?.cancel()
        nextItemPreparer.invalidate()
        loadingTimeout?.cancel(); loadingTimeout = nil
        isPlaying = false; isBuffering = false
        playbackError = error.message; feedback = .failure(error)
        endTransitionMeasurement()
        updateNowPlaying(); persistPlaybackSnapshot()
    }

    private func pauseForSleepTimer() {
        sleepTimerTitle = nil
        sleepTimerController.fadeOutAndPause(player: player) { [weak self] in
            guard let self else { return }
            self.isPlaying = false
            self.isBuffering = false
            self.feedback = .info("睡眠定时已暂停播放")
            self.updateNowPlaying()
            self.persistPlaybackSnapshot()
        }
    }

    private func syncCurrentQueueIndex() {
        guard let currentTrack else {
            currentQueueIndex = nil
            return
        }
        currentQueueIndex = queueTracks.firstIndex { $0.id == currentTrack.id }
    }

    private func persistPlaybackSnapshot(userID: Int? = nil, throttled: Bool = false) {
        guard let targetUserID = userID ?? snapshotStore.userID else { return }
        guard let currentTrack else {
            clearPlaybackSnapshot(userID: targetUserID)
            return
        }
        let snapshot = PlaybackSnapshotStore.Snapshot(
            userID: targetUserID,
            track: currentTrack,
            context: context ?? .unknown(reason: .missingProvenance, label: nil),
            queueTracks: queueTracks.isEmpty ? [currentTrack] : queueTracks,
            currentQueueIndex: currentQueueIndex,
            currentTimeSeconds: currentTimeSeconds,
            playMode: playMode,
            updatedAt: Date()
        )
        snapshotStore.save(snapshot, throttled: throttled)
    }

    func waitForSnapshotWrites() async {
        await snapshotStore.waitForWrites()
    }

    private func clearPlaybackSnapshot(userID: Int? = nil) {
        snapshotStore.clear(userID: userID)
    }

    private func addTimeObserver() {
        guard let player else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self, weak player] time in
            let observedItem = player?.currentItem
            Task { @MainActor [weak observedItem] in
                guard let self, let observedItem, self.player?.currentItem === observedItem else { return }
                let seconds = max(0, time.seconds)
                guard self.player?.currentItem != nil, seconds.isFinite else { return }
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
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak item] in
                guard let self, let item, self.player?.currentItem === item else { return }
                #if DEBUG // P0.1 instrumentation
                self.playbackDiagnostics.itemStatus(item.status)
                #endif // P0.1 instrumentation
                switch item.status {
                case .failed: self.handleItemFailure(item, error: item.error)
                case .readyToPlay: self.observeTimeControlStatus()
                case .unknown: self.isBuffering = self.isPlaying
                @unknown default: break
                }
            }
        }
        keepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak item] in
                guard let self, let item, self.player?.currentItem === item, item.isPlaybackLikelyToKeepUp else { return }
                self.prepareNextIfNeeded()
            }
        }
        let center = NotificationCenter.default
        let end = center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self, weak item] _ in
            Task { @MainActor in
                guard let self, let item, self.player?.currentItem === item else { return }
                await self.playbackEndReached()
            }
        }
        let failed = center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self, weak item] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor in
                guard let item else { return }
                self?.handleItemFailure(item, error: error)
            }
        }
        let stalled = center.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { [weak self, weak item] _ in
            Task { @MainActor in
                guard let self, let item, self.player?.currentItem === item else { return }
                self.stalledCount += 1
                if self.stalledCount >= 3 { self.failPlayback(UserFacingError(message: "网络持续中断，请重新获取播放地址")) }
                else { self.observeTimeControlStatus(); self.startLoadingTimeout(for: item) }
            }
        }
        itemObservers = [end, failed, stalled]
    }

    private func removeItemObservers() {
        itemStatusObservation?.invalidate(); itemStatusObservation = nil
        keepUpObservation?.invalidate(); keepUpObservation = nil
        for token in itemObservers { NotificationCenter.default.removeObserver(token) }
        itemObservers = []
    }

    // MARK: - Audio session, interruptions & route changes

    private func playWhenSessionReady(_ item: AVPlayerItem) {
        #if os(iOS)
        #if DEBUG // P0.1 instrumentation
        playbackDiagnostics.mark("SessionGate", value: audioSessionReady ? 1 : 0)
        #endif // P0.1 instrumentation
        if audioSessionReady { player?.play(); return }
        audioSessionTask?.cancel()
        let session = audioSession, ticket = transitionID, revision = audioSessionRevision
        let force = audioSessionNeedsReactivation
        #if DEBUG // P0.1 instrumentation
        playbackDiagnostics.mark("SessionActivateBegin")
        #endif // P0.1 instrumentation
        audioSessionTask = Task { [weak self, weak item] in
            do {
                // AVAudioSession's synchronous calls can block; serialize them off MainActor.
                try await session.activate(force: force)
                guard let self, let item, !Task.isCancelled, self.transitionID == ticket,
                      self.audioSessionRevision == revision, self.player?.currentItem === item else { return }
                #if DEBUG // P0.1 instrumentation
                self.playbackDiagnostics.mark("SessionActivateEnd")
                #endif // P0.1 instrumentation
                self.audioSessionReady = true
                self.audioSessionNeedsReactivation = false
                self.audioSessionTask = nil
                if self.isPlaying { self.player?.play() }
            } catch {
                guard let self, self.transitionID == ticket, self.audioSessionRevision == revision,
                      !Task.isCancelled else { return }
                self.audioSessionTask = nil
                self.failPlayback(UserFacingErrorMapper.map(error))
            }
        }
        #else
        player?.play()
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
            interruptedPlayback = isPlaying
            audioSessionReady = false
            audioSessionNeedsReactivation = true
            audioSessionRevision = UUID()
            audioSessionTask?.cancel(); audioSessionTask = nil
            if isPlaying { pause() }
        case .ended:
            if let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                if options.contains(.shouldResume), interruptedPlayback {
                    resume()
                }
                interruptedPlayback = false
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
        let position = elapsed ?? player?.currentTime().seconds
        nowPlayingCoordinator.update(track: currentTrack, isPlaying: isPlaying, elapsed: position)
    }

    private func clearNowPlaying() {
        nowPlayingCoordinator.clear()
    }

    private func resetNowPlayingArtwork() {
        nowPlayingCoordinator.resetArtwork()
    }

    private func cancelArtworkTask() {
        nowPlayingCoordinator.resetArtwork()
    }

    private func loadNowPlayingArtwork(for track: MusicPlaybackTrack) {
        nowPlayingCoordinator.loadArtwork(for: track) { [weak self] in
            guard self?.currentTrack?.id == track.id,
                  self?.currentTrack?.coverURLString == track.coverURLString else { return }
            self?.updateNowPlaying()
        }
    }

    private func configureRemoteCommands() {
        remoteCommandCoordinator.install(.init(
            play: { [weak self] in self?.resume() },
            pause: { [weak self] in self?.pause() },
            toggle: { [weak self] in self?.toggle() },
            stop: { [weak self] in self?.stop() },
            next: { [weak self] in await self?.userSkip(by: 1) },
            previous: { [weak self] in await self?.userSkip(by: -1) },
            seek: { [weak self] in self?.seek(to: $0) }
        ))
        updateRemoteCapabilities()
    }

    private func updateRemoteCapabilities() {
        remoteCommandCoordinator.setPreviousEnabled(context?.allowsPrevious ?? true)
    }
}

#if os(iOS)
/// Serializes the OS audio-session calls without blocking UI or ordinary track changes.
private actor PlaybackAudioSession {
    private var configured = false
    private var active = false

    func activate(force: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        if !configured {
            // Playback already supports AirPlay; explicitly allowing it is only valid for playAndRecord.
            try session.setCategory(.playback, mode: .default)
            configured = true
        }
        if !active || force {
            try session.setActive(true)
            active = true
        }
    }
}
#endif

private enum MusicQualityError: Error {
    case unplayable
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

    init(
        id: Int,
        title: String,
        artist: String,
        album: String,
        coverURLString: String?,
        durationMilliseconds: Int,
        mvID: Int?
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.coverURLString = coverURLString
        self.durationMilliseconds = durationMilliseconds
        self.mvID = mvID
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

#if DEBUG
extension MusicPlaybackController {
    /// Seeds presentation state for SwiftUI previews without creating an
    /// `AVPlayer`, configuring the audio session, or touching persisted queues.
    func configurePreview(
        songs: [MusicSong],
        currentIndex: Int = 0,
        queueName: String = "预览播放列表"
    ) {
        let tracks = songs.map(MusicPlaybackTrack.init(song:))
        guard tracks.indices.contains(currentIndex) else { return }

        currentTrack = tracks[currentIndex]
        context = .unknown(reason: .missingProvenance, label: queueName)
        queueTracks = tracks
        self.currentQueueIndex = currentIndex
        currentTimeSeconds = min(83, tracks[currentIndex].durationSeconds)
        playMode = .sequence
        isPlaying = false
        isBuffering = false
        playbackError = nil
        sleepTimerTitle = nil
        feedback = nil
    }
}
#endif
