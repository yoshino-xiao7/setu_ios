import AVFoundation
import MediaToolbox
import MobileVLCKit
import XCTest
@testable import SetuIOSApp

@MainActor
final class VLCIndependentPlaybackTests: XCTestCase {
    func testAVDirectProbeReplacesMediaAndPublishesOnlyCurrentIdentity() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "seek-markers-indexed", withExtension: "mp3"))
        let engine = AVDirectProbeEngine()
        defer { engine.stop() }
        let first = UUID(), second = UUID()
        engine.load(url: url, mediaID: first); engine.play()
        engine.load(url: url, mediaID: second); engine.play()
        var received: [UUID] = []
        engine.onChange = { received.append($0.mediaID) }
        try await wait { engine.snapshot?.state == .playing }
        try await engine.seek(toMilliseconds: 19000)
        XCTAssertEqual(engine.snapshot?.mediaID, second)
        XCTAssertTrue(received.allSatisfy { $0 == second })
        XCTAssertGreaterThanOrEqual(engine.snapshot?.positionMilliseconds ?? 0, 18800)
        engine.stop()
        XCTAssertNil(engine.snapshot)
    }

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

    /// Input is an explicitly supplied real audio file, never a signed URL or account export.
    func testCaptureRealSourcePCMForIndependentAlignment() async throws {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let input = folder.appendingPathComponent("music-probe-input.audio")
        guard FileManager.default.fileExists(atPath: input.path) else { throw XCTSkip("Supply the selected real audio file to the test host Documents directory") }
        // Some AVAssetReader builds reject FLAC. An independently, sequentially
        // decoded WAV may supply the reference; the tested VLC input stays untouched.
        let wave = folder.appendingPathComponent("music-probe-reference.wav")
        let asset = AVURLAsset(url: FileManager.default.fileExists(atPath: wave.path) ? wave : input)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(audioTracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1, AVSampleRateKey: 44100])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? URLError(.cannotDecodeContentData) }
        let reference = folder.appendingPathComponent("music-probe-reference.pcm")
        FileManager.default.createFile(atPath: reference.path, contents: nil)
        let handle = try FileHandle(forWritingTo: reference); defer { try? handle.close(); reader.cancelReading() }
        var bytes = 0
        while let sample = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sample) {
            var data = Data(count: CMBlockBufferGetDataLength(block))
            let count = data.count
            let status = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count, destination: $0.baseAddress!) }
            XCTAssertEqual(status, kCMBlockBufferNoErr)
            try handle.write(contentsOf: data); bytes += count
        }
        XCTAssertEqual(reader.status, .completed)
        let duration = Double(bytes) / 88200
        XCTAssertGreaterThan(duration, 10)
        var results: [[String: String]] = []
        for fraction in [0.2, 0.5, 0.8] {
            let probe = VLCAudioProbe(); defer { probe.stop() }
            probe.player.media = VLCMedia(url: input); probe.player.play()
            try await wait { probe.player.isSeekable && probe.player.time.intValue > 100 }
            let target = Int32(duration * fraction * 1000)
            probe.beginCapture(); probe.player.time = VLCTime(int: target)
            try await wait { probe.capturedPCM().count >= 88200 }
            probe.player.pause()
            let name = "music-probe-seek-\(target).pcm"
            try probe.capturedPCM().prefix(88200).write(to: folder.appendingPathComponent(name))
            results.append(["targetMs": String(target), "file": name, "reportedMs": String(probe.player.time.intValue)])
        }
        let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: folder.appendingPathComponent("music-probe-pcm.json"))
    }

    /// Captures AVPlayer's decoded output, independently of its reported position.
    /// This is a decoder/seek gate, not a physical speaker synchronization claim.
    func testAVPlayerCapturesSeekPCMForIndependentAlignment() async throws {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let supplied = ProcessInfo.processInfo.environment["SETU_CONTINUITY_INPUT"].map { URL(fileURLWithPath: $0) }
            ?? folder.appendingPathComponent("av-continuity-input.audio")
        let input = FileManager.default.fileExists(atPath: supplied.path) ? supplied : try makeContinuityWave(in: folder)
        let asset = AVURLAsset(url: input)
        let duration: Double
        if let suppliedDuration = ProcessInfo.processInfo.environment["SETU_CONTINUITY_DURATION"].flatMap(Double.init) { duration = suppliedDuration }
        else { duration = try await asset.load(.duration).seconds }
        let track = MusicPlaybackTrack(id: 999, title: "Continuity fixture", artist: "", album: "", coverURLString: nil,
                                       durationMilliseconds: Int(duration * 1000), mvID: nil)
        let streaming = ProcessInfo.processInfo.environment["SETU_CONTINUITY_URL"].flatMap(URL.init(string:))
        let cacheFolder = FileManager.default.temporaryDirectory.appendingPathComponent("pcm-cache-\(UUID())")
        let assets = streaming == nil ? nil : CachedAudioAssetFactory(cache: MusicAudioCache(directory: cacheFolder, capacity: 256 * 1024 * 1024))
        let controller = MusicPlaybackController(persistsPlayback: false, audioAssets: assets)
        defer { controller.stop(); try? FileManager.default.removeItem(at: cacheFolder) }
        controller.play(url: streaming ?? input, track: track)
        controller.pause()
        var events: [[String: Any]] = []
        for target in [0.0, duration * 0.2, duration * 0.5, duration * 0.8] {
            controller.seek(to: target)
            try await wait { !controller.isSeeking }
            XCTAssertNil(controller.playbackError)
            let item = try XCTUnwrap(controller.player?.currentItem)
            let tracks = try await item.asset.loadTracks(withMediaType: .audio)
            let probe = AVDecodedOutputCapture()
            try probe.install(on: item, track: XCTUnwrap(tracks.first))
            controller.resume()
            try await wait { probe.sampleCount >= Int(probe.sampleRate * 2) }
            controller.pause()
            let captured = probe.snapshot()
            let filename = "av-continuity-\(Int(target * 1000)).f32"
            try captured.samples.withUnsafeBytes { Data($0) }.write(to: folder.appendingPathComponent(filename))
            events.append(["targetMs": target * 1000, "reportedMs": controller.currentTimeSeconds * 1000,
                           "firstFrameMediaMs": captured.start.isFinite ? (captured.start * 1000) as Any : NSNull(), "sampleRate": captured.rate,
                           "file": filename, "sampleFormat": "f32le"])
            item.audioMix = nil
            try JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys])
                .write(to: folder.appendingPathComponent("av-continuity-pcm.json"))
        }
    }

    private func makeContinuityWave(in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent("av-continuity-input.wav")
        let rate = 44100.0, frames = AVAudioFrameCount(40 * 44100)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try XCTUnwrap(buffer.floatChannelData?.pointee)
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            samples[i] = Float(0.4 * sin(2 * .pi * (500 * t + 125 * t * t)))
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(12))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw NSError(domain: "VLCProbeTimeout", code: 1) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}

