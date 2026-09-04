import Foundation

/// A low-frequency derived view. The controller's fine-grained observable
/// properties remain the source of truth for progress and controls.
enum PlaybackPhase: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case failed

    static func derive(hasTrack: Bool, isBuffering: Bool, isPlaying: Bool, hasError: Bool) -> Self {
        if hasError { return .failed }
        if !hasTrack { return .idle }
        if isBuffering { return .loading }
        return isPlaying ? .playing : .paused
    }
}
