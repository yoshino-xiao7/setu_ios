import AVFoundation
import Foundation

@MainActor
final class SleepTimerController {
    typealias Sleep = @Sendable (UInt64) async throws -> Void

    private let sleep: Sleep
    private var task: Task<Void, Never>?
    private(set) var pausesAtEndOfTrack = false

    init(sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: $0) }) {
        self.sleep = sleep
    }

    deinit { task?.cancel() }

    func start(_ option: MusicSleepTimerOption, onFire: @escaping @MainActor () -> Void) {
        cancel()
        guard let seconds = option.durationSeconds else {
            pausesAtEndOfTrack = true
            return
        }
        task = Task { [sleep] in
            do { try await sleep(seconds * 1_000_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            onFire()
        }
    }

    func consumeEndOfTrack() -> Bool {
        guard pausesAtEndOfTrack else { return false }
        pausesAtEndOfTrack = false
        return true
    }

    func cancel() {
        task?.cancel()
        task = nil
        pausesAtEndOfTrack = false
    }

    func fadeOutAndPause(player: AVPlayer?, onComplete: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { [sleep] in
            let originalVolume = player?.volume ?? 1
            for step in stride(from: 8, through: 1, by: -1) {
                player?.volume = originalVolume * Float(step) / 8
                do { try await sleep(120_000_000) } catch {
                    player?.volume = originalVolume
                    return
                }
            }
            player?.pause()
            player?.volume = originalVolume
            onComplete()
        }
    }
}
