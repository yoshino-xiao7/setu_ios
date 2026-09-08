import AVFoundation
import XCTest
@testable import SetuIOSApp

final class MusicAudioCacheTests: XCTestCase {
    private func temporaryDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("audio-cache-test-\(UUID().uuidString)") }
    private let source = MusicAudioCache.Source(key: "account|song|high", url: URL(string: "https://audio.example/song.mp3")!, quality: "high")
    private func transport(_ data: Data, ranges: Bool = true, counter: MusicTestCounter = MusicTestCounter(), gate: MusicTestGate? = nil,
                           validator: String? = "\"version1\"") -> MusicAudioCache.Transport {
        { request in
            AsyncThrowingStream { continuation in
                let task = Task {
                    _ = await counter.next()
                    let values = (request.value(forHTTPHeaderField: "Range") ?? "bytes=0-0").dropFirst(6).split(separator: "-")
                    let offset = ranges ? Int(values.first!)! : 0
                    let end = ranges ? min(data.count, Int(values.last!)! + 1) : data.count
                    var headers = ["Content-Type": "audio/mpeg", "Content-Length": String(max(0, end - offset))]
                    if let validator { headers["ETag"] = validator }
                    if ranges { headers["Content-Range"] = offset < data.count ? "bytes \(offset)-\(end - 1)/\(data.count)" : "bytes */\(data.count)" }
                    continuation.yield(.response(HTTPURLResponse(url: request.url!, statusCode: offset >= data.count ? 416 : (ranges ? 206 : 200), httpVersion: nil, headerFields: headers)!))
                    if offset < data.count {
                        for start in stride(from: offset, to: end, by: 65_536) {
                            if start == 262_144, let gate { await gate.wait() }
                            if Task.isCancelled { continuation.finish(throwing: CancellationError()); return }
                            continuation.yield(.bytes(data.subdata(in: start..<min(end, start + 65_536))))
                            try? await Task.sleep(for: .milliseconds(1))
                        }
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }

    func testShortResponseCannotBecomeACompleteCacheFile() async throws {
        let folder = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let cache = MusicAudioCache(directory: folder, transport: { request in
            AsyncThrowingStream { stream in
                stream.yield(.response(HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: nil,
                    headerFields: ["Content-Range": "bytes 0-262143/300000", "Content-Length": "262144"])!))
                stream.yield(.bytes(Data(repeating: 1, count: 1024))); stream.finish()
            }
        })
        let id = try await cache.open(source)
        do { _ = try await cache.completeFile(id); XCTFail("Truncated response must not assemble") }
        catch { XCTAssertEqual((error as NSError).code, NSURLErrorNetworkConnectionLost) }
        let complete = await cache.cachedSource(key: source.key); XCTAssertNil(complete)
        await cache.release(id)
    }

    func testMalformedContentRangeFailsBeforeDeliveringBytes() async throws {
        let folder = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let cache = MusicAudioCache(directory: folder, transport: { request in
            AsyncThrowingStream { stream in
                stream.yield(.response(HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: nil,
                    headerFields: ["Content-Range": "bytes 42-100/300000", "Content-Length": "59"])!))
                stream.yield(.bytes(Data(repeating: 9, count: 59))); stream.finish()
            }
        })
        let id = try await cache.open(source)
        do { _ = try await cache.read(id, offset: 0, count: 1); XCTFail("Wrong byte origin must fail") }
        catch { XCTAssertEqual((error as NSError).code, NSURLErrorBadServerResponse) }
        await cache.release(id)
    }

    func testFirstSmallChunkIsReadableBeforeRangeCompletes() async throws {
        let folder = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let gate = MusicTestGate()
        let cache = MusicAudioCache(directory: folder, transport: { request in
            AsyncThrowingStream { continuation in
                let task = Task {
                    continuation.yield(.response(HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: nil,
                        headerFields: ["Content-Range": "bytes 0-262143/300000", "Content-Length": "262144"])!))
                    continuation.yield(.bytes(Data(repeating: 7, count: 1024)))
                    await gate.wait()
                    continuation.yield(.bytes(Data(repeating: 7, count: 261120)))
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        })
        let id = try await cache.open(source)
        let delivered = expectation(description: "First 1024 bytes available without a full cache block")
        let reader = Task {
            let data = try await cache.read(id, offset: 0, count: 1024)
            XCTAssertEqual(data, Data(repeating: 7, count: 1024)); delivered.fulfill()
        }
        await fulfillment(of: [delivered], timeout: 0.5)
        await gate.open()
        _ = try await reader.value
        await cache.release(id)
    }

    func testSlowDiskDoesNotBlockDeliveryOfReceivedAudio() async throws {
        let folder = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let gate = MusicTestGate(), writing = expectation(description: "disk write started")
        let bytes = Data(repeating: 5, count: 262144)
        let cache = MusicAudioCache(directory: folder, diskWrite: { data, url in
            writing.fulfill(); await gate.wait(); try data.write(to: url)
        }, transport: transport(bytes))
        let id = try await cache.open(source)
        let read = Task { try await cache.read(id, offset: 0, count: 100) }
        await fulfillment(of: [writing], timeout: 2)
        let delivered = expectation(description: "read while disk blocked")
        let reader = Task {
            let data = try await cache.read(id, offset: 200000, count: 100)
            XCTAssertEqual(data, Data(repeating: 5, count: 100)); delivered.fulfill()
        }
        await fulfillment(of: [delivered], timeout: 0.5)
        await gate.open(); _ = try await reader.value; _ = try await read.value
        await cache.release(id)
    }

    func testFLACHeaderOverridesMPEGResponseAndCompleteExtension() async throws {
        let folder = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let bytes = Data("fLaC".utf8) + Data(repeating: 0, count: 400000)
        let cache = MusicAudioCache(directory: folder, transport: transport(bytes))
        let id = try await cache.open(source)
        let info = try await cache.info(id)
        XCTAssertEqual(info.mime, "audio/flac")
        let file = try await cache.completeFile(id)
        XCTAssertEqual(file.pathExtension, "flac")
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        await cache.release(id)
    }

    func testConcurrentOverlappingReadsUseOneRangeRequestAndSurviveRestart() async throws {
        let folder = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let bytes = Data((0..<700_000).map { UInt8($0 % 251) }), counter = MusicTestCounter()
        let cache = MusicAudioCache(directory: folder, transport: transport(bytes, counter: counter))
        let id = try await cache.open(source)
        async let a = cache.read(id, offset: 100, count: 1000)
        async let b = cache.read(id, offset: 500, count: 300)
        let results = try await (a, b)
        XCTAssertEqual(results.0, bytes.subdata(in: 100..<1100)); XCTAssertEqual(results.1, bytes.subdata(in: 500..<800))
        let count = await counter.count; XCTAssertEqual(count, 1)
        let complete = try await cache.completeFile(id)
        XCTAssertEqual(try Data(contentsOf: complete), bytes)
        await cache.release(id)
        let restored = MusicAudioCache(directory: folder, transport: { _ in
            AsyncThrowingStream { $0.finish(throwing: URLError(.notConnectedToInternet)) }
        })
        let local = await restored.cachedSource(key: source.key)
        XCTAssertNotNil(local)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(local?.0)), bytes)
    }

    func testIgnoredRangeStartsBeforeWholeResponseAndDoesNotRedownload() async throws {
        let folder = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let bytes = Data(repeating: 27, count: 800_000), gate = MusicTestGate(), counter = MusicTestCounter()
        let cache = MusicAudioCache(directory: folder, transport: transport(bytes, ranges: false, counter: counter, gate: gate))
        let id = try await cache.open(source)
        let first = try await cache.read(id, offset: 0, count: 4096)
        XCTAssertEqual(first.count, 4096)
        let partial = await cache.statistics(); XCTAssertLessThan(partial.networkBytes, Int64(bytes.count))
        await gate.open()
        let completed = try await cache.completeFile(id)
        XCTAssertEqual(try Data(contentsOf: completed), bytes)
        let requests = await counter.count; XCTAssertEqual(requests, 1)
        await cache.release(id)
    }

    func testChangedURLWithoutValidatorNeverMixesPartialBytes() async throws {
        let folder = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let cache = MusicAudioCache(directory: folder, transport: transport(Data(repeating: 1, count: 500_000), validator: nil))
        let id = try await cache.open(source)
        _ = try await cache.read(id, offset: 0, count: 100)
        await cache.release(id)
        let restored = MusicAudioCache(directory: folder, transport: transport(Data(repeating: 2, count: 500_000), validator: nil))
        let newID = try await restored.open(.init(key: source.key, url: URL(string: "https://audio.example/refreshed.mp3")!, quality: source.quality))
        let data = try await restored.read(newID, offset: 0, count: 100)
        XCTAssertEqual(data, Data(repeating: 2, count: 100))
        await restored.release(newID)
    }

    func testClearKeepsLeasedPlaybackAndRemovesAfterRelease() async throws {
        let folder = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let cache = MusicAudioCache(directory: folder, transport: transport(Data(repeating: 4, count: 300_000)))
        let id = try await cache.open(source)
        _ = try await cache.completeFile(id)
        await cache.clear()
        let pending = await cache.usage(); XCTAssertTrue(pending.pendingRemoval)
        let bytes = try await cache.read(id, offset: 42, count: 20); XCTAssertEqual(bytes.count, 20)
        await cache.release(id)
        let cleared = await cache.usage(); XCTAssertFalse(cleared.pendingRemoval); XCTAssertLessThan(cleared.bytes, 4096)
        let missing = await cache.cachedSource(key: source.key); XCTAssertNil(missing)
    }

    func testCancellationUnblocksWaitingRead() async throws {
        let folder = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let cache = MusicAudioCache(directory: folder, transport: { _ in AsyncThrowingStream { _ in } })
        let id = try await cache.open(source)
        let task = Task { try await cache.read(id, offset: 0, count: 100) }
        await Task.yield(); task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled read must finish") } catch is CancellationError {} catch { XCTFail("\(error)") }
        await cache.release(id)
    }

    func testDirectSeekRejectsMissingOrContradictoryVBRIndex() {
        var bytes = Data(repeating: 0, count: 256)
        bytes.replaceSubrange(0..<4, with: [0xff, 0xfb, 0x90, 0])
        bytes.replaceSubrange(36..<40, with: Data("Xing".utf8))
        bytes[43] = 7; bytes[47] = 100
        bytes[48] = 0; bytes[49] = 0; bytes[50] = 0x27; bytes[51] = 0x10
        for index in 0..<100 { bytes[52 + index] = UInt8(index * 255 / 100) }
        XCTAssertFalse(AudioSeekIndex.supportsDirectSeek(header: bytes, fileLength: 10_000))
        XCTAssertFalse(AudioSeekIndex.supportsDirectSeek(header: bytes, fileLength: 30_000))
        bytes[43] = 3
        XCTAssertFalse(AudioSeekIndex.supportsDirectSeek(header: bytes, fileLength: 10_000))
        bytes[43] = 7; bytes[100] = 0
        XCTAssertFalse(AudioSeekIndex.supportsDirectSeek(header: bytes, fileLength: 10_000))
    }

    func testAccountAndEffectiveQualityAreIsolatedAndQuotaEvictsIdleFiles() async throws {
        let folder = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let bytes = Data(repeating: 3, count: 2_500_000)
        let cache = MusicAudioCache(directory: folder, capacity: 12 * 1024 * 1024, transport: transport(bytes))
        let first = try await cache.open(source)
        _ = try await cache.completeFile(first); await cache.release(first)
        let other = MusicAudioCache.Source(key: "other|song|high", url: source.url, quality: "lossless")
        let second = try await cache.open(other)
        _ = try await cache.completeFile(second); await cache.release(second)
        await cache.configure(capacity: 3 * 1024 * 1024, prefetchAllowed: false)
        let firstURL = await cache.cachedSource(key: source.key), secondURL = await cache.cachedSource(key: other.key)
        XCTAssertNil(firstURL); XCTAssertNotNil(secondURL)
        let usage = await cache.usage(); XCTAssertLessThanOrEqual(usage.bytes, 3 * 1024 * 1024)
    }

    func testDiskUnavailableStillServesPlaybackData() async throws {
        let folder = temporaryDirectory(); try Data([1]).write(to: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = MusicAudioCache(directory: folder, transport: transport(Data(repeating: 9, count: 400_000)))
        let id = try await cache.open(source)
        let bytes = try await cache.read(id, offset: 100, count: 100)
        XCTAssertEqual(bytes, Data(repeating: 9, count: 100))
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await cache.usage().writeDisabled), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let usage = await cache.usage(); XCTAssertTrue(usage.writeDisabled)
        await cache.release(id)
    }

    func testConcurrentFullPreparationUsesOneAssemblyAndOneDownloadPerBlock() async throws {
        let folder = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let data = Data(repeating: 7, count: 700_000), counter = MusicTestCounter()
        let cache = MusicAudioCache(directory: folder, transport: transport(data, counter: counter))
        let id = try await cache.open(source)
        await cache.configure(capacity: 20 * 1024 * 1024, prefetchAllowed: true)
        async let background = cache.completeFile(id, speculative: true)
        async let foreground = cache.completeFile(id)
        let result = try await (background, foreground)
        XCTAssertEqual(result.0, result.1)
        XCTAssertEqual(try Data(contentsOf: result.0), data)
        let count = await counter.count; XCTAssertEqual(count, 3)
        let used = await cache.usage(); XCTAssertLessThan(used.bytes, Int64(data.count + 4096))
        await cache.release(id)
    }

    func testOutOfBoundsRangeLearnsEOFWithoutRetryLoop() async throws {
        let folder = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let counter = MusicTestCounter()
        let cache = MusicAudioCache(directory: folder, transport: transport(Data(repeating: 1, count: 300_000), counter: counter))
        let id = try await cache.open(source)
        let bytes = try await cache.read(id, offset: 900_000, count: 100)
        XCTAssertTrue(bytes.isEmpty)
        let count = await counter.count; XCTAssertEqual(count, 1)
        await cache.release(id)
    }

    func testDisabledPrefetchDoesNotStartNetworkRequest() async throws {
        let folder = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let counter = MusicTestCounter()
        let cache = MusicAudioCache(directory: folder, transport: transport(Data(repeating: 1, count: 300_000), counter: counter))
        let id = try await cache.open(source)
        do { try await cache.prefetch(id); XCTFail("Prefetch is disabled by default") } catch is CancellationError {}
        do { _ = try await cache.completeFile(id, speculative: true); XCTFail("Background completion is also disabled") } catch is CancellationError {}
        let count = await counter.count; XCTAssertEqual(count, 0)
        let current = try await cache.read(id, offset: 0, count: 100); XCTAssertEqual(current.count, 100)
        await cache.release(id)
    }

    @MainActor func testSettingsDefaultsAndNetworkPolicies() async throws {
        let folder = temporaryDirectory(), suite = UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { try? FileManager.default.removeItem(at: folder); preferences.removePersistentDomain(forName: suite) }
        let cache = MusicAudioCache(directory: folder)
        let settings = MusicCacheSettings(cache: cache, preferences: preferences, monitorsNetwork: false)
        XCTAssertEqual(settings.capacityMB, 1024); XCTAssertEqual(settings.policy, .wifi)
        settings.setNetwork(connected: true, wifi: false, constrained: false); XCTAssertFalse(settings.permitsPrefetch)
        settings.setNetwork(connected: true, wifi: true, constrained: false); XCTAssertTrue(settings.permitsPrefetch)
        settings.policy = .all
        settings.setNetwork(connected: true, wifi: false, constrained: false); XCTAssertTrue(settings.permitsPrefetch)
        settings.setNetwork(connected: true, wifi: true, constrained: true); XCTAssertFalse(settings.permitsPrefetch)
        settings.capacityMB = 2048; settings.policy = .off
        let restored = MusicCacheSettings(cache: cache, preferences: preferences, monitorsNetwork: false)
        XCTAssertEqual(restored.capacityMB, 2048); XCTAssertEqual(restored.policy, .off)
    }
}
