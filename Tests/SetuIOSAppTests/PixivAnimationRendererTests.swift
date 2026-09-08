import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import XCTest
import ZIPFoundation
@testable import SetuIOSCore

final class PixivAnimationRendererTests: XCTestCase {
    func testNativeMP4PreservesUnequalFrameDelays() async throws {
        let archive = try Archive(data: Data(), accessMode: .create)
        for (index, gray) in [CGFloat(0.1), CGFloat(0.9)].enumerated() {
            let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(gray: gray, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            let image = try XCTUnwrap(context.makeImage())
            let data = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let bytes = data as Data
            try archive.addEntry(with: "\(index).png", type: .file, uncompressedSize: Int64(bytes.count), compressionMethod: .deflate) { position, size in
                bytes.subdata(in: Int(position)..<(Int(position) + size))
            }
        }
        let file = try await PixivAnimationRenderer().render(zip: XCTUnwrap(archive.data), frames: [PixivAnimationFrame(file: "0.png", delay: 37), PixivAnimationFrame(file: "1.png", delay: 83)])
        defer { try? FileManager.default.removeItem(at: file) }
        let asset = AVURLAsset(url: file)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 0.120, accuracy: 0.002)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: try XCTUnwrap(tracks.first), outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output); XCTAssertTrue(reader.startReading())
        var times: [Double] = []
        while let sample = output.copyNextSampleBuffer() { times.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds) }
        XCTAssertEqual(reader.status, .completed)
        XCTAssertEqual(times.count, 3)
        XCTAssertEqual(times[0], 0, accuracy: 0.001)
        XCTAssertEqual(times[1], 0.037, accuracy: 0.001)
        XCTAssertEqual(times[2], 0.119, accuracy: 0.001)
    }
    func testInvalidFramesCannotCreateAnOutputFile() async {
        for frame in [PixivAnimationFrame(file: "../escape.png", delay: 10), PixivAnimationFrame(file: "0.png", delay: 0)] {
            do { _ = try await PixivAnimationRenderer().render(zip: Data(), frames: [frame]); XCTFail("Invalid frame accepted") }
            catch { }
        }
    }
}
