import Foundation
import SetuIOSCore

enum AsmrPlayback {
    static func track(_ track: AsmrTrack, work: AsmrWork) -> MusicPlaybackTrack {
        MusicPlaybackTrack(
            identity: .canonical(MusicV2TrackID(rawValue: "asmr:track:\(track.id)")),
            title: track.title,
            artist: work.circleName ?? work.displayTitle,
            album: work.displayTitle,
            coverURLString: work.coverURL,
            durationMilliseconds: Int((track.durationSeconds ?? work.durationSeconds.map(Double.init) ?? 0) * 1000),
            streamURL: track.url
        )
    }

    static func queue(_ tracks: [AsmrTrack], work: AsmrWork) -> [MusicPlaybackTrack] {
        tracks.map { track($0, work: work) }
    }
}
