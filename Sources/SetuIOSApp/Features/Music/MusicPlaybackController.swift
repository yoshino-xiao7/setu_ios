import AVFoundation
import Foundation
import Observation
import SetuIOSCore

#if os(iOS)
import MediaPlayer
#endif

@MainActor
@Observable
final class MusicPlaybackController {
    private(set) var currentTrack: MusicPlaybackTrack?
    private(set) var queueName: String?
    private(set) var queueTracks: [MusicPlaybackTrack] = []
    private(set) var currentQueueIndex: Int?
    private(set) var isPlaying = false
    private(set) var message: String?

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var remoteCommandsConfigured = false

    deinit {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
    }

    func play(
        url: URL,
        track: MusicPlaybackTrack,
        queueName: String? = nil,
        queueTracks: [MusicPlaybackTrack] = []
    ) {
        configureAudioSession()
        configureRemoteCommands()
        removeTimeObserver()

        let item = AVPlayerItem(url: url)
        let nextPlayer = AVPlayer(playerItem: item)
        let nextQueue = queueTracks.isEmpty ? [track] : queueTracks
        player = nextPlayer
        currentTrack = track
        self.queueName = queueName
        self.queueTracks = nextQueue
        currentQueueIndex = nextQueue.firstIndex { $0.id == track.id }
        isPlaying = true
        message = "正在播放 \(track.title)"
        addTimeObserver()
        updateNowPlaying(elapsed: 0)
        nextPlayer.play()
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
        message = nil
        removeTimeObserver()
        clearNowPlaying()
    }

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

    private func addTimeObserver() {
        guard let player else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.updateNowPlaying(elapsed: time.seconds)
            }
        }
    }

    private func removeTimeObserver() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }

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
