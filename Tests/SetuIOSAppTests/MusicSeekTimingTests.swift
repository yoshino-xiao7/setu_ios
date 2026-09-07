import AVFoundation
import XCTest
@testable import SetuIOSApp
@testable import SetuIOSCore

@MainActor
final class MusicSeekTimingTests: XCTestCase {
    private func fixtureURL() throws -> URL {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        return try XCTUnwrap(bundle.url(forResource: "seek-markers-vbr", withExtension: "mp3"))
    }

    func testCompletedSeekDecodesTheSelectedLyricTime() async throws {
        let controller = MusicPlaybackController(persistsPlayback: false)
        defer { controller.stop() }
        controller.play(url: try fixtureURL(), track: try playbackTracks()[0])
        controller.pause()
        controller.seek(to: 19)
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { !controller.isSeeking }
        }, object: nil)
        await fulfillment(of: [completed], timeout: 5)
        XCTAssertNil(controller.playbackError)
        try await assertRequestedSound(in: XCTUnwrap(controller.player?.currentItem).asset)
    }

    func testSlowCacheDoesNotBlockPlaybackAndCompletedCacheSeeksAccurately() async throws {
        let gate = MusicTestGate(), downloads = MusicTestCounter()
        let started = expectation(description: "background cache started")
        let cache = PreciseSeekAudioCache { source, destination in
            _ = await downloads.next()
            started.fulfill()
            await gate.wait()
            try Task.checkCancellation()
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        }
        let controller = MusicPlaybackController(persistsPlayback: false, preciseSeekCache: cache)
        defer { controller.stop() }
        controller.play(url: try fixtureURL(), track: try playbackTracks()[0])
        let engine = try XCTUnwrap(controller.player)
        let original = try XCTUnwrap(engine.currentItem)
        await fulfillment(of: [started], timeout: 5)
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { engine.currentTime().seconds > 0.1 }
        }, object: nil)
        await fulfillment(of: [playing], timeout: 5)
        XCTAssertFalse(controller.isBuffering, "Playback must start before the full cache arrives")
        controller.seek(to: 19)
        XCTAssertTrue(controller.isSeeking)
        XCTAssertTrue(engine.currentItem === original)
        XCTAssertLessThan(controller.currentTimeSeconds, 5)
        await gate.open()
        await waitForSeek(controller)
        XCTAssertFalse(engine.currentItem === original)
        XCTAssertTrue(controller.isPlaying)
        try await assertRequestedSound(in: XCTUnwrap(engine.currentItem).asset)
        let localItem = engine.currentItem
        controller.seek(to: 5)
        await waitForSeek(controller)
        XCTAssertTrue(engine.currentItem === localItem)
        let count = await downloads.count
        XCTAssertEqual(count, 1, "Repeated lyric taps reuse the same complete audio")
    }

    func testDownloadFailureKeepsOriginalItemAndPosition() async throws {
        let cache = PreciseSeekAudioCache { _, _ in throw URLError(.notConnectedToInternet) }
        let controller = MusicPlaybackController(persistsPlayback: false, preciseSeekCache: cache)
        defer { controller.stop() }
        controller.play(url: try fixtureURL(), track: try playbackTracks()[0])
        controller.pause()
        let original = controller.player?.currentItem
        controller.seek(to: 19)
        await waitForSeek(controller)
        XCTAssertTrue(controller.player?.currentItem === original)
        XCTAssertEqual(controller.currentTimeSeconds, 0)
        XCTAssertFalse(controller.isBuffering)
        if case .warning = controller.feedback {} else { XCTFail("Failed preparation must explain why the seek did not happen") }
    }

    func testCacheTimeoutResumesOriginalAudio() async throws {
        let gate = MusicTestGate()
        let started = expectation(description: "cache waiting")
        let cache = PreciseSeekAudioCache { source, destination in
            started.fulfill()
            await gate.wait()
            try Task.checkCancellation()
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        }
        let controller = MusicPlaybackController(persistsPlayback: false, preciseSeekCache: cache,
                                                 seekPreparationTimeout: .milliseconds(100))
        defer { controller.stop() }
        controller.play(url: try fixtureURL(), track: try playbackTracks()[0])
        let original = controller.player?.currentItem
        await fulfillment(of: [started], timeout: 5)
        controller.seek(to: 19)
        await waitForSeek(controller)
        XCTAssertTrue(controller.player?.currentItem === original)
        XCTAssertTrue(controller.isPlaying)
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { controller.player?.timeControlStatus == .playing && !controller.isBuffering }
        }, object: nil)
        await fulfillment(of: [resumed], timeout: 5)
        XCTAssertLessThan(controller.currentTimeSeconds, 5)
        await gate.open()
    }

    func testStopCancelsPendingCacheDownload() async throws {
        let started = expectation(description: "download started")
        let cancelled = expectation(description: "download cancelled")
        let cache = PreciseSeekAudioCache { _, _ in
            started.fulfill()
            do { try await Task.sleep(for: .seconds(60)); throw CancellationError() }
            catch { cancelled.fulfill(); throw error }
        }
        let controller = MusicPlaybackController(persistsPlayback: false, preciseSeekCache: cache)
        controller.play(url: try fixtureURL(), track: try playbackTracks()[0])
        await fulfillment(of: [started], timeout: 5)
        controller.seek(to: 19)
        controller.stop()
        await fulfillment(of: [cancelled], timeout: 3)
        XCTAssertFalse(controller.isSeeking)
        XCTAssertNil(controller.player?.currentItem)
    }

    func testRelaunchRestoresActualAudioPositionFromSnapshot() async throws {
        let suite = "restore-seek-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let url = try fixtureURL(), track = try playbackTracks()[0]
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: storage) }
        let before = MusicPlaybackController(preferences: preferences,
            preciseSeekCache: PreciseSeekAudioCache(storageDirectory: storage))
        before.setSnapshotUserID(42)
        before.play(url: url, track: track)
        before.pause()
        before.seek(to: 19)
        await waitForSeek(before)
        before.savePlaybackSnapshot(userID: 42)
        await before.waitForSnapshotWrites()
        before.resetForUserChange()

        let restored = MusicPlaybackController(preferences: preferences,
            preciseSeekCache: PreciseSeekAudioCache(storageDirectory: storage) { _, _ in
                XCTFail("Completed audio must survive controller recreation without another download")
                throw URLError(.notConnectedToInternet)
            })
        defer { restored.stop() }
        restored.setSnapshotUserID(42)
        restored.restorePlaybackSnapshotIfNeeded(for: 42)
        XCTAssertEqual(restored.currentTimeSeconds, 19, accuracy: 0.1)
        restored.urlResolver = PlaybackURLResolver { ids, quality in
            try playbackResponse(ids: ids, quality: quality, url: url)
        }
        restored.resume()
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { restored.player?.timeControlStatus == .playing && !restored.isSeeking }
        }, object: nil)
        await fulfillment(of: [playing], timeout: 8)
        restored.pause()
        try await assertRequestedSound(in: XCTUnwrap(restored.player?.currentItem).asset)
        XCTAssertEqual(try XCTUnwrap(restored.player).currentTime().seconds, 19, accuracy: 1)
    }

    func testRelaunchUsesCompletedAudioWithoutResolvingOrDownloadingAgain() async throws {
        let suite = "restore-seek-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let url = try fixtureURL(), track = try playbackTracks()[0]
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: storage) }
        let before = MusicPlaybackController(preferences: preferences,
            preciseSeekCache: PreciseSeekAudioCache(storageDirectory: storage))
        before.setSnapshotUserID(42)
        before.play(url: url, track: track)
        before.pause()
        before.seek(to: 19)
        await waitForSeek(before)
        before.savePlaybackSnapshot(userID: 42)
        await before.waitForSnapshotWrites()
        before.resetForUserChange()

        let restored = MusicPlaybackController(preferences: preferences,
            preciseSeekCache: PreciseSeekAudioCache(storageDirectory: storage) { _, _ in
                XCTFail("Completed audio must survive controller recreation without another download")
                throw URLError(.notConnectedToInternet)
            })
        defer { restored.stop() }
        restored.setSnapshotUserID(42)
        restored.restorePlaybackSnapshotIfNeeded(for: 42)
        XCTAssertEqual(restored.currentTimeSeconds, 19, accuracy: 0.1)
        restored.urlResolver = PlaybackURLResolver { ids, quality in
            throw URLError(.notConnectedToInternet)
        }
        restored.resume()
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { restored.player?.timeControlStatus == .playing && !restored.isSeeking }
        }, object: nil)
        await fulfillment(of: [playing], timeout: 3)
        restored.pause()
        try await assertRequestedSound(in: XCTUnwrap(restored.player?.currentItem).asset)
        XCTAssertEqual(try XCTUnwrap(restored.player).currentTime().seconds, 19, accuracy: 1)
    }

    func testFailedRestoreKeepsSavedPositionAndCanRetry() async throws {
        let suite = "restore-retry-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let url = try fixtureURL(), track = try playbackTracks()[0]
        let snapshot = PlaybackSnapshotStore.Snapshot(
            userID: 42, track: track, context: .unknown(reason: .legacySnapshot, label: nil),
            queueTracks: [track], currentQueueIndex: 0, currentTimeSeconds: 19,
            playMode: .sequence, updatedAt: Date())
        preferences.set(try JSONEncoder().encode(snapshot), forKey: PlaybackSnapshotStore.snapshotKey(userID: 42))
        let attempts = MusicTestCounter()
        let cache = PreciseSeekAudioCache { source, destination in
            if await attempts.next() == 1 { throw URLError(.notConnectedToInternet) }
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        }
        let controller = MusicPlaybackController(preferences: preferences, preciseSeekCache: cache)
        defer { controller.stop() }
        controller.setSnapshotUserID(42)
        controller.restorePlaybackSnapshotIfNeeded(for: 42)
        controller.urlResolver = PlaybackURLResolver { ids, quality in
            try playbackResponse(ids: ids, quality: quality, url: url)
        }
        controller.resume()
        let failed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                if case .warning = controller.feedback { return !controller.isSeeking }
                return false
            }
        }, object: nil)
        await fulfillment(of: [failed], timeout: 5)
        XCTAssertNil(controller.player?.currentItem)
        XCTAssertFalse(controller.isPlaying)
        XCTAssertFalse(controller.isBuffering)
        XCTAssertEqual(controller.currentTimeSeconds, 19, accuracy: 0.1)
        await controller.waitForSnapshotWrites()
        XCTAssertEqual(PlaybackSnapshotStore(enabled: true, preferences: preferences).restore(for: 42)?.currentTimeSeconds, 19)
        controller.resume()
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { controller.player?.timeControlStatus == .playing && !controller.isSeeking }
        }, object: nil)
        await fulfillment(of: [playing], timeout: 8)
        controller.pause()
        XCTAssertEqual(try XCTUnwrap(controller.player).currentTime().seconds, 19, accuracy: 1)
        try await assertRequestedSound(in: XCTUnwrap(controller.player?.currentItem).asset)
    }

    func testPersistentCacheSeparatesSourcesAndEvictsOldAudio() async throws {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage) }
        let cache = PreciseSeekAudioCache(storageDirectory: storage)
        let url = try fixtureURL()
        _ = try await cache.prepare(source: url, identity: "user1|song1|standard")
        XCTAssertNotNil(cache.cachedSource(identity: "user1|song1|standard"))
        XCTAssertNil(cache.cachedSource(identity: "user2|song1|standard"))
        XCTAssertNil(cache.cachedSource(identity: "user1|song1|lossless"))
        _ = try await cache.prepare(source: url, identity: "user1|song2|standard")
        _ = try await cache.prepare(source: url, identity: "user1|song3|standard")
        XCTAssertNil(cache.cachedSource(identity: "user1|song1|standard"))
        let stored = try XCTUnwrap(cache.cachedSource(identity: "user1|song3|standard"))
        cache.invalidate()
        try Data("broken audio".utf8).write(to: stored)
        do {
            _ = try await cache.prepare(source: url, identity: "user1|song3|standard")
            XCTFail("Corrupt files must not remain available for restoration")
        } catch {}
        XCTAssertNil(cache.cachedSource(identity: "user1|song3|standard"))
        _ = try await cache.prepare(source: url, identity: "user1|song3|standard")
        XCTAssertNotNil(cache.cachedSource(identity: "user1|song3|standard"))
    }

    func testUnavailablePersistentStorageDoesNotPreventPrecisePlayback() async throws {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: storage)
        defer { try? FileManager.default.removeItem(at: storage) }
        let cache = PreciseSeekAudioCache(storageDirectory: storage)
        let asset = try await cache.prepare(source: fixtureURL(), identity: "user|song|quality")
        try await assertRequestedSound(in: asset)
    }

    func testSeekPreparationKeepsAudioPlayingAndCancellationRejectsLateCompletion() async throws {
        let gate = MusicTestGate()
        let cache = PreciseSeekAudioCache { source, destination in
            await gate.wait()
            try Task.checkCancellation()
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        }
        let controller = MusicPlaybackController(persistsPlayback: false, preciseSeekCache: cache)
        defer { controller.stop() }
        controller.play(url: try fixtureURL(), track: try playbackTracks()[0])
        let started = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { (controller.player?.currentTime().seconds ?? 0) > 0.1 }
        }, object: nil)
        await fulfillment(of: [started], timeout: 5)
        let original = controller.player?.currentItem
        controller.seek(to: 19)
        XCTAssertTrue(controller.isPreparingSeek)
        let before = controller.player?.currentTime().seconds ?? 0
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertGreaterThan(controller.player?.currentTime().seconds ?? 0, before)
        controller.cancelPendingSeek()
        XCTAssertFalse(controller.isSeeking)
        XCTAssertTrue(controller.isPlaying)
        await gate.open()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(controller.player?.currentItem === original)
        XCTAssertLessThan(controller.currentTimeSeconds, 5)
    }

    func testSharedLoaderReusesStreamBytesForExactSeekAndOfflineRestart() async throws {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "shared-audio-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { try? FileManager.default.removeItem(at: storage); preferences.removePersistentDomain(forName: suite) }
        let bytes = try Data(contentsOf: fixtureURL())
        let cache = MusicAudioCache(directory: storage, transport: { request in
            AsyncThrowingStream { continuation in
                let range = request.value(forHTTPHeaderField: "Range")!.dropFirst(6).split(separator: "-")
                let start = Int(range[0])!, end = min(bytes.count, Int(range[1])! + 1)
                let response = HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: nil, headerFields: [
                    "Content-Type": "audio/mpeg", "Content-Length": "\(end - start)",
                    "Content-Range": "bytes \(start)-\(end - 1)/\(bytes.count)", "ETag": "\"sound-v1\""])!
                continuation.yield(.response(response))
                continuation.yield(.bytes(bytes.subdata(in: start..<end))); continuation.finish()
            }
        })
        let controller = MusicPlaybackController(preferences: preferences, audioAssets: CachedAudioAssetFactory(cache: cache))
        controller.setSnapshotUserID(42)
        controller.play(url: URL(string: "https://audio.example/fixture.mp3")!, track: try playbackTracks()[0])
        let started = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { controller.player?.timeControlStatus == .playing }
        }, object: nil)
        await fulfillment(of: [started], timeout: 6)
        controller.pause(); controller.seek(to: 19)
        await waitForSeek(controller)
        if case .warning(let message) = controller.feedback { XCTFail(message) }
        try await assertRequestedSound(in: XCTUnwrap(controller.player?.currentItem).asset)
        let metrics = await cache.statistics()
        XCTAssertEqual(metrics.networkBytes, Int64(bytes.count), "Playback and precise seeking must share downloaded bytes")
        controller.savePlaybackSnapshot(userID: 42); await controller.waitForSnapshotWrites(); controller.resetForUserChange()
        let offline = MusicAudioCache(directory: storage, transport: { _ in
            AsyncThrowingStream { $0.finish(throwing: URLError(.notConnectedToInternet)) }
        })
        let restored = MusicPlaybackController(preferences: preferences, audioAssets: CachedAudioAssetFactory(cache: offline))
        defer { restored.stop() }
        restored.setSnapshotUserID(42); restored.restorePlaybackSnapshotIfNeeded(for: 42)
        // No URL resolver: the fully cached song must still resume.
        restored.resume()
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { restored.player?.timeControlStatus == .playing && !restored.isSeeking }
        }, object: nil)
        await fulfillment(of: [resumed], timeout: 3)
        restored.pause()
        XCTAssertEqual(restored.player?.currentTime().seconds ?? 0, 19, accuracy: 1)
        try await assertRequestedSound(in: XCTUnwrap(restored.player?.currentItem).asset)
    }

    func testIndexedMP3SeeksUsingSharedStreamWithoutCompleteFile() async throws {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let bytes = try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "seek-markers-indexed", withExtension: "mp3")))
        XCTAssertTrue(AudioSeekIndex.supportsDirectSeek(header: bytes, fileLength: Int64(bytes.count)))
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage) }
        let cache = MusicAudioCache(directory: storage, transport: { request in
            AsyncThrowingStream { continuation in
                let range = request.value(forHTTPHeaderField: "Range")!.dropFirst(6).split(separator: "-")
                let start = Int(range[0])!, end = min(bytes.count, Int(range[1])! + 1)
                continuation.yield(.response(HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: nil, headerFields: [
                    "Content-Type": "audio/mpeg", "Content-Length": "\(end - start)", "Content-Range": "bytes \(start)-\(end - 1)/\(bytes.count)"])!))
                continuation.yield(.bytes(bytes.subdata(in: start..<end))); continuation.finish()
            }
        })
        let controller = MusicPlaybackController(persistsPlayback: false, audioAssets: CachedAudioAssetFactory(cache: cache))
        defer { controller.stop() }
        controller.play(url: URL(string: "https://audio.example/indexed.mp3")!, track: try playbackTracks()[0])
        let started = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { controller.player?.timeControlStatus == .playing }
        }, object: nil)
        await fulfillment(of: [started], timeout: 6)
        controller.pause()
        let original = controller.player?.currentItem
        controller.seek(to: 19); await waitForSeek(controller)
        XCTAssertTrue(controller.player?.currentItem === original)
        try await assertRequestedSound(in: XCTUnwrap(controller.player?.currentItem).asset, requiresPreciseFlag: false)
        let files = try FileManager.default.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.contains(where: { $0.pathExtension == "mp3" }), "Direct seeking must not assemble a complete local file")
    }

    private func waitForSeek(_ controller: MusicPlaybackController) async {
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { !controller.isSeeking }
        }, object: nil)
        await fulfillment(of: [completed], timeout: 5)
        XCTAssertNil(controller.playbackError)
    }

    private func assertRequestedSound(in asset: AVAsset, requiresPreciseFlag: Bool = true, file: StaticString = #filePath, line: UInt = #line) async throws {
        let precise = try await asset.load(.providesPreciseDurationAndTiming)
        let duration = try await asset.load(.duration).seconds
        if requiresPreciseFlag { XCTAssertTrue(precise, file: file, line: line) }
        XCTAssertEqual(duration, 40, accuracy: 0.1, file: file, line: line)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1, AVSampleRateKey: 44_100
        ])
        reader.add(output)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: 19, preferredTimescale: 44_100),
                                       duration: CMTime(seconds: 1, preferredTimescale: 44_100))
        XCTAssertTrue(reader.startReading())
        defer { reader.cancelReading() }
        var samples = [Float]()
        while samples.count < 8192, let buffer = output.copyNextSampleBuffer(),
              let block = CMSampleBufferGetDataBuffer(buffer) {
            let length = CMBlockBufferGetDataLength(block)
            var values = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = values.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
            }
            XCTAssertEqual(status, noErr)
            samples.append(contentsOf: values)
        }
        XCTAssertGreaterThanOrEqual(samples.count, 8192)
        let count = min(samples.count, 8192)
        let marker = (0..<8).max { a, b in
            power(of: 200 + 40 * a, samples: samples, count: count) < power(of: 200 + 40 * b, samples: samples, count: count)
        }
        // The 15...20 s segment is 320 Hz. Approximate MP3 lookup instead decodes
        // the 30...35 s segment (440 Hz), even though its timestamps say 19 s.
        XCTAssertEqual(marker, 3, "Decoded audio must match the selected lyric time", file: file, line: line)
    }

    private func power(of frequency: Int, samples: [Float], count: Int) -> Double {
        var real = 0.0, imaginary = 0.0
        for index in 0..<count {
            let phase = 2 * Double.pi * Double(frequency * index) / 44_100
            real += Double(samples[index]) * cos(phase)
            imaginary += Double(samples[index]) * sin(phase)
        }
        return real * real + imaginary * imaginary
    }
}
