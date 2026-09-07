import AVFoundation
import Foundation
import SetuIOSCore
import UniformTypeIdentifiers

/// One complete source at a time. Streaming never waits for this optional cache.
@MainActor
final class PreciseSeekAudioCache {
    typealias Download = @Sendable (URL, URL) async throws -> URL
    private struct Prepared {
        let asset: AVURLAsset
        let file: URL
    }
    private let download: Download
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("setu-precise-seek-\(UUID().uuidString)", isDirectory: true)
    private var source: URL?
    private var revision = UUID()
    private var task: Task<Prepared, Error>?
    private var prepared: Prepared?

    init(download: @escaping Download = { source, destination in
        try await PreciseSeekAudioCache.downloadSource(source, destination)
    }) {
        self.download = download
    }

    deinit {
        task?.cancel()
        try? FileManager.default.removeItem(at: directory)
    }

    func prepare(source url: URL) async throws -> AVURLAsset {
        if source != url {
            invalidate()
            source = url
        }
        if let prepared { return prepared.asset }
        let ticket = revision
        let work: Task<Prepared, Error>
        if let task {
            work = task
        } else {
            let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension.isEmpty ? "mp3" : url.pathExtension)
            let download = download
            work = Task {
                var completeFile: URL?
                do {
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let local = try await download(url, destination)
                    completeFile = local
                    try Task.checkCancellation()
                    let size = try local.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size > 0, size <= 256 * 1024 * 1024 else {
                        throw UserFacingError(message: "音频缓存大小不支持精确跳转")
                    }
                    let asset = AVURLAsset(url: local, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
                    let playable = try await asset.load(.isPlayable)
                    let duration = try await asset.load(.duration).seconds
                    let precise = try await asset.load(.providesPreciseDurationAndTiming)
                    guard playable, precise, duration.isFinite, duration > 0 else {
                        throw UserFacingError(message: "无法建立精确音频索引")
                    }
                    try Task.checkCancellation()
                    return Prepared(asset: asset, file: local)
                } catch {
                    if let completeFile { try? FileManager.default.removeItem(at: completeFile) }
                    throw error
                }
            }
            task = work
        }
        do {
            let result = try await work.value
            guard revision == ticket else {
                try? FileManager.default.removeItem(at: result.file)
                throw CancellationError()
            }
            prepared = result
            return result.asset
        } catch {
            if revision == ticket { task = nil }
            throw error
        }
    }

    func invalidate() {
        revision = UUID()
        task?.cancel(); task = nil
        prepared = nil
        source = nil
        try? FileManager.default.removeItem(at: directory)
    }

    nonisolated private static func downloadSource(_ source: URL, _ destination: URL) async throws -> URL {
        if source.isFileURL {
            try await Task.detached(priority: .utility) {
                try Task.checkCancellation()
                try FileManager.default.copyItem(at: source, to: destination)
            }.value
            return destination
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: source, cachePolicy: .reloadIgnoringLocalCacheData)
        let (temporary, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UserFacingError(message: "无法取得完整音频，请稍后重试")
        }
        let mediaExtension = http.mimeType.flatMap { UTType(mimeType: $0) }
            .flatMap { $0.conforms(to: .audio) ? $0.preferredFilenameExtension : nil }
        let finalURL = mediaExtension.map { destination.deletingPathExtension().appendingPathExtension($0) } ?? destination
        try FileManager.default.moveItem(at: temporary, to: finalURL)
        return finalURL
    }
}
