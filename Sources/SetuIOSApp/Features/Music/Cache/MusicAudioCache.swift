import Foundation
import CryptoKit
import UniformTypeIdentifiers
import SetuIOSCore
import OSLog

actor MusicAudioCache {
    static let blockSize = 256 * 1024
    static let maximumCapacity: Int64 = 2 * 1024 * 1024 * 1024
    typealias Transport = @Sendable (URLRequest) -> AsyncThrowingStream<MusicAudioTransport.Event, Error>
    struct Source: Sendable { let key: String; let url: URL; let quality: String }
    struct Info: Sendable { let length: Int64; let mime: String; let supportsRanges: Bool }
    struct Usage: Sendable { let bytes: Int64; let pendingRemoval: Bool; let writeDisabled: Bool }
    struct Metrics: Sendable { var networkBytes: Int64 = 0; var cacheBytes: Int64 = 0; var requests = 0; var firstByteMilliseconds: Double? }
    private struct Segment: Codable { let offset: Int64; let count: Int; let name: String; var end: Int64 { offset + Int64(count) } }
    private struct Entry: Codable {
        let id: String; let key: String; let quality: String
        var sourceHash: String; var validator: String?; var length: Int64?; var mime = "audio/mpeg"
        var ranges = true; var segments: [Segment] = []; var complete: String?
        var used = Date(); var deleteWhenReleased = false
    }
    private struct Assembly { let token: UUID; let task: Task<URL, Error>; var consumers: Set<UUID>; var speculative: Bool }
    private var assemblies: [String: Assembly] = [:]
    private struct Flight { let token: UUID; let task: Task<Void, Never>; var speculative: Bool }
    private let directory: URL
    private let transport: Transport
    private let legacyDirectory: URL?
    private var entries: [String: Entry] = [:]
    private var sources: [String: URL] = [:]
    private var leases: [String: Int] = [:]
    private var flights: [String: Flight] = [:]
    private var failures: [String: Error] = [:]
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var volatile: [String: Data] = [:]
    private var capacity: Int64
    private var canPrefetch = false
    private var playbackWaiting = false
    private var writesDisabled = false
    private var metrics = Metrics()
    private var storedBytes: Int64 = 0
    private var catalogBytes: Int64 = 0
    private var legacyBytes: Int64 = 0
    private let log = Logger(subsystem: "icu.yukiryou.setuios", category: "MusicAudioCache")

    init(directory: URL, capacity: Int64 = 1024 * 1024 * 1024, legacyDirectory: URL? = nil,
         transport: @escaping Transport = { MusicAudioTransport.events(for: $0) }) {
        self.directory = directory; self.legacyDirectory = legacyDirectory; self.capacity = min(max(0, capacity), Self.maximumCapacity); self.transport = transport
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: directory.appendingPathComponent("catalog.json")),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved.mapValues { entry in
                var entry = entry
                entry.segments = entry.segments.filter {
                    let url = directory.appendingPathComponent($0.name)
                    return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) == $0.count
                }
                if let complete = entry.complete,
                   (try? directory.appendingPathComponent(complete).resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) != entry.length { entry.complete = nil }
                return entry
            }.filter { !$0.value.deleteWhenReleased }
        }
        // Startup removes crash leftovers; no playback leases exist yet.
        let names = Set(entries.values.flatMap { $0.segments.map(\.name) + [$0.complete].compactMap { $0 } } + ["catalog.json"])
        for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where !names.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
        legacyBytes = legacyDirectory.map(Self.directorySize) ?? 0
        storedBytes = Self.directorySize(directory) + legacyBytes
        catalogBytes = Int64((try? directory.appendingPathComponent("catalog.json").resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private static func hash(_ string: String) -> String { SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined() }
    func open(_ source: Source) async throws -> String {
        let id = Self.hash(source.key + "|" + source.quality)
        let hash = Self.hash(source.url.absoluteString)
        if var entry = entries[id] {
            if entry.sourceHash != hash, entry.complete == nil {
                for key in Array(flights.keys) where key.hasPrefix(id + ":") { flights.removeValue(forKey: key)?.task.cancel() }
                signal()
                // Never splice partial data across signed URLs without strong content validation.
                if let validator = entry.validator {
                    var request = URLRequest(url: source.url); request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
                    var matches = false
                    for try await event in transport(request) {
                        if case .response(let response) = event {
                            matches = response.value(forHTTPHeaderField: "ETag") == validator && Self.totalLength(response) == entry.length
                            break
                        }
                    }
                    if !matches { removeFiles(entry); entry.segments = []; entry.length = nil; entry.validator = nil }
                } else { removeFiles(entry); entry.segments = []; entry.length = nil }
            }
            entry.sourceHash = hash; entry.used = Date(); entries[id] = entry
        } else { entries[id] = Entry(id: id, key: source.key, quality: source.quality, sourceHash: hash) }
        sources[id] = source.url; leases[id, default: 0] += 1
        save(); return id
    }
    func leaseFile(_ url: URL) -> String? {
        guard let entry = entries.values.first(where: { $0.complete.map { directory.appendingPathComponent($0).standardizedFileURL.path == url.standardizedFileURL.path } == true }) else { return nil }
        leases[entry.id, default: 0] += 1; return entry.id
    }
    func release(_ id: String) {
        leases[id] = max(0, (leases[id] ?? 0) - 1)
        if leases[id] == 0 {
            for key in Array(flights.keys) where key.hasPrefix(id + ":") { flights.removeValue(forKey: key)?.task.cancel() }
            if entries[id]?.deleteWhenReleased == true, let entry = entries.removeValue(forKey: id) { removeFiles(entry) }
        }
        evict(reserving: 0); save(); signal()
    }
    func cachedSource(key: String) -> (URL, String)? {
        if !entries.values.contains(where: { $0.key == key && $0.complete != nil }) { importLegacy(key) }
        guard let entry = entries.values.filter({ $0.key == key && !$0.deleteWhenReleased && $0.complete != nil }).max(by: { $0.used < $1.used }),
              let name = entry.complete else { return nil }
        let url = directory.appendingPathComponent(name)
        guard let length = entry.length, (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) == length else { return nil }
        entries[entry.id]?.used = Date(); return (url, entry.quality)
    }
    private func importLegacy(_ key: String) {
        guard let legacyDirectory else { return }
        let folder = legacyDirectory.appendingPathComponent(Self.hash(key))
        guard let old = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]))?.first(where: { $0.deletingPathExtension().lastPathComponent == "audio" }),
              let size = try? old.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else { return }
        let quality = String(key.split(separator: "|").last ?? "exhigh"), id = Self.hash(key + "|" + quality)
        let name = id + "." + (old.pathExtension.isEmpty ? "mp3" : old.pathExtension), destination = directory.appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: old, to: destination)
            legacyBytes = max(0, legacyBytes - Int64(size))
            if let prior = entries[id] { removeFiles(prior) }
            var entry = Entry(id: id, key: key, quality: quality, sourceHash: Self.hash(destination.absoluteString))
            entry.length = Int64(size); entry.complete = name; entries[id] = entry; save()
        } catch { /* Legacy data is expendable; normal source resolution remains available. */ }
    }

    func discard(key: String) {
        for entry in Array(entries.values) where entry.key == key {
            for flight in Array(flights.keys) where flight.hasPrefix(entry.id + ":") { flights.removeValue(forKey: flight)?.task.cancel() }
            removeFiles(entry); entries[entry.id] = nil
        }
        save(); signal()
    }

    func info(_ id: String) async throws -> Info {
        _ = try await read(id, offset: 0, count: 1)
        guard let entry = entries[id], let length = entry.length else { throw URLError(.badServerResponse) }
        return Info(length: length, mime: entry.mime, supportsRanges: entry.ranges)
    }
    func read(_ id: String, offset: Int64, count: Int, speculative: Bool = false) async throws -> Data {
        guard offset >= 0, count > 0 else { return Data() }
        while true {
            try Task.checkCancellation()
            guard let entry = entries[id], !entry.deleteWhenReleased || (leases[id] ?? 0) > 0 else { throw CancellationError() }
            if let length = entry.length, offset >= length { return Data() }
            if let data = available(entry, offset: offset, count: count), !data.isEmpty {
                metrics.cacheBytes += Int64(data.count); entries[id]?.used = Date(); return data
            }
            if speculative && (!canPrefetch || playbackWaiting || writesDisabled) { throw CancellationError() }
            let block = offset / Int64(Self.blockSize) * Int64(Self.blockSize)
            let key = id + ":" + String(entry.ranges ? block : 0)
            if let error = failures.removeValue(forKey: key) { throw error }
            if var flight = flights[key], !speculative { flight.speculative = false; flights[key] = flight }
            if flights[key] == nil && !flights.keys.contains(where: { $0.hasPrefix(id + ":") && !entry.ranges }) {
                if flights.count < 2 {
                    start(id, offset: entry.ranges ? block : 0, speculative: speculative)
                } else if !speculative, let victim = flights.first(where: { $0.value.speculative }) {
                    flights.removeValue(forKey: victim.key)?.task.cancel(); signal(); continue
                }
            }
            await waitForChange()
        }
    }
    private func available(_ entry: Entry, offset: Int64, count: Int) -> Data? {
        if let name = entry.complete, let handle = try? FileHandle(forReadingFrom: directory.appendingPathComponent(name)) {
            defer { try? handle.close() }; try? handle.seek(toOffset: UInt64(offset))
            return try? handle.read(upToCount: count)
        }
        guard let segment = entry.segments.first(where: { $0.offset <= offset && $0.end > offset }) else { return nil }
        guard let data = volatile[segment.name] ?? (try? Data(contentsOf: directory.appendingPathComponent(segment.name))) else {
            entries[entry.id]?.segments.removeAll { $0.name == segment.name }
            return nil
        }
        let start = Int(offset - segment.offset); return data.subdata(in: start..<min(data.count, start + count))
    }
    private func start(_ id: String, offset: Int64, speculative: Bool) {
        guard let url = sources[id] else { return }
        let key = id + ":" + String(offset), token = UUID(), transport = transport
        failures[key] = nil; metrics.requests += 1
        let task = Task { [weak self] in
            do {
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
                request.setValue("bytes=\(offset)-\(offset + Int64(Self.blockSize) - 1)", forHTTPHeaderField: "Range")
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                let began = ContinuousClock.now
                var position = offset, expectedEnd: Int64?, buffer = Data(), receivedHeader = false
                for try await event in transport(request) {
                    try Task.checkCancellation()
                    guard let self else { throw CancellationError() }
                    switch event {
                    case .response(let response):
                        position = try await self.accept(response, id: id, requested: offset)
                        expectedEnd = response.expectedContentLength >= 0 ? position + response.expectedContentLength : nil
                        receivedHeader = true
                    case .bytes(let data):
                        guard receivedHeader else { throw URLError(.badServerResponse) }
                        await self.received(data.count, since: began)
                        buffer.append(data)
                        while buffer.count >= Self.blockSize {
                            try await self.store(Data(buffer.prefix(Self.blockSize)), id: id, offset: position)
                            buffer.removeFirst(Self.blockSize); position += Int64(Self.blockSize)
                        }
                    }
                }
                if !buffer.isEmpty, let self { try await self.store(buffer, id: id, offset: position); position += Int64(buffer.count) }
                if let expectedEnd, expectedEnd != position { throw URLError(.networkConnectionLost) }
                await self?.finish(key, token: token, error: nil)
            } catch { await self?.finish(key, token: token, error: error) }
        }
        flights[key] = Flight(token: token, task: task, speculative: speculative)
    }
    private func received(_ count: Int, since start: ContinuousClock.Instant) {
        metrics.networkBytes += Int64(count)
        if metrics.firstByteMilliseconds == nil {
            let duration = start.duration(to: .now).components
            metrics.firstByteMilliseconds = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
            log.info("audio.first_byte_ms=\(self.metrics.firstByteMilliseconds ?? 0, privacy: .public)")
        }
    }
    private static func totalLength(_ response: HTTPURLResponse) -> Int64? {
        if let range = response.value(forHTTPHeaderField: "Content-Range"), let last = range.split(separator: "/").last, let size = Int64(last) { return size }
        return response.statusCode == 200 && response.expectedContentLength >= 0 ? response.expectedContentLength : nil
    }
    private func accept(_ response: HTTPURLResponse, id: String, requested: Int64) throws -> Int64 {
        try Task.checkCancellation()
        guard var entry = entries[id] else { throw CancellationError() }
        if response.statusCode == 416 {
            if let length = Self.totalLength(response) { entry.length = length; entries[id] = entry; signal() }
            throw URLError(.badServerResponse)
        }
        guard response.statusCode == 200 || response.statusCode == 206,
              let length = Self.totalLength(response), length > 0 else { throw URLError(.badServerResponse) }
        if response.statusCode == 206 {
            guard let header = response.value(forHTTPHeaderField: "Content-Range"), header.hasPrefix("bytes "),
                  let span = header.dropFirst(6).split(separator: "/").first else { throw URLError(.badServerResponse) }
            let bounds = span.split(separator: "-")
            guard bounds.count == 2, let start = Int64(bounds[0]), let end = Int64(bounds[1]),
                  start == requested, end >= start, end < length,
                  response.expectedContentLength < 0 || response.expectedContentLength == end - start + 1 else { throw URLError(.badServerResponse) }
        }
        let tag = response.value(forHTTPHeaderField: "ETag").flatMap { $0.hasPrefix("W/") ? nil : $0 }
        if let old = entry.validator, let tag, old != tag, !entry.segments.isEmpty { throw URLError(.resourceUnavailable) }
        if let old = entry.length, old != length, !entry.segments.isEmpty { throw URLError(.resourceUnavailable) }
        entry.length = length; entry.mime = response.mimeType ?? "audio/mpeg"; entry.ranges = response.statusCode == 206; entry.validator = tag
        entries[id] = entry; signal(); return entry.ranges ? requested : 0
    }
    private func store(_ data: Data, id: String, offset: Int64) throws {
        try Task.checkCancellation()
        guard var entry = entries[id] else { throw CancellationError() }
        if entry.segments.contains(where: { $0.offset == offset && $0.count >= data.count &&
            (volatile[$0.name] != nil || FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.name).path)) }) { return }
        let name = id + "-" + String(offset) + "-" + UUID().uuidString + ".part"
        evict(reserving: Int64(data.count))
        do {
            guard !writesDisabled, diskBytes() + Int64(data.count) * 2 + 4 * 1024 * 1024 <= capacity else { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            storedBytes += Int64(data.count)
        } catch {
            writesDisabled = true
            if volatile.values.reduce(0, { $0 + $1.count }) > 4 * 1024 * 1024 {
                if let first = volatile.keys.first { volatile[first] = nil }
            }
            volatile[name] = data
        }
        entry.segments.append(Segment(offset: offset, count: data.count, name: name)); entry.used = Date()
        entries[id] = entry; save(); signal()
    }
    private func finish(_ key: String, token: UUID, error: Error?) {
        guard flights[key]?.token == token else { return }
        flights[key] = nil; if let error { failures[key] = error }; signal()
    }
    private func waitForChange() async {
        let ticket = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume() } else { waiters[ticket] = continuation }
            }
        } onCancel: { Task { await self.cancelWait(ticket) } }
    }
    private func cancelWait(_ id: UUID) { waiters.removeValue(forKey: id)?.resume() }
    private func signal() { let pending = waiters.values; waiters.removeAll(); for waiter in pending { waiter.resume() } }

    func prefetch(_ id: String, limit: Int = 3 * 1024 * 1024) async throws {
        var offset: Int64 = 0
        while offset < limit {
            let data = try await read(id, offset: offset, count: min(Self.blockSize, limit - Int(offset)), speculative: true)
            if data.isEmpty { break }; offset += Int64(data.count)
        }
    }
    func completeFile(_ id: String, speculative: Bool = false) async throws -> URL {
        let consumer = UUID()
        if let name = entries[id]?.complete { return directory.appendingPathComponent(name) }
        if assemblies[id] == nil {
            let token = UUID()
            assemblies[id] = Assembly(token: token, task: Task { try await self.buildCompleteFile(id) }, consumers: [], speculative: speculative)
        }
        assemblies[id]?.consumers.insert(consumer)
        if !speculative { assemblies[id]?.speculative = false }
        let assembly = assemblies[id]!
        do {
            let result = try await withTaskCancellationHandler {
                try await assembly.task.value
            } onCancel: { Task { await self.releaseAssembly(id, token: assembly.token, consumer: consumer) } }
            releaseAssembly(id, token: assembly.token, consumer: consumer)
            try Task.checkCancellation()
            return result
        } catch { releaseAssembly(id, token: assembly.token, consumer: consumer); throw error }
    }
    private func releaseAssembly(_ id: String, token: UUID, consumer: UUID) {
        guard assemblies[id]?.token == token else { return }
        assemblies[id]?.consumers.remove(consumer)
        if assemblies[id]?.consumers.isEmpty == true { assemblies.removeValue(forKey: id)?.task.cancel() }
    }
    private func buildCompleteFile(_ id: String) async throws -> URL {
        if assemblies[id]?.speculative == true && (!canPrefetch || playbackWaiting || writesDisabled) { throw CancellationError() }
        if let name = entries[id]?.complete { return directory.appendingPathComponent(name) }
        let info = try await info(id)
        guard info.length <= capacity / 2 else { throw UserFacingError(message: "缓存空间不足以准备精确跳转，请提高缓存上限") }
        var offset: Int64 = 0
        while offset < info.length {
            let data = try await read(id, offset: offset, count: Self.blockSize, speculative: assemblies[id]?.speculative ?? false)
            guard !data.isEmpty else { throw URLError(.networkConnectionLost) }; offset += Int64(data.count)
        }
        evict(reserving: info.length)
        guard diskBytes() + info.length <= capacity, !writesDisabled else { throw CocoaError(.fileWriteOutOfSpace) }
        let fileExtension = UTType(mimeType: info.mime)?.preferredFilenameExtension ?? "mp3"
        let name = id + "." + fileExtension, temporary = directory.appendingPathComponent(id + "-" + UUID().uuidString + ".assembling")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temporary)
        var assembledBytes: Int64 = 0
        do {
            offset = 0
            while offset < info.length {
                try Task.checkCancellation()
                guard let entry = entries[id], let data = available(entry, offset: offset, count: Self.blockSize), !data.isEmpty else { throw URLError(.cannotDecodeContentData) }
                try handle.write(contentsOf: data); offset += Int64(data.count)
                assembledBytes += Int64(data.count); storedBytes += Int64(data.count)
            }
            try handle.close()
            try FileManager.default.moveItem(at: temporary, to: directory.appendingPathComponent(name))
            if var entry = entries[id] {
                for segment in entry.segments { removeFile(segment.name); volatile[segment.name] = nil }
                entry.segments = []; entry.complete = name; entries[id] = entry
            }
            save(); return directory.appendingPathComponent(name)
        } catch { try? handle.close(); try? FileManager.default.removeItem(at: temporary); storedBytes -= assembledBytes; throw error }
    }
    func configure(capacity: Int64, prefetchAllowed: Bool, playbackWaiting: Bool = false) {
        if capacity > self.capacity { writesDisabled = false }
        self.capacity = min(max(0, capacity), Self.maximumCapacity); canPrefetch = prefetchAllowed; self.playbackWaiting = playbackWaiting
        if !canPrefetch || playbackWaiting {
            for assembly in assemblies.values where assembly.speculative { assembly.task.cancel() }
            for key in Array(flights.keys) where flights[key]?.speculative == true { flights.removeValue(forKey: key)?.task.cancel() }
        }
        evict(reserving: 0); save(); signal()
    }
    func clear() {
        for assembly in assemblies.values where assembly.speculative { assembly.task.cancel() }
        for key in Array(flights.keys) where flights[key]?.speculative == true { flights.removeValue(forKey: key)?.task.cancel() }
        for entry in Array(entries.values) {
            if (leases[entry.id] ?? 0) > 0 { entries[entry.id]?.deleteWhenReleased = true }
            else { removeFiles(entry); entries[entry.id] = nil }
        }
        if let legacyDirectory { try? FileManager.default.removeItem(at: legacyDirectory); storedBytes -= legacyBytes; legacyBytes = 0 }
        writesDisabled = false; save(); signal()
    }
    func usage() -> Usage { Usage(bytes: diskBytes(), pendingRemoval: entries.values.contains(where: \.deleteWhenReleased), writeDisabled: writesDisabled) }
    func statistics() -> Metrics { metrics }
    func resetStatistics() { metrics = Metrics() }
    private func diskBytes() -> Int64 { max(0, storedBytes) }
    nonisolated private static func directorySize(_ directory: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            if let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }
    private func evict(reserving bytes: Int64) {
        if diskBytes() + bytes > capacity, let legacyDirectory {
            try? FileManager.default.removeItem(at: legacyDirectory); storedBytes -= legacyBytes; legacyBytes = 0
        }
        for entry in entries.values.sorted(by: { $0.used < $1.used }) where diskBytes() + bytes > capacity && (leases[entry.id] ?? 0) == 0 {
            removeFiles(entry); entries[entry.id] = nil
        }
    }
    private func removeFiles(_ entry: Entry) {
        for name in entry.segments.map(\.name) + [entry.complete].compactMap({ $0 }) {
            removeFile(name); volatile[name] = nil
        }
    }
    private func removeFile(_ name: String) {
        let url = directory.appendingPathComponent(name)
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        do { try FileManager.default.removeItem(at: url); storedBytes -= size } catch {}
    }
    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            do {
                try data.write(to: directory.appendingPathComponent("catalog.json"), options: .atomic)
                storedBytes += Int64(data.count) - catalogBytes; catalogBytes = Int64(data.count)
            } catch {}
        }
    }
}
