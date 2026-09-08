import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import ZIPFoundation

public struct PixivAnimationFrame: Codable, Sendable {
    public let file: String
    public let delay: Int
}
public protocol PixivAnimationRendering: Sendable {
    func render(zip: Data, frames: [PixivAnimationFrame]) async throws -> URL
}
/// Decodes one bounded frame at a time and writes native H.264, preserving millisecond delays.
public struct PixivAnimationRenderer: PixivAnimationRendering {
    public init() { }
    public func render(zip: Data, frames: [PixivAnimationFrame]) async throws -> URL {
        guard zip.count <= 100 * 1024 * 1024, !frames.isEmpty, frames.count <= 3000,
              frames.allSatisfy({ $0.delay > 0 && $0.delay <= 60000 && !$0.file.isEmpty && !$0.file.contains("/") && !$0.file.contains("\\") && $0.file != ".." }),
              Set(frames.map(\.file)).count == frames.count else { throw PixivClientError("动图帧数据无效") }
        let duration = frames.reduce(0) { $0 + $1.delay }
        guard duration <= 600000 else { throw PixivClientError("动图时长超出当前支持范围") }
        let archive = try Archive(data: zip, accessMode: .read)
        var entries: [String: Entry] = [:]
        var size: UInt64 = 0
        for entry in archive {
            guard entry.type == .file, entries[entry.path] == nil, entries.count < 3000,
                  entry.uncompressedSize <= 20 * 1024 * 1024 else { throw PixivClientError("动图压缩包无效") }
            size += entry.uncompressedSize
            guard size <= 300 * 1024 * 1024 else { throw PixivClientError("动图解压数据过大") }
            entries[entry.path] = entry
        }
        guard frames.allSatisfy({ entries[$0.file] != nil }) else { throw PixivClientError("动图缺少图片帧") }
        func image(_ frame: PixivAnimationFrame) throws -> CGImage {
            try Task.checkCancellation()
            let entry = entries[frame.file]!
            var data = Data()
            _ = try archive.extract(entry, consumer: { chunk in
                try Task.checkCancellation()
                guard data.count + chunk.count <= 20 * 1024 * 1024 else { throw PixivClientError("动图帧过大") }
                data.append(chunk)
            })
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 12000, height <= 12000, width * height <= 40_000_000,
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1920, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw PixivClientError("动图图片帧无法解码") }
            return image
        }
        let first = try image(frames[0])
        let width = max(2, first.width / 2 * 2), height = max(2, first.height / 2 * 2)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SetuPixivAnimations", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] where file.pathExtension == "mp4" {
            if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date < Date().addingTimeInterval(-86400) { try? FileManager.default.removeItem(at: file) }
        }
        let output = directory.appendingPathComponent(UUID().uuidString + ".mp4")
        var succeeded = false
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        defer { if !succeeded { writer.cancelWriting(); try? FileManager.default.removeItem(at: output) } }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 5_000_000]])
        input.expectsMediaDataInRealTime = false
        input.mediaTimeScale = 1000
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height, kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        guard writer.canAdd(input) else { throw PixivClientError("设备无法创建动图视频") }
        writer.add(input)
        guard writer.startWriting() else { throw PixivClientError("动图视频创建失败") }
        writer.startSession(atSourceTime: .zero)
        let deadline = Date().addingTimeInterval(180)
        func append(_ image: CGImage, at milliseconds: Int) async throws {
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                guard Date() < deadline, writer.status == .writing else { throw PixivClientError("动图转换未能完成，请重试") }
                try await Task.sleep(for: .milliseconds(10))
            }
            try Task.checkCancellation()
            guard Date() < deadline, let pool = adaptor.pixelBufferPool else { throw PixivClientError("动图转换未能完成，请重试") }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw PixivClientError("动图内存不足") }
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else { throw PixivClientError("动图帧渲染失败") }
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let scale = min(Double(width) / Double(image.width), Double(height) / Double(image.height))
            let w = Double(image.width) * scale, h = Double(image.height) * scale
            context.draw(image, in: CGRect(x: (Double(width)-w)/2, y: (Double(height)-h)/2, width: w, height: h))
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(milliseconds), timescale: 1000)) else { throw PixivClientError("动图帧写入失败") }
        }
        var timestamp = 0
        var last = first
        for (index, frame) in frames.enumerated() {
            let current = index == 0 ? first : try image(frame)
            try await append(current, at: timestamp)
            timestamp += frame.delay; last = current
        }
        if frames.last!.delay > 1 { try await append(last, at: duration - 1) }
        writer.endSession(atSourceTime: CMTime(value: Int64(duration), timescale: 1000))
        input.markAsFinished()
        await writer.finishWriting()
        try Task.checkCancellation()
        guard writer.status == .completed, let count = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize, count <= 100 * 1024 * 1024 else { throw PixivClientError("动图视频未能保存，请重试") }
        succeeded = true
        return output
    }
}
