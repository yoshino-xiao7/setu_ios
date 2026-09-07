import AVFoundation
import MobileVLCKit
import XCTest
@testable import SetuIOSApp

@MainActor
final class VLCIndependentPlaybackTests: XCTestCase {
    func testVLCDecodesTheRequestedSoundWithMisleadingXingIndex() async throws {
        let bundle = Bundle(for: Self.self)
        var bytes = try Data(contentsOf: XCTUnwrap(bundle.url(forResource: "seek-markers-indexed", withExtension: "mp3")))
        let xing = try XCTUnwrap(bytes.range(of: Data("Xing".utf8))).lowerBound
        for index in 0..<100 { bytes[xing + 16 + index] = UInt8(min(255, index * 4)) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("vlc-seek-\(UUID()).mp3")
        try bytes.write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        let probe = VLCAudioProbe(); defer { probe.stop() }
        probe.player.media = VLCMedia(url: file); probe.player.play()
        try await wait { probe.player.isSeekable && probe.player.time.intValue > 100 }
        probe.beginCapture()
        probe.player.time = VLCTime(int: 19000)
        try await wait { probe.capturedPCM().count >= 16384 }
        probe.player.pause()
        let data = probe.capturedPCM()
        let samples: [Int16] = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self).prefix(8192)) }
        let powers = (0..<8).map { group -> Double in
            let omega = 2 * Double.pi * Double(200 + 40 * group) / 44100
            var real = 0.0, imaginary = 0.0
            for (i, sample) in samples.enumerated() {
                real += Double(sample) * cos(omega * Double(i))
                imaginary += Double(sample) * sin(omega * Double(i))
            }
            return real * real + imaginary * imaginary
        }
        XCTAssertEqual(powers.indices.max(by: { powers[$0] < powers[$1] }), 3,
                       "At 19s the actual decoded sound must be marker 3, regardless of the player's reported time")
    }

    func testVLCChirpSeekSoundIsWithin200Milliseconds() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "seek-chirp-vbr", withExtension: "mp3"))
        let probe = VLCAudioProbe(); defer { probe.stop() }
        probe.player.media = VLCMedia(url: url); probe.player.play()
        try await wait { probe.player.isSeekable && probe.player.time.intValue > 100 }
        probe.beginCapture(); probe.player.time = VLCTime(int: 19000)
        try await wait { probe.capturedPCM().count >= 16384 }
        probe.player.pause()
        let pcm = probe.capturedPCM().withUnsafeBytes { Array($0.bindMemory(to: Int16.self).prefix(8192)) }
        let crossings = zip(pcm, pcm.dropFirst()).filter { $0 <= 0 && $1 > 0 }.count
        let windowSeconds = Double(pcm.count - 1) / 44100
        let frequency = Double(crossings) / windowSeconds
        let decodedStart = (frequency - 500) / 250 - windowSeconds / 2
        XCTAssertEqual(decodedStart, 19, accuracy: 0.2, "Decoded chirp independently measures seek position; player timestamps are not proof")
    }

    func testVLCChirpSeekWithAvformatDemuxIsWithin200Milliseconds() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "seek-chirp-vbr", withExtension: "mp3"))
        let probe = VLCAudioProbe(); defer { probe.stop() }
        probe.player.media = VLCMedia(url: url)
        probe.player.media?.addOption(":demux=avformat")
        probe.player.media?.addOption(":input-fast-seek=0")
        probe.player.play()
        try await wait { probe.player.isSeekable && probe.player.time.intValue > 100 }
        probe.beginCapture(); probe.player.time = VLCTime(int: 19000)
        try await wait { probe.capturedPCM().count >= 16384 }
        probe.player.pause()
        let pcm = probe.capturedPCM().withUnsafeBytes { Array($0.bindMemory(to: Int16.self).prefix(8192)) }
        let crossings = zip(pcm, pcm.dropFirst()).filter { $0 <= 0 && $1 > 0 }.count
        let windowSeconds = Double(pcm.count - 1) / 44100
        let frequency = Double(crossings) / windowSeconds
        let decodedStart = (frequency - 500) / 250 - windowSeconds / 2
        XCTAssertEqual(decodedStart, 19, accuracy: 0.2, "Decoded chirp independently measures seek position; player timestamps are not proof")
    }

    func testChirpMeasurementIsCalibratedAgainstSequentialDecode() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "seek-chirp-vbr", withExtension: "mp3"))
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1, AVSampleRateKey: 44100])
        reader.add(output); XCTAssertTrue(reader.startReading()); defer { reader.cancelReading() }
        var frame = 0, pcm: [Int16] = []
        while pcm.count < 8192, let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            let count = CMBlockBufferGetDataLength(block) / 2
            var values = [Int16](repeating: 0, count: count)
            values.withUnsafeMutableBytes { pointer in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * 2, destination: pointer.baseAddress!)
            }
            for value in values {
                if frame >= 19 * 44100 && pcm.count < 8192 { pcm.append(value) }
                frame += 1
            }
        }
        XCTAssertEqual(pcm.count, 8192)
        let crossings = zip(pcm, pcm.dropFirst()).filter { $0 <= 0 && $1 > 0 }.count
        let window = Double(pcm.count - 1) / 44100
        XCTAssertEqual((Double(crossings) / window - 500) / 250 - window / 2, 19, accuracy: 0.2)
    }

    func testVLCAdapterReplacesMediaAndSeeksWithoutOldCallbacks() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "seek-markers-indexed", withExtension: "mp3"))
        let engine = VLCPlaybackEngine(); defer { engine.stop() }
        let old = UUID(), current = UUID()
        engine.load(url: url, mediaID: old); engine.play()
        engine.load(url: url, mediaID: current); engine.play()
        try await wait { engine.snapshot?.seekable == true }
        do { try await engine.seek(toMilliseconds: 19000) }
        catch { XCTFail("Seek failed: \(error), snapshot: \(String(describing: engine.snapshot))"); return }
        XCTAssertEqual(engine.snapshot?.mediaID, current)
        XCTAssertGreaterThanOrEqual(engine.snapshot?.positionMilliseconds ?? 0, 18800)
        XCTAssertLessThanOrEqual(engine.snapshot?.positionMilliseconds ?? 0, 20000)
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(12))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw NSError(domain: "VLCProbeTimeout", code: 1) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