private final class AVDecodedOutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var format = AudioStreamBasicDescription()
    private var samples: [Float] = []
    private var firstTime: Double = 0
    var sampleCount: Int { lock.withLock { samples.count } }
    var sampleRate: Double { lock.withLock { format.mSampleRate > 0 ? format.mSampleRate : 44100 } }
    func snapshot() -> (samples: [Float], start: Double, rate: Double) {
        lock.withLock { (samples, firstTime, format.mSampleRate) }
    }
    func install(on item: AVPlayerItem, track: AVAssetTrack) throws {
        var callbacks = MTAudioProcessingTapCallbacks(version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(self).toOpaque(), init: { _, info, storage in
                storage.pointee = info
            }, finalize: { tap in
                Unmanaged<AVDecodedOutputCapture>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            }, prepare: { tap, _, format in
                let capture = Unmanaged<AVDecodedOutputCapture>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                capture.lock.withLock { capture.format = format.pointee }
            }, unprepare: nil, process: { tap, count, _, buffers, countOut, flagsOut in
                var range = CMTimeRange.invalid
                let status = MTAudioProcessingTapGetSourceAudio(tap, count, buffers, flagsOut, &range, countOut)
                guard status == noErr else { countOut.pointee = 0; return }
                guard range.start.isValid, range.start.seconds.isFinite, countOut.pointee > 0 else { return }
                let capture = Unmanaged<AVDecodedOutputCapture>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                capture.append(buffers, count: countOut.pointee, time: range.start.seconds)
            })
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr, let tap else {
            Unmanaged<AVDecodedOutputCapture>.fromOpaque(callbacks.clientInfo!).release()
            throw NSError(domain: "AVOutputCapture", code: Int(status))
        }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix(); mix.inputParameters = [parameters]; item.audioMix = mix
    }
    private func append(_ list: UnsafeMutablePointer<AudioBufferList>, count: Int, time: Double) {
        lock.lock(); defer { lock.unlock() }
        guard samples.count < Int(format.mSampleRate * 2), format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else { return }
        if samples.isEmpty { firstTime = time }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        let channels = max(1, Int(format.mChannelsPerFrame))
        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        for frame in 0..<count {
            var value: Float = 0
            for channel in 0..<channels {
                let buffer = buffers[interleaved ? 0 : channel]
                guard let pointer = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                value += pointer[interleaved ? frame * channels + channel : frame]
            }
            samples.append(value / Float(channels))
        }
    }
}
