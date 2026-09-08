import AVFoundation
import SetuIOSCore

@MainActor
final class NextItemPreparer {
    struct Prepared {
        let trackID: MusicPlaybackIdentity
        let quality: MusicAudioQuality
        let source: ResolvedPlaybackURL
        let item: AVPlayerItem
    }
    private(set) var prepared: Prepared?
    private var targetID: MusicPlaybackIdentity?
    private var quality: MusicAudioQuality?
    private var revision = UUID()
    private var task: Task<Void, Never>?
    private let makeItem: @MainActor (URL) async throws -> AVPlayerItem

    init(makeItem: @escaping @MainActor (URL) async throws -> AVPlayerItem = { url in
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else { throw UserFacingError(message: "音源暂时无法播放") }
        try Task.checkCancellation()
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 10
        return item
    }) { self.makeItem = makeItem }

    deinit { task?.cancel() }

    func invalidate(unlessTrackID id: MusicPlaybackIdentity? = nil, quality: MusicAudioQuality? = nil) {
        if let id, targetID == id, self.quality == quality { return }
        revision = UUID()
        task?.cancel(); task = nil
        prepared = nil; targetID = nil; self.quality = nil
    }

    func prepare(trackID: MusicPlaybackIdentity, quality: MusicAudioQuality, resolver: PlaybackURLResolver,
                 makeCachedItem: (@MainActor (ResolvedPlaybackURL) async throws -> AVPlayerItem)? = nil) async {
        invalidate(unlessTrackID: trackID, quality: quality)
        if let prepared, prepared.source.isValid(at: Date()), prepared.item.status != .failed { return }
        if let task { await task.value; return }
        targetID = trackID; self.quality = quality
        let ticket = revision, makeItem = self.makeItem
        let work = Task { [weak self] in
            do {
                let source = try await resolver.resolve(trackID: trackID, quality: quality)
                let item: AVPlayerItem
                if let makeCachedItem { item = try await makeCachedItem(source) } else { item = try await makeItem(source.url) }
                try Task.checkCancellation()
                guard let self, self.revision == ticket, source.isValid(at: Date()) else { return }
                self.prepared = Prepared(trackID: trackID, quality: quality, source: source, item: item)
            } catch { /* Speculative work must never change playback or its error state. */ }
        }
        task = work
        await work.value
        if revision == ticket { task = nil }
    }

    func consume(trackID: MusicPlaybackIdentity, quality: MusicAudioQuality, now: Date = Date()) -> Prepared? {
        guard let prepared, prepared.trackID == trackID, prepared.quality == quality,
              prepared.source.isValid(at: now), prepared.item.status != .failed else { return nil }
        invalidate()
        return prepared
    }
}
