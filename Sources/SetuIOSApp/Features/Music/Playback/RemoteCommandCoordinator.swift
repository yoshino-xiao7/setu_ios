import Foundation

#if os(iOS)
import MediaPlayer
#endif

@MainActor
final class RemoteCommandCoordinator {
    struct Handlers {
        let play: @MainActor () -> Void
        let pause: @MainActor () -> Void
        let toggle: @MainActor () -> Void
        let stop: @MainActor () -> Void
        let next: @MainActor () async -> Void
        let previous: @MainActor () async -> Void
        let seek: @MainActor (Double) -> Void
    }

    private(set) var isInstalled = false
    private(set) var previousEnabled = true
    #if os(iOS)
    private var tokens: [(MPRemoteCommand, Any)] = []
    #endif

    deinit {
        #if os(iOS)
        for (command, token) in tokens { command.removeTarget(token) }
        #endif
    }

    func install(_ handlers: Handlers) {
        guard !isInstalled else { return }
        isInstalled = true
        #if os(iOS)
        let center = MPRemoteCommandCenter.shared()
        tokens = [
            (center.playCommand, center.playCommand.addTarget { _ in Task { @MainActor in handlers.play() }; return .success }),
            (center.pauseCommand, center.pauseCommand.addTarget { _ in Task { @MainActor in handlers.pause() }; return .success }),
            (center.togglePlayPauseCommand, center.togglePlayPauseCommand.addTarget { _ in Task { @MainActor in handlers.toggle() }; return .success }),
            (center.stopCommand, center.stopCommand.addTarget { _ in Task { @MainActor in handlers.stop() }; return .success }),
            (center.nextTrackCommand, center.nextTrackCommand.addTarget { _ in Task { @MainActor in await handlers.next() }; return .success }),
            (center.previousTrackCommand, center.previousTrackCommand.addTarget { _ in Task { @MainActor in await handlers.previous() }; return .success }),
            (center.changePlaybackPositionCommand, center.changePlaybackPositionCommand.addTarget { event in
                guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
                Task { @MainActor in handlers.seek(event.positionTime) }
                return .success
            })
        ]
        center.nextTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = previousEnabled
        #endif
    }

    func setPreviousEnabled(_ enabled: Bool) {
        previousEnabled = enabled
        #if os(iOS)
        MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = enabled
        #endif
    }

    func uninstall() {
        #if os(iOS)
        for (command, token) in tokens { command.removeTarget(token) }
        tokens.removeAll()
        #endif
        isInstalled = false
    }
}
