import CoreImage
import Foundation
import ImageIO
import Observation
import SwiftUI
import SetuIOSCore

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Finite decoded pixel tiers, selected from display points × display scale.
enum SetuImageSize: Int, CaseIterable, Sendable {
    case thumbnail = 200
    case medium = 400
    case large = 1200
    case fullScreen = 3072

    static func fitting(width: CGFloat?, height: CGFloat?, scale: CGFloat) -> Self {
        guard width != nil || height != nil else { return .fullScreen }
        let pixels = max(width ?? height ?? 0, height ?? width ?? 0) * max(scale, 1)
        return allCases.first { CGFloat($0.rawValue) >= pixels } ?? .fullScreen
    }
}

struct SetuImageKey: Hashable, Sendable {
    let url: URL
    let size: SetuImageSize

    init(url: URL, size: SetuImageSize) {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        let scheme = components?.scheme?.lowercased(), host = components?.host?.lowercased()
        components?.scheme = scheme
        components?.host = host
        self.url = components?.url ?? url
        self.size = size
    }

    static func music(_ raw: String?, size: SetuImageSize) -> Self? {
        guard let normalized = secureURLString(raw, artworkSize: .custom(width: size.rawValue, height: size.rawValue)),
              let url = URL(string: normalized) else { return nil }
        return Self(url: url, size: size)
    }

    var cacheKey: NSString { "\(size.rawValue)|\(url.absoluteString)" as NSString }
}

struct SetuImageAccent: Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
}

/// Only immutable, already-rasterized images cross executors.
final class SetuDecodedImage: @unchecked Sendable {
    let image: SetuPlatformImage
    let cgImage: CGImage
    var cost: Int { cgImage.bytesPerRow * cgImage.height }

    init(cgImage: CGImage) {
        self.cgImage = cgImage
        #if os(iOS)
        image = UIImage(cgImage: cgImage)
        #else
        image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #endif
    }
}

/// NSCache is thread-safe. The lock also makes memory-pressure eviction and epoch
/// validation atomic, so a late decode cannot refill a just-cleared cache.
final class SetuImageMemoryCache: @unchecked Sendable {
    private final class AccentBox { let value: SetuImageAccent; init(_ value: SetuImageAccent) { self.value = value } }
    private let images = NSCache<NSString, SetuDecodedImage>()
    private let accents = NSCache<NSString, AccentBox>()
    private let lock = NSLock()
    private var epoch = UUID()
    private let center: NotificationCenter
    private var warningObserver: NSObjectProtocol?
    let costLimit: Int
    let countLimit: Int

    init(costLimit: Int = 64 * 1024 * 1024, countLimit: Int = 200, center: NotificationCenter = .default) {
        self.costLimit = costLimit; self.countLimit = countLimit; self.center = center
        images.totalCostLimit = costLimit; images.countLimit = countLimit
        accents.countLimit = countLimit
        #if os(iOS)
        warningObserver = center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [weak self] _ in self?.removeAll() }
        #endif
    }

    deinit { if let warningObserver { center.removeObserver(warningObserver) } }
    var generation: UUID { lock.withLock { epoch } }
    func image(for key: SetuImageKey) -> SetuDecodedImage? { lock.withLock { images.object(forKey: key.cacheKey) } }
    func accent(for key: SetuImageKey) -> SetuImageAccent? { lock.withLock { accents.object(forKey: key.cacheKey)?.value } }
    func insert(_ image: SetuDecodedImage, for key: SetuImageKey, generation: UUID) {
        lock.withLock { if epoch == generation { images.setObject(image, forKey: key.cacheKey, cost: image.cost) } }
    }
    func insert(_ accent: SetuImageAccent, for key: SetuImageKey, generation: UUID) {
        lock.withLock { if epoch == generation { accents.setObject(AccentBox(accent), forKey: key.cacheKey) } }
    }
    func removeAll() { lock.withLock { epoch = UUID(); images.removeAllObjects(); accents.removeAllObjects() } }
}

