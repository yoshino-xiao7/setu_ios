import AVFoundation
import Foundation
import XCTest
@testable import SetuIOSCore
@testable import SetuIOSApp

final class PlaybackContract3Tests: XCTestCase {
    override func tearDown() { MusicV2URLProtocol.handler = nil; super.tearDown() }

    func testFrozenClientBoundariesThroughResolver() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("baseline/playback-3.0.0/frozen-cases.json"))) as! [String: Any]
        for fixture in document["boundaries"] as! [[String: Any]] {
            let name = fixture["id"] as! String
            // Provider evidence provenance is server-owned and not transmitted to the client.
            if name == "non-null-without-evidence" { continue }
            let body = try JSONSerialization.data(withJSONObject: ["kind": "success", "source": fixture["value"]!])
            MusicV2URLProtocol.handler = { _ in .init(body: body, headers: ["X-Setu-Playback-Contract": "3.0.0"]) }
            let received = ISO8601DateFormatter().date(from: fixture["receivedAt"] as! String)!
            let resolver = PlaybackURLResolver(client: musicTestClient(), v2: makeMusicV2Client(), now: { received })
            var accepted = false
            do { _ = try await resolver.resolve(trackID: .canonical(.init(rawValue: "netease:track:123")), quality: .standard); accepted = true } catch {}
            XCTAssertEqual(accepted, fixture["valid"] as! Bool, name)
        }
    }

    func testMismatchedRequestedQualityCannotEnterCache() async throws {
        MusicV2URLProtocol.handler = { request in
            var root = try! JSONSerialization.jsonObject(with: typedSourceResponse(request)) as! [String: Any]
            var source = root["source"] as! [String: Any]
            source["requestedQuality"] = "lossless"; root["source"] = source
            return .init(body: try! JSONSerialization.data(withJSONObject: root), headers: ["X-Setu-Playback-Contract": "3.0.0"])
        }
        let resolver = PlaybackURLResolver(client: musicTestClient(), v2: makeMusicV2Client())
        do { _ = try await resolver.resolve(trackID: .canonical(.init(rawValue: "netease:track:1")), quality: .standard); XCTFail("Mismatched quality") } catch {}
    }

    func testRequiredNullableAndNoLegacyMixing() throws {
        let request = URLRequest(url: URL(string: "https://example.invalid/tracks/netease:track:1/playback")!)
        let data = typedSourceResponse(request)
        let decoded = try JSONDecoder().decode(MusicV2PlaybackResolution.self, from: data)
        guard case .success(let source) = decoded else { return XCTFail("success required") }
        XCTAssertNil(source.sourceExpiresAt)
        for field in ["refreshAt", "sourceExpiresAt"] {
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var body = try XCTUnwrap(root["source"] as? [String: Any])
            body.removeValue(forKey: field); root["source"] = body
            XCTAssertThrowsError(try JSONDecoder().decode(MusicV2PlaybackResolution.self, from: JSONSerialization.data(withJSONObject: root)))
        }
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var body = try XCTUnwrap(root["source"] as? [String: Any])
        body["expiresAt"] = source.refreshAt; root["source"] = body
        XCTAssertThrowsError(try JSONDecoder().decode(MusicV2PlaybackResolution.self, from: JSONSerialization.data(withJSONObject: root)))
        body.removeValue(forKey: "expiresAt"); body["refreshAt"] = NSNull(); root["source"] = body
        XCTAssertThrowsError(try JSONDecoder().decode(MusicV2PlaybackResolution.self, from: JSONSerialization.data(withJSONObject: root)))
    }

    func testExplicitNegotiationAndRejectMissingWrongOrDuplicateSelection() async throws {
        for header in [nil, "2.0.0", "3.0.0, 3.0.0", "3.0.0"] as [String?] {
            MusicV2URLProtocol.handler = { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Setu-Playback-Contract"), "3.0.0")
                return .init(body: typedSourceResponse(request), headers: header.map { ["X-Setu-Playback-Contract": $0] } ?? [:])
            }
            do {
                _ = try await makeMusicV2Client().playback(trackID: .init(rawValue: "netease:track:1"))
                XCTAssertEqual(header, "3.0.0")
            } catch { XCTAssertNotEqual(header, "3.0.0") }
        }
    }

    func testMonotonicBudgetAndWallRollbackNeverExtendReuse() {
        let clock = FreshnessTestClock()
        let received = Date(timeIntervalSince1970: 1000)
        let source = ResolvedPlaybackURL(trackID: .legacy(1), url: URL(string: "https://example.invalid/audio")!,
            effectiveLevel: "standard", resolvedAt: received, expiresAt: received.addingTimeInterval(45),
            notice: nil, usedFallback: false, uptime: { clock.value })
        XCTAssertTrue(source.isValid(at: received.addingTimeInterval(1)))
        XCTAssertFalse(source.isValid(at: received.addingTimeInterval(-1)))
        clock.set(45)
        XCTAssertFalse(source.isValid(at: received.addingTimeInterval(2)))
        XCTAssertFalse(source.isValid(at: received.addingTimeInterval(45)))
    }

    func testExpiredResolutionIsNotConsumedOrLooped() async throws {
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            let data = typedSourceResponse(request)
            var root = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            var source = root["source"] as! [String: Any]
            source["refreshAt"] = "2000-01-01T00:00:00Z"; root["source"] = source
            return .init(body: try! JSONSerialization.data(withJSONObject: root), headers: ["X-Setu-Playback-Contract": "3.0.0"])
        }
        let resolver = PlaybackURLResolver(client: musicTestClient(), v2: makeMusicV2Client())
        do { _ = try await resolver.resolve(trackID: .canonical(.init(rawValue: "netease:track:1")), quality: .standard); XCTFail("Expired") } catch {}
        XCTAssertEqual(capture.requests.count, 1)
    }

    func testFailedForcedResolutionCannotRestorePreviousCache() async throws {
        let capture = MusicV2RequestCapture()
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            if capture.requests.count == 2 {
                return .init(status: 503, body: Data(), headers: ["X-Setu-Playback-Contract": "3.0.0"])
            }
            return .init(body: typedSourceResponse(request), headers: ["X-Setu-Playback-Contract": "3.0.0"])
        }
        let resolver = PlaybackURLResolver(client: musicTestClient(), v2: makeMusicV2Client())
        let id = MusicPlaybackIdentity.canonical(.init(rawValue: "netease:track:1"))
        _ = try await resolver.resolve(trackID: id, quality: .standard)
        do { _ = try await resolver.resolve(trackID: id, quality: .standard, force: true); XCTFail("Forced failure") } catch {}
        _ = try await resolver.resolve(trackID: id, quality: .standard)
        XCTAssertEqual(capture.requests.count, 3)
    }

    func testMonotonicExpiredCacheResolvesAgainWithUnchangedWallClock() async throws {
        let capture = MusicV2RequestCapture(), clock = FreshnessTestClock()
        let now = Date()
        MusicV2URLProtocol.handler = { request in
            capture.append(request)
            var root = try! JSONSerialization.jsonObject(with: typedSourceResponse(request)) as! [String: Any]
            var source = root["source"] as! [String: Any]
            source["refreshAt"] = ISO8601DateFormatter().string(from: now.addingTimeInterval(45)); root["source"] = source
            return .init(body: try! JSONSerialization.data(withJSONObject: root), headers: ["X-Setu-Playback-Contract": "3.0.0"])
        }
        let resolver = PlaybackURLResolver(client: musicTestClient(), v2: makeMusicV2Client(), now: { now }, uptime: { clock.value })
        let id = MusicPlaybackIdentity.canonical(.init(rawValue: "netease:track:1"))
        _ = try await resolver.resolve(trackID: id, quality: .standard)
        _ = try await resolver.resolve(trackID: id, quality: .standard)
        XCTAssertEqual(capture.requests.count, 1)
        clock.set(46)
        _ = try await resolver.resolve(trackID: id, quality: .standard)
        XCTAssertEqual(capture.requests.count, 2)
    }

    @MainActor
    func testPreparedNextRechecksMonotonicExpiryAtConsumption() async throws {
        let clock = FreshnessTestClock(), now = Date()
        MusicV2URLProtocol.handler = { request in
            var root = try! JSONSerialization.jsonObject(with: typedSourceResponse(request)) as! [String: Any]
            var source = root["source"] as! [String: Any]
            source["refreshAt"] = ISO8601DateFormatter().string(from: now.addingTimeInterval(45)); root["source"] = source
            return .init(body: try! JSONSerialization.data(withJSONObject: root), headers: ["X-Setu-Playback-Contract": "3.0.0"])
        }
        let resolver = PlaybackURLResolver(client: musicTestClient(), v2: makeMusicV2Client(), now: { now }, uptime: { clock.value })
        let preparer = NextItemPreparer(makeItem: { AVPlayerItem(url: $0) })
        let id = MusicPlaybackIdentity.canonical(.init(rawValue: "netease:track:1"))
        await preparer.prepare(trackID: id, quality: .standard, resolver: resolver)
        XCTAssertNotNil(preparer.prepared)
        clock.set(46)
        XCTAssertNil(preparer.consume(trackID: id, quality: .standard, now: now))
    }

    func testKnownDeadlineCannotEqualRefresh() {
        let now = Date()
        let source = ResolvedPlaybackURL(trackID: .legacy(1), url: URL(string: "https://example.invalid/audio")!,
            effectiveLevel: "standard", resolvedAt: now, expiresAt: now.addingTimeInterval(5),
            notice: nil, usedFallback: false, sourceExpiresAt: now.addingTimeInterval(5))
        XCTAssertFalse(source.isValid(at: now))
    }
}

private final class FreshnessTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: TimeInterval = 0
    var value: TimeInterval { lock.withLock { time } }
    func set(_ time: TimeInterval) { lock.withLock { self.time = time } }
}
