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

    func testDirectPlaybackDecodesTheRequestedSound() async throws {
        let controller = MusicPlaybackController(persistsPlayback: false)
        defer { controller.stop() }
        controller.play(url: try fixtureURL(), track: try playbackTracks()[0])
        controller.pause()
        try await assertRequestedSound(in: XCTUnwrap(controller.player?.currentItem).asset)
    }

    func testPreparedNextDecodesTheRequestedSound() async throws {
        let url = try fixtureURL()
        let resolver = PlaybackURLResolver { ids, quality in
            try playbackResponse(ids: ids, quality: quality, url: url)
        }
        let preparer = NextItemPreparer()
        await preparer.prepare(trackID: 1, quality: .exhigh, resolver: resolver)
        try await assertRequestedSound(in: XCTUnwrap(preparer.prepared).item.asset)
    }

    func testQualityReplacementDecodesTheRequestedSound() async throws {
        let url = try fixtureURL()
        let controller = MusicPlaybackController(persistsPlayback: false)
        defer { controller.stop() }
        controller.play(url: url, track: try playbackTracks()[0])
        controller.pause()
        controller.resolveQualityURL = { _, _ in .success(url, notice: nil) }
        let changed = await controller.setAudioQuality(.higher)
        XCTAssertTrue(changed)
        try await assertRequestedSound(in: XCTUnwrap(controller.player?.currentItem).asset)
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
