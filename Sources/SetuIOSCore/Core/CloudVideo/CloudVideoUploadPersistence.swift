import Foundation

public protocol CloudVideoUploadPersisting: Sendable {
    func load() throws -> CloudVideoUploadSnapshot
    func save(_ snapshot: CloudVideoUploadSnapshot) throws
}

public struct CloudVideoUploadSnapshot: Codable, Sendable, Equatable {
    public var wifiOnly: Bool
    public var items: [CloudVideoUploadItem]

    public init(wifiOnly: Bool = true, items: [CloudVideoUploadItem] = []) {
        self.wifiOnly = wifiOnly
        self.items = items
    }
}

public final class CloudVideoUploadMemoryPersistence: CloudVideoUploadPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot = CloudVideoUploadSnapshot()

    public init(snapshot: CloudVideoUploadSnapshot = CloudVideoUploadSnapshot()) {
        self.snapshot = snapshot
    }

    public func load() throws -> CloudVideoUploadSnapshot {
        lock.withLock { snapshot }
    }

    public func save(_ snapshot: CloudVideoUploadSnapshot) throws {
        lock.withLock { self.snapshot = snapshot }
    }
}

public struct CloudVideoUploadFilePersistence: CloudVideoUploadPersisting, Sendable {
    private let url: URL

    public init(url: URL? = nil) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = url ?? directory.appendingPathComponent("CloudVideoUploadQueue.json")
    }

    public func load() throws -> CloudVideoUploadSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return CloudVideoUploadSnapshot()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CloudVideoUploadSnapshot.self, from: data)
    }

    public func save(_ snapshot: CloudVideoUploadSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }
}
