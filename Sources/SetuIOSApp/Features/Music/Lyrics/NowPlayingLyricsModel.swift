import Foundation
import Observation
import SetuIOSCore

/// Presentation state lives outside the sheet. Structured values belong to the P9 LyricStore.
/// Replace the store on owner changes rather than allowing an old flight to populate a new session.
@MainActor
@Observable
final class NowPlayingLyricsModel {
    private(set) var state: LoadState<[LyricLine]> = .idle
    private(set) var identity: MusicPlaybackIdentity?
    private var owner: Int?
    private var store: LyricStore?
    private var generation = 0
    private var wordEnabled = false

    func invalidate() {
        generation += 1
        store = nil
        identity = nil
        state = .idle
    }

    func load(identity next: MusicPlaybackIdentity, environment: AppEnvironment) async {
        let user = environment.authSession.currentUser?.id
        let enabled = environment.config.musicFeatureFlags.wordByWordLyricsEnabled
        if owner != user || enabled != wordEnabled {
            invalidate()
            owner = user
            wordEnabled = enabled
        }
        if identity == next, case .loaded = state { return }
        generation += 1
        let request = generation
        identity = next
        state = .loading
        do {
            let lines: [LyricLine]
            switch next {
            case .legacy(let id):
                // Never synthesize a canonical token from a legacy number.
                let response = try await environment.musicClient.lyric(songID: id)
                try Task.checkCancellation()
                lines = await Task.detached(priority: .utility) {
                    LyricParser.parse(response.lrc?.lyric ?? "", translation: response.tlyric?.lyric)
                }.value
            case .canonical(let id):
                guard enabled else { throw UserFacingError(message: "此歌曲的歌词入口尚未启用") }
                let cache = store ?? LyricStore(client: environment.musicV2Client)
                store = cache
                let lyric = try await cache.lyric(for: id)
                try Task.checkCancellation()
                lines = await Task.detached(priority: .utility) { LyricParser.parse(lyric) }.value
            }
            guard !Task.isCancelled, generation == request,
                  environment.authSession.currentUser?.id == user else { return }
            state = .loaded(lines)
        } catch {
            guard !Task.isCancelled, generation == request,
                  environment.authSession.currentUser?.id == user else { return }
            state = .failed(UserFacingErrorMapper.map(error))
        }
    }
}
