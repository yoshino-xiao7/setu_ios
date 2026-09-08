import Foundation
import ImageIO
import XCTest
@testable import SetuIOSApp

@MainActor
final class ArtworkImageStoreTests: XCTestCase {
    func testRotatingCapabilityAndConcurrentConsumersReuseOneDecode() async throws {
        let server = ArtworkImageTestServer(data: try pixels())
        let cache = ArtworkImageStore(fetch: { try await server.fetch($0) })
        let first = Task { try await cache.load("capability-A", identity: "pixiv:1:0", quality: .thumbnail) }
        let second = Task { try await cache.load("capability-B", identity: "pixiv:1:0", quality: .thumbnail) }
        let a = try await first.value, b = try await second.value
        XCTAssertTrue(a === b)
        let reused = try await cache.load("capability-C", identity: "pixiv:1:0", quality: .thumbnail)
        XCTAssertTrue(reused === a)
        let requests = await server.requests
        XCTAssertEqual(requests, 1)
    }

    func testThumbnailRemainsAvailableDuringPreviewAndOriginalUpgrade() async throws {
        let server = ArtworkImageTestServer(data: try pixels())
        let cache = ArtworkImageStore(fetch: { try await server.fetch($0) })
        let thumbnail = try await cache.load("thumb", identity: "pixiv:1:0", quality: .thumbnail)
        XCTAssertTrue(cache.cached("pixiv:1:0", quality: .preview) === thumbnail)
        XCTAssertNil(cache.cached("pixiv:1:0", quality: .preview, fallback: false))
        let preview = try await cache.load("preview", identity: "pixiv:1:0", quality: .preview)
        XCTAssertTrue(cache.cached("pixiv:1:0", quality: .original) === preview)
        XCTAssertNil(cache.cached("pixiv:1:0", quality: .original, fallback: false))
        _ = try await cache.load("original", identity: "pixiv:1:0", quality: .original)
        XCTAssertNil(cache.cached("gallery:1:0", quality: .thumbnail))
        let requests = await server.requests
        XCTAssertEqual(requests, 3, "A lower-quality cached image must never suppress fetching the original")
    }

    func testAccountClearRejectsLateInFlightImageAndAllowsFreshRequest() async throws {
        let server = ArtworkImageTestServer(data: try pixels())
        let cache = ArtworkImageStore(fetch: { try await server.fetch($0) })
        await server.block()
        let old = Task { try await cache.load("old-account", identity: "pixiv:1:0", quality: .preview) }
        await server.waitForRequest()
        cache.clear()
        await server.release()
        do { _ = try await old.value; XCTFail("The previous account's image must be discarded") }
        catch is CancellationError { }
        XCTAssertNil(cache.cached("pixiv:1:0", quality: .preview))
        _ = try await cache.load("new-account", identity: "pixiv:1:0", quality: .preview)
        let requests = await server.requests
        XCTAssertEqual(requests, 2)
    }

    private func pixels() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
                                             bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private actor ArtworkImageTestServer {
    let data: Data
    var requests = 0
    var blocked = false
    var pending: CheckedContinuation<Void, Never>?
    var started: CheckedContinuation<Void, Never>?
    init(data: Data) { self.data = data }
    func block() { blocked = true }
    func waitForRequest() async {
        if requests == 0 { await withCheckedContinuation { started = $0 } }
    }
    func release() { blocked = false; pending?.resume(); pending = nil }
    func fetch(_ path: String) async throws -> Data {
        requests += 1; started?.resume(); started = nil
        if blocked { await withCheckedContinuation { pending = $0 } }
        return data
    }
}
