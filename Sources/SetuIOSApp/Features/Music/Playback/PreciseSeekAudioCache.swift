import AVFoundation
import Foundation
import CryptoKit
import SetuIOSCore
import UniformTypeIdentifiers

/// One indexed asset in memory, with completed audio retained for fast restart.
/// Normal streaming never waits for this optional cache.
@MainActor
final class PreciseSeekAudioCache {
    typealias Download = @Sendable (URL, URL) async throws -> URL
    private struct Prepared {
        let asset: AVURLAsset
        let file: URL
    }
    static let persistentDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("setu-resume-audio-v1", isDirectory: true)
    private let storageDirectory: URL?
    private var identity: String?
    private let download: Download
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("setu-precise-seek-\(UUID().uuidString)", isDirectory: true)
    private var source: URL?
    private var revision = UUID()
    private var task: Task<Prepared, Error>?
    private var prepared: Prepared?

    init(storageDirectory: URL? = nil, download: @escaping Download = { source, destination in
        try await PreciseSeekAudioCache.downloadSource(source, destination)
    }) {
        self.download = download
        self.storageDirectory = storageDirectory
    }

    deinit {
        task?.cancel()
        try? FileManager.default.removeItem(at: directory)
    }

    func prepare(source url: URL, identity key: String? = nil) async throws -> AVURLAsset {
        if source != url || identity != key {
            invalidate()
            source = url
            identity = key
        }
        if let prepared { return prepared.asset }
        let ticket = revision
        let work: Task<Prepared, Error>
        if let task {
            work = task
        } else {
            let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension.isEmpty ? "mp3" : url.pathExtension)
            let download = download
            let cached = key.flatMap { cachedSource(identity: $0) }
            let storedDirectory = key.flatMap { directory(for: $0) }
            work = Task {
                var completeFile: URL?
                do {
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let local: URL
                    if let cached { local = cached } else { local = try await download(url, destination) }
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
                    if cached == nil, let storedDirectory {
                        do {
                            try FileManager.default.createDirectory(at: storedDirectory, withIntermediateDirectories: true)
                            let stored = storedDirectory.appendingPathComponent("audio").appendingPathExtension(local.pathExtension)
                            try FileManager.default.moveItem(at: local, to: stored)
                            return Prepared(asset: AVURLAsset(url: stored, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]), file: stored)
                        } catch {
                            // Disk retention is optional; the validated temporary audio can still play.
                        }
                    }
                    return Prepared(asset: asset, file: local)
                } catch {
                    if let completeFile, cached == nil || !(error is CancellationError) { try? FileManager.default.removeItem(at: completeFile) }
                    throw error
                }
            }
            task = work
        }
        do {
            let result = try await work.value
            guard revision == ticket else {
                throw CancellationError()
            }
            pruneStorage(keeping: result.file)
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
        identity = nil
        try? FileManager.default.removeItem(at: directory)
    }

    private func directory(for identity: String) -> URL? {
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return storageDirectory?.appendingPathComponent(hash, isDirectory: true)
    }

    func cachedSource(identity: String) -> URL? {
        guard let folder = directory(for: identity),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]),
              let file = files.first(where: { $0.deletingPathExtension().lastPathComponent == "audio" }) else { return nil }
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= 256 * 1024 * 1024 else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return file
    }

    private func pruneStorage(keeping file: URL) {
        guard let storageDirectory else { return }
        let folder = file.deletingLastPathComponent()
        guard folder.deletingLastPathComponent() == storageDirectory else { return }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: folder.path)
        let folders = (try? FileManager.default.contentsOfDirectory(at: storageDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let older = folders.filter { $0 != folder }.sorted {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >
            ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        // Keep the current song and one previous source; disk use is bounded at 512 MiB.
        for stale in older.dropFirst() { try? FileManager.default.removeItem(at: stale) }
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
