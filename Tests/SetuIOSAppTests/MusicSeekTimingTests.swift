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
        XCTAssertFalse(controller.isBuffering)
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

    private func waitForSeek(_ controller: MusicPlaybackController) async {
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { !controller.isSeeking }
        }, object: nil)
        await fulfillment(of: [completed], timeout: 5)
        XCTAssertNil(controller.playbackError)
    }

    private func assertRequestedSound(in asset: AVAsset, file: StaticString = #filePath, line: UInt = #line) async throws {
        let precise = try await asset.load(.providesPreciseDurationAndTiming)
        let duration = try await asset.load(.duration).seconds
        XCTAssertTrue(precise, file: file, line: line)
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
