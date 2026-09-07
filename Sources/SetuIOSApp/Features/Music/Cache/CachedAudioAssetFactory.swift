import AVFoundation
import Foundation
import ObjectiveC
import UniformTypeIdentifiers

private var audioLoaderAssociation: UInt8 = 0

@MainActor
final class CachedAudioAssetFactory {
    let cache: MusicAudioCache
    init(cache: MusicAudioCache) { self.cache = cache }

    func asset(source: MusicAudioCache.Source) -> AVURLAsset {
        if source.url.isFileURL {
            let asset = AVURLAsset(url: source.url)
            objc_setAssociatedObject(asset, &audioLoaderAssociation, CachedAudioResourceLoader(cache: cache, source: source), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return asset
        }
        var components = URLComponents(url: source.url, resolvingAgainstBaseURL: false)!
        components.scheme = "setu-audio"
        let asset = AVURLAsset(url: components.url!)
        let loader = CachedAudioResourceLoader(cache: cache, source: source)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        objc_setAssociatedObject(asset, &audioLoaderAssociation, loader, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return asset
    }
    func cachedSource(key: String) async -> (URL, String)? { await cache.cachedSource(key: key) }
    func prefetch(source: MusicAudioCache.Source) async throws {
        let id = try await cache.open(source)
        do { try await cache.prefetch(id); await cache.release(id) }
        catch { await cache.release(id); throw error }
    }
    func preciseAsset(source: MusicAudioCache.Source, speculative: Bool = false) async throws -> AVURLAsset {
        if source.url.isFileURL {
            let asset = AVURLAsset(url: source.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            objc_setAssociatedObject(asset, &audioLoaderAssociation, CachedAudioResourceLoader(cache: cache, source: source), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return asset
        }
        let id = try await cache.open(source)
        do {
            let url = try await cache.completeFile(id, speculative: speculative)
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            guard try await asset.load(.isPlayable), try await asset.load(.providesPreciseDurationAndTiming) else { throw URLError(.cannotDecodeContentData) }
            // Keep the disk lease for the lifetime of this asset, including while playing.
            objc_setAssociatedObject(asset, &audioLoaderAssociation, CachedAudioResourceLoader(cache: cache, leasedID: id), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return asset
        } catch { await cache.release(id); throw error }
    }
    func canSeekNatively(_ source: MusicAudioCache.Source) async -> Bool {
        guard !source.url.isFileURL else { return false }
        guard let id = try? await cache.open(source) else { return false }
        do {
            let info = try await cache.info(id)
            let data = try await cache.read(id, offset: 0, count: 64 * 1024)
            await cache.release(id)
            return AudioSeekIndex.supportsDirectSeek(header: data, fileLength: info.length)
        } catch { await cache.release(id); return false }
    }
}

private final class CachedAudioResourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "setu.music.resource-loader")
    private let cache: MusicAudioCache
    private let source: MusicAudioCache.Source?
    private var opening: Task<String, Error>?
    private var leasedID: String?
    private var requests: [ObjectIdentifier: Task<Void, Never>] = [:]
    init(cache: MusicAudioCache, source: MusicAudioCache.Source) { self.cache = cache; self.source = source; self.opening = Task {
            if source.url.isFileURL, let id = await cache.leaseFile(source.url) { return id }
            return try await cache.open(source)
        } }
    init(cache: MusicAudioCache, leasedID: String) { self.cache = cache; self.leasedID = leasedID; source = nil }
    deinit {
        for task in requests.values { task.cancel() }
        let cache = cache
        if let leasedID { Task { await cache.release(leasedID) } }
        else if let opening { Task { if let id = try? await opening.value { await cache.release(id) } } }
    }
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard let source else { return false }
        if opening == nil { let cache = cache; opening = Task { try await cache.open(source) } }
        let opening = opening!, cache = cache, key = ObjectIdentifier(request), queue = queue
        requests[key] = Task { [weak self] in
            do {
                let id = try await opening.value
                let info = try await cache.info(id)
                try Task.checkCancellation()
                await withCheckedContinuation { continuation in
                    queue.async {
                        if !request.isCancelled {
                            request.contentInformationRequest?.contentType = UTType(mimeType: info.mime)?.identifier ?? UTType.mp3.identifier
                            request.contentInformationRequest?.contentLength = info.length
                            request.contentInformationRequest?.isByteRangeAccessSupported = true
                        }
                        continuation.resume()
                    }
                }
                if let dataRequest = request.dataRequest {
                    var offset = max(dataRequest.requestedOffset, dataRequest.currentOffset)
                    let end = dataRequest.requestsAllDataToEndOfResource ? info.length : min(info.length, dataRequest.requestedOffset + Int64(dataRequest.requestedLength))
                    while offset < end {
                        try Task.checkCancellation()
                        let data = try await cache.read(id, offset: offset, count: Int(min(Int64(MusicAudioCache.blockSize), end - offset)))
                        guard !data.isEmpty else { break }
                        try Task.checkCancellation()
                        await withCheckedContinuation { continuation in
                            queue.async { if !request.isCancelled { dataRequest.respond(with: data) }; continuation.resume() }
                        }
                        offset += Int64(data.count)
                    }
                }
                queue.async { [weak self] in
                    if !request.isCancelled { request.finishLoading() }
                    self?.requests[key] = nil
                }
            } catch {
                queue.async { [weak self] in
                    if !request.isCancelled { request.finishLoading(with: error) }
                    self?.requests[key] = nil
                }
            }
        }
        return true
    }
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        requests.removeValue(forKey: ObjectIdentifier(loadingRequest))?.cancel()
    }
}
