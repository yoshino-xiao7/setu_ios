import Foundation

#if os(iOS)
import MediaPlayer
import UIKit
#endif

@MainActor
final class NowPlayingCoordinator {
    struct Metadata: Equatable {
        let title: String
        let artist: String
        let album: String
        let duration: Double?
        let elapsed: Double?
        let playbackRate: Double
    }

    private(set) var metadata: Metadata?
    #if os(iOS)
    private var artworkTask: Task<Void, Never>?
    private var artwork: MPMediaItemArtwork?
    private var artworkTrackID: Int?
    #endif

    deinit {
        #if os(iOS)
        artworkTask?.cancel()
        #endif
    }

    func update(track: MusicPlaybackTrack?, isPlaying: Bool, elapsed: Double?) {
        guard let track else {
            clear()
            return
        }
        metadata = Metadata(
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.durationSeconds > 0 ? track.durationSeconds : nil,
            elapsed: elapsed.map { max(0, $0) },
            playbackRate: isPlaying ? 1 : 0
        )
        publish(track: track)
    }

    func loadArtwork(for track: MusicPlaybackTrack, onChange: @escaping @MainActor () -> Void) {
        #if os(iOS)
        guard let key = SetuImageKey.music(track.coverURLString, size: .large) else { return }
        artworkTask?.cancel()
        if let image = SetuRemoteImageLoader.shared.cachedImage(for: key) {
            apply(image, track: track, onChange: onChange)
            return
        }
        artworkTask = Task { [weak self] in
            do {
                let image = try await SetuRemoteImageLoader.shared.image(for: key)
                guard !Task.isCancelled else { return }
                self?.apply(image, track: track, onChange: onChange)
            } catch {
                // Artwork is optional and must never interrupt playback.
            }
        }
        #endif
    }

    func resetArtwork() {
        #if os(iOS)
        artworkTask?.cancel()
        artworkTask = nil
        artwork = nil
        artworkTrackID = nil
        #endif
    }

    func clear() {
        metadata = nil
        resetArtwork()
        #if os(iOS)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #endif
    }

    private func publish(track: MusicPlaybackTrack) {
        #if os(iOS)
        guard let metadata else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: metadata.title,
            MPMediaItemPropertyArtist: metadata.artist,
            MPMediaItemPropertyAlbumTitle: metadata.album,
            MPNowPlayingInfoPropertyPlaybackRate: metadata.playbackRate
        ]
        if let duration = metadata.duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let elapsed = metadata.elapsed { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed }
        if artworkTrackID == track.id, let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #endif
    }

    #if os(iOS)
    private func apply(_ image: UIImage, track: MusicPlaybackTrack, onChange: @escaping @MainActor () -> Void) {
        artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        artworkTrackID = track.id
        onChange()
    }
    #endif
}
