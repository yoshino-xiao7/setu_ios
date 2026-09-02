import Foundation
import ImageIO
import XCTest
import SwiftUI
import SetuIOSCore
@testable import SetuIOSApp
#if os(iOS)
import UIKit
import AVFoundation
import MediaPlayer
#endif

final class SetuRemoteImageCacheTests: XCTestCase {
    func testFirstMissThenSameKeyHitMakesNoNetworkOrDecode() async throws {
        let fixture = try ImageFixture(), decodeCount = ImageCounter()
        let loader = fixture.loader(decode: { data, key in
            decodeCount.increment()
            XCTAssertFalse(Thread.isMainThread, "Decode must execute on a background executor")
            return try SetuRemoteImageLoader.decodeImage(data, key: key)
        })
        let key = fixture.key()
        XCTAssertNil(loader.cachedImage(for: key))
        let first = try await loader.image(for: key)
        XCTAssertTrue(loader.cachedImage(for: key) === first)
        let second = try await loader.image(for: key)
        XCTAssertTrue(first === second)
        let count = await fixture.server.count
        XCTAssertEqual(count, 1); XCTAssertEqual(decodeCount.value, 1)
    }

    func testKeyNormalizationAndFiniteSizeSelection() throws {
        let first = try XCTUnwrap(SetuImageKey.music("http://p1.music.126.net/cover.jpg?param=400y400#old", size: .thumbnail))
        let second = try XCTUnwrap(SetuImageKey.music("https://p1.music.126.net/cover.jpg?param=200y200", size: .thumbnail))
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, SetuImageKey.music(second.url.absoluteString, size: .large))
        XCTAssertEqual(SetuImageSize.fitting(width: 54, height: 54, scale: 3), .thumbnail)
        XCTAssertEqual(SetuImageSize.fitting(width: 100, height: 100, scale: 3), .medium)
        XCTAssertEqual(SetuImageSize.fitting(width: 360, height: 360, scale: 3), .large)
        XCTAssertEqual(SetuImageSize.fitting(width: nil, height: nil, scale: 3), .fullScreen)
        let tiers = Set((1...500).map { SetuImageSize.fitting(width: CGFloat($0), height: CGFloat($0), scale: 3) })
        XCTAssertLessThanOrEqual(tiers.count, 4)
    }

    func testSizeAndURLIsolationAndActualDownsampleDimensions() async throws {
        let fixture = try ImageFixture(width: 2400, height: 1200)
        let loader = fixture.loader()
        let small = fixture.key(), large = fixture.key(size: .large), other = fixture.key(path: "/other.png")
        _ = try await loader.image(for: small)
        _ = try await loader.image(for: large)
        XCTAssertEqual(loader.memory.image(for: small)?.cgImage.width, 200)
        XCTAssertEqual(loader.memory.image(for: small)?.cgImage.height, 100)
        XCTAssertEqual(loader.memory.image(for: large)?.cgImage.width, 1200)
        XCTAssertFalse(loader.cachedImage(for: small) === loader.cachedImage(for: large))
        XCTAssertNil(loader.cachedImage(for: other))
        _ = try await loader.image(for: other)
        XCTAssertFalse(loader.cachedImage(for: small) === loader.cachedImage(for: other))
        XCTAssertLessThan(try XCTUnwrap(loader.memory.image(for: small)).cost, 200 * 200 * 5)
    }

    func testTenConcurrentConsumersShareOneNetworkAndDecode() async throws {
        let fixture = try ImageFixture(), counter = ImageCounter(), gate = MusicTestGate()
        let started = expectation(description: "one image request")
        await fixture.server.configure(gate: gate, started: { started.fulfill() })
        let loader = fixture.loader(decode: { data, key in counter.increment(); return try SetuRemoteImageLoader.decodeImage(data, key: key) })
        let key = fixture.key()
        let callers = Task {
            try await withThrowingTaskGroup(of: Bool.self) { group in
                for _ in 0..<10 { group.addTask { _ = try await loader.image(for: key); return true } }
                var count = 0; for try await _ in group { count += 1 }; return count
            }
        }
        await fulfillment(of: [started], timeout: 2)
        await gate.open()
        let completed = try await callers.value
        XCTAssertEqual(completed, 10)
        let requests = await fixture.server.count
        XCTAssertEqual(requests, 1); XCTAssertEqual(counter.value, 1)
    }

    func testDecodeFailureClearsFlightAndAllowsRetry() async throws {
        let fixture = try ImageFixture(), loader = fixture.loader()
        let valid = await fixture.server.data
        await fixture.server.setData(Data("invalid image".utf8))
        do { _ = try await loader.image(for: fixture.key()); XCTFail("Invalid image must fail") } catch {}
        XCTAssertNil(loader.cachedImage(for: fixture.key()))
        await fixture.server.setData(valid)
        _ = try await loader.image(for: fixture.key())
        let count = await fixture.server.count
        XCTAssertEqual(count, 2)
    }

    func testTransportFailureDoesNotPoisonFlight() async throws {
        let fixture = try ImageFixture(), loader = fixture.loader()
        await fixture.server.setStatus(503)
        do { _ = try await loader.image(for: fixture.key()); XCTFail("HTTP failure") } catch {}
        await fixture.server.setStatus(200)
        _ = try await loader.image(for: fixture.key())
        let count = await fixture.server.count
        XCTAssertEqual(count, 3, "Existing transport retry is bounded to one, followed by the successful user retry")
    }

    func testEvictionReloadsAndURLCacheHitAvoidsNetwork() async throws {
        let fixture = try ImageFixture()
        let cache = URLCache(memoryCapacity: 2 * 1024 * 1024, diskCapacity: 2 * 1024 * 1024, diskPath: "image-test-\(UUID().uuidString)")
        let loader = fixture.loader(urlCache: cache), key = fixture.key()
        let response = try XCTUnwrap(HTTPURLResponse(url: key.url, statusCode: 200, httpVersion: nil, headerFields: ["Cache-Control": "public, max-age=3600", "Content-Type": "image/png"]))
        let data = await fixture.server.data
        cache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: URLRequest(url: key.url, cachePolicy: .returnCacheDataElseLoad))
        _ = try await loader.image(for: key)
        loader.memory.removeAll()
        XCTAssertNil(loader.cachedImage(for: key))
        _ = try await loader.image(for: key)
        let count = await fixture.server.count
        XCTAssertEqual(count, 0, "Clearing decoded memory must retain the existing URLCache layer")
        cache.removeAllCachedResponses()
        loader.memory.removeAll()
        _ = try await loader.image(for: key)
        let reloaded = await fixture.server.count; XCTAssertEqual(reloaded, 1)
    }

    func testMemoryBudgetAndClearDoNotAllowLateDecodeToRefill() async throws {
        let fixture = try ImageFixture(), memory = SetuImageMemoryCache()
        XCTAssertEqual(memory.costLimit, 64 * 1024 * 1024); XCTAssertEqual(memory.countLimit, 200)
        let gate = MusicTestGate(), started = expectation(description: "pending image")
        await fixture.server.configure(gate: gate, started: { started.fulfill() })
        let loader = fixture.loader(memory: memory)
        let request = Task { try await loader.image(for: fixture.key()) }
        await fulfillment(of: [started], timeout: 2)
        memory.removeAll(); await gate.open(); _ = try await request.value
        XCTAssertNil(loader.cachedImage(for: fixture.key()), "Pre-warning work must not refill the cleared memory cache")
        _ = try await loader.image(for: fixture.key())
        XCTAssertNotNil(loader.cachedImage(for: fixture.key()))
    }

    #if os(iOS)
    @MainActor
    func testNowPlayingSynchronouslyReusesLargeDecodedCover() async throws {
        let fixture = try ImageFixture(width: 1200, height: 1200)
        let loader = fixture.loader(), key = fixture.key(size: .large)
        let image = try await loader.image(for: key)
        let shared = SetuRemoteImageLoader.shared
        shared.memory.insert(try XCTUnwrap(loader.memory.image(for: key)), for: key, generation: shared.memory.generation)
        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("artwork-test-\(UUID().uuidString).wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 80))
        buffer.frameLength = 80
        let samples = try XCTUnwrap(buffer.floatChannelData)
        for index in 0..<80 { samples[0][index] = 0 }
        do {
            let audio = try AVAudioFile(forWriting: audioURL, settings: format.settings)
            try audio.write(from: buffer)
        }
        let controller = MusicPlaybackController(persistsPlayback: false)
        defer {
            controller.stop()
            shared.memory.removeAll()
            try? FileManager.default.removeItem(at: audioURL)
        }
        let song = MusicSong(id: 1, name: "缓存封面", artists: [],
                             album: MusicAlbum(id: 1, name: "测试", picUrl: key.url.absoluteString), duration: 10)
        for _ in 0..<2 {
            controller.play(url: audioURL, track: MusicPlaybackTrack(song: song))
            // No await: artwork must already be present on the synchronous cache path.
            let artwork = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork)
            XCTAssertEqual(artwork.bounds.size, image.size)
            XCTAssertEqual(artwork.image(at: image.size)?.cgImage?.width, 1200)
        }
        let count = await fixture.server.count
        XCTAssertEqual(count, 1, "Now Playing must reuse the already loaded large cover")
    }

    @MainActor
    func testBothViewsRenderCachedPixelsOnFirstFrameAtCompactAndWideWidths() async throws {
        let fixture = try ImageFixture(width: 1200, height: 1200)
        let data = await fixture.server.data
        let shared = SetuRemoteImageLoader.shared
        defer { shared.memory.removeAll() }
        for tier in [SetuImageSize.thumbnail, .large] {
            let key = fixture.key(size: tier)
            let decoded = try await Task.detached {
                try SetuRemoteImageLoader.decodeImage(data, key: key)
            }.value
            shared.memory.insert(decoded, for: key, generation: shared.memory.generation)
        }
        // ImageRenderer renders synchronously: neither view's .task has a chance
        // to populate local state. Red pixels must therefore come from memory.
        for screenWidth in [CGFloat(375), CGFloat(430)] {
            let coverSide = min(screenWidth - 48, 360)
            let views = [
                AnyView(MusicArtworkView(urlString: fixture.key().url.absoluteString)),
                AnyView(SetuRemoteImage(urlString: fixture.key().url.absoluteString, accessibilityLabel: "测试封面")),
                AnyView(MusicArtworkView(urlString: fixture.key().url.absoluteString,
                                         width: coverSide, height: coverSide, artworkSize: .lockScreen))
            ]
            for (index, view) in views.enumerated() {
                // Construct twice to cover re-entry with completely new @State.
                for _ in 0..<2 {
                    let renderer = ImageRenderer(content: view.environment(\.displayScale, 3))
                    renderer.scale = 1
                    let image = try XCTUnwrap(renderer.uiImage)
                    let bitmap = try XCTUnwrap(image.cgImage)
                    let center = try XCTUnwrap(bitmap.cropping(to: CGRect(x: bitmap.width / 2 - 5,
                        y: bitmap.height / 2 - 5, width: 10, height: 10)))
                    var pixel = [UInt8](repeating: 0, count: 4)
                    let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1,
                        bitsPerComponent: 8, bytesPerRow: 4, space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                    context.draw(center, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                    XCTAssertGreaterThan(pixel[0], 230)
                    XCTAssertLessThan(pixel[1], 25)
                    XCTAssertLessThan(pixel[2], 25, "First render must contain cover pixels, not placeholder")
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "cached-first-frame-\(Int(screenWidth))-\(index)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
        let count = await fixture.server.count
        XCTAssertEqual(count, 0, "Rendering cached covers must not request image data")
    }

    func testMemoryWarningClearsImagesAndAccentOnly() async throws {
        let fixture = try ImageFixture(), center = NotificationCenter()
        let memory = SetuImageMemoryCache(center: center), loader = fixture.loader(memory: memory), key = fixture.key()
        _ = try await loader.averageColor(for: key)
        XCTAssertNotNil(loader.cachedImage(for: key)); XCTAssertNotNil(loader.cachedAccent(for: key))
        center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertNil(loader.cachedImage(for: key)); XCTAssertNil(loader.cachedAccent(for: key))
    }
    #endif

    func testEXIFOrientationIsAppliedDuringDownsampling() async throws {
        let fixture = try ImageFixture(width: 800, height: 400, orientation: 6), loader = fixture.loader()
        let image = try await loader.image(for: fixture.key())
        let bitmap = try XCTUnwrap(loader.memory.image(for: fixture.key())?.cgImage)
        XCTAssertEqual(bitmap.width, 100); XCTAssertEqual(bitmap.height, 200)
        #if os(iOS)
        XCTAssertEqual(image.imageOrientation, .up)
        #else
        XCTAssertEqual(image.size.width, 100)
        #endif
    }

    func testAverageColorUsesImageCacheAndCachesBackgroundRender() async throws {
        let fixture = try ImageFixture(), renders = ImageCounter(), decodes = ImageCounter()
        let loader = SetuRemoteImageLoader(session: fixture.session(), decode: { data, key in
            decodes.increment(); return try SetuRemoteImageLoader.decodeImage(data, key: key)
        }, renderAccent: { _ in
            XCTAssertFalse(Thread.isMainThread)
            renders.increment(); return SetuImageAccent(red: 1, green: 0, blue: 0)
        })
        _ = try await loader.image(for: fixture.key())
        let first = try await loader.averageColor(for: fixture.key())
        let second = try await loader.averageColor(for: fixture.key())
        XCTAssertEqual(first, second); XCTAssertEqual(renders.value, 1); XCTAssertEqual(decodes.value, 1)
        let count = await fixture.server.count; XCTAssertEqual(count, 1)
        let actual = try await fixture.loader().averageColor(for: fixture.key())
        XCTAssertGreaterThan(try XCTUnwrap(actual).red, 0.9)
        XCTAssertLessThan(try XCTUnwrap(actual).blue, 0.1)
    }

    @MainActor
    func testNewViewStateSynchronouslyDisplaysMemoryHitBeforeLoadTask() async throws {
        let fixture = try ImageFixture(), loader = fixture.loader(), key = fixture.key()
        let cached = try await loader.image(for: key)
        let newViewState = SetuRemoteImageState()
        XCTAssertTrue(newViewState.displayedImage(for: key, loader: loader) === cached)
        XCTAssertNil(newViewState.key, "No asynchronous view loading has run yet")
        XCTAssertFalse(newViewState.isLoading)
    }

    @MainActor
    func testURLChangeAndCancelledOldTaskCannotReplaceNewImage() async throws {
        let fixture = try ImageFixture(), loader = fixture.loader(), state = SetuRemoteImageState()
        let gate = MusicTestGate(), started = expectation(description: "A pending")
        let a = fixture.key(), b = fixture.key(path: "/b.png")
        await fixture.server.configure(gate: gate, started: { started.fulfill() }, path: a.url.path)
        let old = Task { await state.load(a, loader: loader) }
        await fulfillment(of: [started], timeout: 2)
        old.cancel()
        XCTAssertNil(state.displayedImage(for: b, loader: loader), "Before .task(B), never display A under B's identity")
        await state.load(b, loader: loader)
        let expected = state.image
        await gate.open(); await old.value
        XCTAssertEqual(state.key, b); XCTAssertTrue(state.image === expected); XCTAssertFalse(state.failed)
        XCTAssertFalse(state.isLoading)
    }

    @MainActor
    func testCancellationWithoutReplacementDoesNotPublishImageOrFailure() async throws {
        let fixture = try ImageFixture(), loader = fixture.loader(), state = SetuRemoteImageState()
        let gate = MusicTestGate(), started = expectation(description: "cancelled view")
        await fixture.server.configure(gate: gate, started: { started.fulfill() })
        let old = Task { await state.load(fixture.key(), loader: loader) }
        await fulfillment(of: [started], timeout: 2)
        old.cancel(); await gate.open(); await old.value
        XCTAssertNil(state.image); XCTAssertFalse(state.failed)
        XCTAssertNotNil(loader.cachedImage(for: fixture.key()), "Another consumer may still reuse the shared result")
    }
}

private final class ImageCounter: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private struct ImageFixture {
    let host = "image-\(UUID().uuidString.lowercased()).test"
    let server: ImageTestServer
    init(width: Int = 600, height: Int = 400, orientation: Int = 1) throws {
        server = ImageTestServer(data: try makeImageData(width: width, height: height, orientation: orientation))
        ImageTestProtocol.register(server, host: host)
    }
    func key(path: String = "/cover.png", size: SetuImageSize = .thumbnail) -> SetuImageKey {
        SetuImageKey(url: URL(string: "https://\(host)\(path)")!, size: size)
    }
    func session(urlCache: URLCache? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageTestProtocol.self]; configuration.urlCache = urlCache
        return URLSession(configuration: configuration)
    }
    func loader(urlCache: URLCache? = nil, memory: SetuImageMemoryCache = SetuImageMemoryCache(),
                decode: @escaping @Sendable (Data, SetuImageKey) throws -> SetuDecodedImage = { try SetuRemoteImageLoader.decodeImage($0, key: $1) }) -> SetuRemoteImageLoader {
        SetuRemoteImageLoader(session: session(urlCache: urlCache), memory: memory, decode: decode)
    }
}

private actor ImageTestServer {
    private(set) var data: Data
    private(set) var count = 0
    private var status = 200
    private var gate: MusicTestGate?
    private var started: (@Sendable () -> Void)?
    private var gatedPath: String?
    init(data: Data) { self.data = data }
    func setData(_ data: Data) { self.data = data }
    func setStatus(_ status: Int) { self.status = status }
    func configure(gate: MusicTestGate, started: @escaping @Sendable () -> Void, path: String? = nil) {
        self.gate = gate; self.started = started; gatedPath = path
    }
    func response(path: String) async -> (Data, Int) {
        count += 1
        if gatedPath == nil || path == gatedPath {
            let notify = started; started = nil
            notify?(); await gate?.wait()
        }
        return (data, status)
    }
}

private final class ImageTestProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var servers: [String: ImageTestServer] = [:]
    private var responseTask: Task<Void, Never>?
    static func register(_ server: ImageTestServer, host: String) { lock.withLock { servers[host] = server } }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasPrefix("image-") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let server = Self.lock.withLock({ Self.servers[url.host ?? ""] }) else { return }
        responseTask = Task {
            let (data, status) = await server.response(path: url.path)
            guard !Task.isCancelled, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "image/png", "Cache-Control": "public, max-age=3600"]) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { responseTask?.cancel() }
}

private func makeImageData(width: Int, height: Int, orientation: Int) throws -> Data {
    let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try XCTUnwrap(context.makeImage()), data = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
}
