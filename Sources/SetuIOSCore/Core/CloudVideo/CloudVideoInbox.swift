import Foundation

public protocol CloudVideoInboxing: Sendable {
    func materialize(itemId: String, from source: URL, fileName: String) async throws -> URL
    func remove(itemId: String)
}

public struct CloudVideoInbox: CloudVideoInboxing, Sendable {
    private let root: URL
    private let fileManager: FileManager
    private let minimumFreeBytes: Int64

    public init(
        root: URL? = nil,
        fileManager: FileManager = .default,
        minimumFreeBytes: Int64 = 64 * 1024 * 1024
    ) {
        self.root = root ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudVideoInbox", isDirectory: true)
        self.fileManager = fileManager
        self.minimumFreeBytes = minimumFreeBytes
    }

    public func materialize(itemId: String, from source: URL, fileName: String) async throws -> URL {
        try fileManager.createDirectory(at: itemDirectory(itemId), withIntermediateDirectories: true)
        let destination = itemDirectory(itemId).appendingPathComponent(safeFileName(fileName))
        if fileManager.fileExists(atPath: destination.path) {
            return destination
        }
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        try requireSpace(needed: size)
        let accessed = source.startAccessingSecurityScopedResource()
        defer {
            if accessed { source.stopAccessingSecurityScopedResource() }
        }
        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            if source.standardizedFileURL == destination.standardizedFileURL {
                return destination
            }
            throw error
        }
        return destination
    }

    public func remove(itemId: String) {
        try? fileManager.removeItem(at: itemDirectory(itemId))
    }

    private func itemDirectory(_ itemId: String) -> URL {
        root.appendingPathComponent(itemId, isDirectory: true)
    }

    private func safeFileName(_ fileName: String) -> String {
        let trimmed = (fileName as NSString).lastPathComponent
        return trimmed.isEmpty ? "video.bin" : trimmed
    }

    private func requireSpace(needed: Int64) throws {
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage,
           available < needed + minimumFreeBytes {
            throw CloudVideoUploadError.noSpace
        }
    }
}

public struct CloudVideoPassthroughInbox: CloudVideoInboxing, Sendable {
    public init() {}

    public func materialize(itemId: String, from source: URL, fileName: String) async throws -> URL {
        _ = itemId
        _ = fileName
        return source
    }

    public func remove(itemId: String) {}
}