/// Shared CIContext supports concurrent rendering; construction is not per artwork.
private final class SetuImageColorRenderer: @unchecked Sendable {
    static let shared = SetuImageColorRenderer()
    private let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
    func accent(_ image: CGImage) -> SetuImageAccent? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent)]),
              let output = filter.outputImage else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &rgba, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return SetuImageAccent(red: Double(rgba[0]) / 255, green: Double(rgba[1]) / 255, blue: Double(rgba[2]) / 255)
    }
}

actor SetuRemoteImageLoader {
    static let shared = SetuRemoteImageLoader()
    nonisolated let memory: SetuImageMemoryCache
    private let session: URLSession
    private let decode: @Sendable (Data, SetuImageKey) throws -> SetuDecodedImage
    private let renderAccent: @Sendable (CGImage) -> SetuImageAccent?
    private struct Flight { let id: UUID; let task: Task<SetuDecodedImage, Error> }
    private struct AccentFlight { let id: UUID; let task: Task<SetuImageAccent?, Error> }
    private var flights: [SetuImageKey: Flight] = [:]
    private var accentFlights: [SetuImageKey: AccentFlight] = [:]

    init(session: URLSession? = nil, memory: SetuImageMemoryCache = SetuImageMemoryCache(),
         decode: @escaping @Sendable (Data, SetuImageKey) throws -> SetuDecodedImage = { try SetuRemoteImageLoader.decodeImage($0, key: $1) },
         renderAccent: @escaping @Sendable (CGImage) -> SetuImageAccent? = { SetuImageColorRenderer.shared.accent($0) }) {
        self.memory = memory; self.decode = decode; self.renderAccent = renderAccent
        if let session { self.session = session } else {
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024, diskPath: "SetuRemoteImageCache")
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            self.session = URLSession(configuration: configuration)
        }
    }

    nonisolated func cachedImage(for key: SetuImageKey) -> SetuPlatformImage? { memory.image(for: key)?.image }
    nonisolated func cachedAccent(for key: SetuImageKey) -> SetuImageAccent? { memory.accent(for: key) }

    func image(for key: SetuImageKey) async throws -> SetuPlatformImage {
        try await decodedImage(for: key).image
    }

    private func decodedImage(for key: SetuImageKey) async throws -> SetuDecodedImage {
        try Task.checkCancellation()
        if let cached = memory.image(for: key) { return cached }
        let flight: Flight
        if let existing = flights[key] { flight = existing } else {
            let session = self.session, decode = self.decode, memory = self.memory, epoch = memory.generation
            flight = Flight(id: UUID(), task: Task.detached(priority: .utility) {
                do {
                    let data = try await Self.fetchData(from: key.url, session: session)
                    let decoded = try decode(data, key)
                    memory.insert(decoded, for: key, generation: epoch)
                    return decoded
                } catch {
                    session.configuration.urlCache?.removeCachedResponse(for: Self.imageRequest(url: key.url, cachePolicy: .returnCacheDataElseLoad))
                    throw error
                }
            })
            flights[key] = flight
        }
        do {
            let result = try await flight.task.value
            if flights[key]?.id == flight.id { flights[key] = nil }
            try Task.checkCancellation()
            return result
        } catch {
            if flights[key]?.id == flight.id { flights[key] = nil }
            throw error
        }
    }

    func averageColor(for key: SetuImageKey) async throws -> SetuImageAccent? {
        try Task.checkCancellation()
        if let accent = memory.accent(for: key) { return accent }
        // Image loading already coalesces with the cover and Now Playing consumers.
        let epoch = memory.generation
        let decoded = try await decodedImage(for: key)
        if let cached = memory.accent(for: key) { return cached }
        let flight: AccentFlight
        if let existing = accentFlights[key] { flight = existing } else {
            let memory = self.memory, renderAccent = self.renderAccent
            flight = AccentFlight(id: UUID(), task: Task.detached(priority: .utility) {
                let accent = renderAccent(decoded.cgImage)
                if let accent { memory.insert(accent, for: key, generation: epoch) }
                return accent
            })
            accentFlights[key] = flight
        }
        do {
            let result = try await flight.task.value
            if accentFlights[key]?.id == flight.id { accentFlights[key] = nil }
            try Task.checkCancellation()
            return result
        } catch {
            if accentFlights[key]?.id == flight.id { accentFlights[key] = nil }
            throw error
        }
    }

    private nonisolated static func fetchData(from url: URL, session: URLSession) async throws -> Data {
        let request = imageRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        if let cached = session.configuration.urlCache?.cachedResponse(for: request) { return cached.data }
        do { return try await fetch(request, session: session) }
        catch {
            try Task.checkCancellation()
            return try await fetch(imageRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData), session: session)
        }
    }

    private nonisolated static func imageRequest(url: URL, cachePolicy: URLRequest.CachePolicy) -> URLRequest {
        if JmAppToken.isImageCDN(url) {
            return JmAppToken.imageRequest(url: url, cachePolicy: cachePolicy)
        }
        if HanimeSite.isImageCDN(url) {
            return HanimeSite.imageRequest(url: url, cachePolicy: cachePolicy)
        }
        if CloudVideoCDN.isImageCDN(url) {
            return CloudVideoCDN.imageRequest(url: url, cachePolicy: cachePolicy)
        }
        return URLRequest(url: url, cachePolicy: cachePolicy)
    }

    private nonisolated static func fetch(_ request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else { throw URLError(.badServerResponse) }
        return data
    }

    nonisolated static func decodeImage(_ data: Data, key: SetuImageKey) throws -> SetuDecodedImage {
        if let thumbnail = thumbnailCGImage(from: data, maxPixelSize: key.size.rawValue),
           let decoded = rasterizedImage(thumbnail) {
            return decoded
        }
        if let image = platformCGImage(from: data), let decoded = rasterizedImage(image) {
            return decoded
        }
        throw URLError(.cannotDecodeContentData)
    }

    private nonisolated static func thumbnailCGImage(from data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    private nonisolated static func platformCGImage(from data: Data) -> CGImage? {
        #if os(iOS)
        return UIImage(data: data)?.cgImage
        #elseif os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }

    private nonisolated static func rasterizedImage(_ image: CGImage) -> SetuDecodedImage? {
        // Force bitmap rasterization here; drawing the SwiftUI image cannot defer source decoding.
        let colorSpace = image.colorSpace?.model == .rgb ? image.colorSpace : CGColorSpace(name: CGColorSpace.sRGB)
        guard let colorSpace, let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let bitmap = rasterize(image, in: context) else {
            return nil
        }
        return SetuDecodedImage(cgImage: bitmap)
    }

    private nonisolated static func rasterize(_ image: CGImage, in context: CGContext) -> CGImage? {
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}

/// Per-view state only. Cache lookup is synchronous, including a newly constructed
/// view and the render immediately after its URL changes, before .task runs.
@MainActor @Observable
final class SetuRemoteImageState {
    private(set) var key: SetuImageKey?
    private(set) var image: SetuPlatformImage?
    private(set) var isLoading = false
    private(set) var failed = false
    private var revision = UUID()

    func displayedImage(for key: SetuImageKey?, loader: SetuRemoteImageLoader = .shared) -> SetuPlatformImage? {
        guard let key else { return nil }
        return (self.key == key ? image : nil) ?? loader.cachedImage(for: key)
    }

    func load(_ key: SetuImageKey?, loader: SetuRemoteImageLoader = .shared, animation: Animation? = nil) async {
        let ticket = UUID(); revision = ticket
        self.key = key; failed = false
        image = key.flatMap { loader.cachedImage(for: $0) }
        guard let key, image == nil else { isLoading = false; return }
        isLoading = true
        do {
            let loaded = try await loader.image(for: key)
            guard revision == ticket, self.key == key, !Task.isCancelled else { return }
            withAnimation(animation) { image = loaded; isLoading = false }
        } catch {
            guard revision == ticket, self.key == key else { return }
            isLoading = false
            guard !Task.isCancelled else { return }
            failed = true
        }
    }
}

struct SetuImageLoadID: Hashable {
    let key: SetuImageKey?
    let retry: UUID
}
