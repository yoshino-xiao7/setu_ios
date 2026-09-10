import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
#if canImport(UIKit)
import UIKit
#endif

public enum JmImageDescrambler {
    public struct StripBlit: Equatable {
        public let sourceY: Int
        public let destinationY: Int
        public let height: Int
    }

    public static func fileName(from url: URL) -> String {
        let name = url.lastPathComponent
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }

    public static func stripCount(photoID: Int, scrambleID: Int, fileName: String) -> Int {
        if photoID < scrambleID { return 0 }
        if photoID < 268_850 { return 10 }
        let modulus = photoID < 421_926 ? 10 : 8
        let digest = Insecure.MD5.hash(data: Data("\(photoID)\(fileName)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        guard let last = digest.utf8.last else { return 0 }
        return (Int(last) % modulus) * 2 + 2
    }

    public static func stripBlits(height: Int, count: Int) -> [StripBlit] {
        guard height > 0, count > 0 else { return [] }
        let over = height % count
        return (0..<count).map { index in
            var move = height / count
            let sourceY = height - (move * (index + 1)) - over
            var destinationY = move * index
            if index == 0 {
                move += over
            } else {
                destinationY += over
            }
            return StripBlit(sourceY: sourceY, destinationY: destinationY, height: move)
        }
    }

    public static func descramble(data: Data, photoID: Int, scrambleID: Int, fileName: String) -> Data {
        let strips = stripCount(photoID: photoID, scrambleID: scrambleID, fileName: fileName)
        guard strips > 0 else { return data }
        #if canImport(UIKit)
        let image = uprightCGImage(from: data)
        #else
        let image = cgImage(from: data)
        #endif
        guard let image, let restored = reorderStrips(image, count: strips) else { return data }
        return pngData(from: restored) ?? data
    }

    public static func descramble(data: Data, page: JmPageImage) -> Data {
        descramble(
            data: data,
            photoID: photoID(from: page.url) ?? page.albumID,
            scrambleID: page.scrambleID,
            fileName: fileName(from: page.url)
        )
    }

    #if canImport(UIKit)
    public static func descrambleUIImage(data: Data, page: JmPageImage) -> UIImage? {
        descrambleUIImage(
            data: data,
            photoID: photoID(from: page.url) ?? page.albumID,
            scrambleID: page.scrambleID,
            fileName: fileName(from: page.url)
        )
    }

    public static func descrambleUIImage(data: Data, photoID: Int, scrambleID: Int, fileName: String) -> UIImage? {
        guard let source = uprightCGImage(from: data) else { return nil }
        let count = stripCount(photoID: photoID, scrambleID: scrambleID, fileName: fileName)
        guard count > 0 else { return UIImage(cgImage: source, scale: 1, orientation: .up) }
        guard let restored = reorderStrips(source, count: count) else { return nil }
        return UIImage(cgImage: restored, scale: 1, orientation: .up)
    }
    #endif

    public static func photoID(from url: URL) -> Int? {
        let parts = url.pathComponents
        guard let photos = parts.firstIndex(of: "photos"), photos + 1 < parts.count else { return nil }
        return Int(parts[photos + 1])
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(
            source,
            0,
            [kCGImageSourceShouldCache: false, kCGImageSourceShouldCacheImmediately: false] as CFDictionary
        )
    }

    #if canImport(UIKit)
    private static func uprightCGImage(from data: Data) -> CGImage? {
        if let image = UIImage(data: data) {
            if image.imageOrientation == .up, let cgImage = image.cgImage {
                return cgImage
            }
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
            let drawn = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
            if let cgImage = drawn.cgImage { return cgImage }
        }
        return cgImage(from: data)
    }
    #endif

    private static func reorderStrips(_ image: CGImage, count: Int) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, count > 0 else { return image }
        let bytesPerRow = width * 4
        var destination = [UInt8](repeating: 255, count: bytesPerRow * height)
        for blit in stripBlits(height: height, count: count) where blit.height > 0 {
            guard blit.sourceY >= 0, blit.destinationY >= 0,
                  blit.sourceY + blit.height <= height,
                  blit.destinationY + blit.height <= height else { return nil }
            let crop = CGRect(x: 0, y: blit.sourceY, width: width, height: blit.height)
            guard let slice = image.cropping(to: crop),
                  slice.width == width, slice.height == blit.height,
                  let pixels = packedRGBA(from: slice) else { return nil }
            for row in 0..<blit.height {
                let from = row * bytesPerRow
                let to = (blit.destinationY + row) * bytesPerRow
                destination.replaceSubrange(to..<(to + bytesPerRow), with: pixels[from..<(from + bytesPerRow)])
            }
        }
        for index in stride(from: 3, to: destination.count, by: 4) {
            destination[index] = 255
        }
        return cgImage(width: width, height: height, topDownRGBA: destination, bytesPerRow: bytesPerRow)
    }

    /// Crop first, then copy that strip 1:1. Drawing the whole page first lets the
    /// decoder smear across the original scramble cuts; those edges become 分割线.
    /// Do not memcpy `dataProvider` of a cropped image: it often still points at the
    /// parent bitmap, so byte 0 is the original top, not the crop.
    private static func packedRGBA(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: bytesPerRow * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = makeBitmapContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bytesPerRow: bytesPerRow
            ) else { return false }
            context.setShouldAntialias(false)
            context.setAllowsAntialiasing(false)
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return pixels
    }

    private static func makeBitmapContext(data: UnsafeMutableRawPointer?, width: Int, height: Int, bytesPerRow: Int) -> CGContext? {
        let space = CGColorSpaceCreateDeviceRGB()
        return CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func cgImage(width: Int, height: Int, topDownRGBA: [UInt8], bytesPerRow: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(topDownRGBA) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
