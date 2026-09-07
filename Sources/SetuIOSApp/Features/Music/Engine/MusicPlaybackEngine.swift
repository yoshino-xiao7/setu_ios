import Foundation

/// The business layer owns intent; the engine publishes only observations of its current media.
struct MusicEngineSnapshot: Sendable, Equatable {
    enum State: String, Sendable { case idle, opening, buffering, playing, paused, ended, failed }
    let mediaID: UUID
    let state: State
    let positionMilliseconds: Int64
    let durationMilliseconds: Int64
    let seekable: Bool
}

@MainActor
protocol MusicPlaybackEngine: AnyObject {
    var snapshot: MusicEngineSnapshot? { get }
    var onChange: ((MusicEngineSnapshot) -> Void)? { get set }
    var volume: Float { get set }
    func load(url: URL, mediaID: UUID)
    func play()
    func pause()
    func stop()
    func seek(toMilliseconds: Int64) async throws
}
