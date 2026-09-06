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
    private var transportEnabled = false

    func invalidate() {
        generation += 1
        store = nil
        identity = nil
        state = .idle
    }

    func load(identity next: MusicPlaybackIdentity, environment: AppEnvironment) async {
        let user = environment.authSession.currentUser?.id
        let enabled = environment.config.musicFeatureFlags.wordByWordLyricsEnabled
        let transport = environment.config.musicFeatureFlags.usesV2Lyrics
        if owner != user || enabled != wordEnabled || transport != transportEnabled {
            invalidate()
            owner = user
            wordEnabled = enabled
            transportEnabled = transport
        }
        if identity == next, case .loaded = state { return }
        generation += 1
        let request = generation
        identity = next
        state = .loading
        do {
            let lines: [LyricLine]
            let requested: MusicPlaybackIdentity
            if case .legacy(let id) = next, transport {
                guard id > 0 else { throw UserFacingError(message: "歌曲标识无效") }
                let token = MusicV2TrackID(rawValue: "netease:track:\(id)")
                let track = try await environment.musicV2Client.track(token)
                guard track.id == token else { throw UserFacingError(message: "歌曲来源不匹配") }
                requested = .canonical(track.id)
            } else { requested = next }
            switch requested {
            case .legacy(let id):
                // Never synthesize a canonical token from a legacy number.
                let response = try await environment.musicClient.lyric(songID: id)
                MusicClientObservation.emit((response.lrc?.lyric?.isEmpty == false) ? "lyrics.line" : "lyrics.none", v2: false)
                try Task.checkCancellation()
                lines = await Task.detached(priority: .utility) {
                    LyricParser.parse(response.lrc?.lyric ?? "", translation: response.tlyric?.lyric)
                }.value
            case .canonical(let id):
                guard transport else { throw UserFacingError(message: "此歌曲的歌词入口尚未启用") }
                let cache = store ?? LyricStore(client: environment.musicV2Client)
                store = cache
                let lyric = try await cache.lyric(for: id)
                let kind: String = switch lyric.kind { case .none: "none"; case .plain: "plain"; case .line: "line"; case .word: "word"; case .unknown: "failed" }
                MusicClientObservation.emit("lyrics.\(kind)", v2: true)
                try Task.checkCancellation()
                lines = await Task.detached(priority: .utility) {
                    LyricParser.parse(lyric).map { line in
                        var line = line
                        if !enabled { line.words = [] }
                        return line
                    }
                }.value
            }
            guard !Task.isCancelled, generation == request,
                  environment.authSession.currentUser?.id == user else { return }
            state = .loaded(lines)
        } catch {
            guard !Task.isCancelled, generation == request,
                  environment.authSession.currentUser?.id == user else { return }
            MusicClientObservation.emit("lyrics.failed", v2: transport)
            state = .failed(UserFacingErrorMapper.map(error))
        }
    }
}
