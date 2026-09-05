import XCTest
@testable import SetuIOSApp
@testable import SetuIOSCore

@MainActor
final class RadioFMFeederTests: XCTestCase {
    private func batch(empty: Bool = false) throws -> MusicV2RadioBatch {
        try JSONDecoder().decode(MusicV2RadioBatch.self, from: Data("{\"tracks\":[\(empty ? "" : MusicV2Fixtures.track)],\"source\":\(MusicV2Fixtures.source)}".utf8))
    }

    func testThresholdAndSingleFlight() async throws {
        let value = try batch()
        var requests = 0, deliveries = 0
        var release: CheckedContinuation<Void, Never>?
        let feeder = RadioFMFeeder(fetch: {
            requests += 1
            await withCheckedContinuation { release = $0 }
            return value
        })
        feeder.refill(remaining: 2, receive: { _ in XCTFail() }, failure: { _ in XCTFail() })
        await Task.yield()
        XCTAssertEqual(requests, 0)
        feeder.refill(remaining: 1, receive: { _ in deliveries += 1 }, failure: { _ in XCTFail() })
        while release == nil { await Task.yield() }
        feeder.refill(remaining: 0, receive: { _ in XCTFail() }, failure: { _ in XCTFail() })
        XCTAssertEqual(requests, 1)
        release?.resume()
        await feeder.waitForRefill()
        XCTAssertEqual(deliveries, 1)
        feeder.stop()
    }

    func testStopRejectsTransportIgnoringCancellation() async throws {
        let value = try batch()
        var release: CheckedContinuation<Void, Never>?
        let feeder = RadioFMFeeder(fetch: {
            await withCheckedContinuation { release = $0 }
            return value
        })
        feeder.refill(remaining: 0, receive: { _ in XCTFail("Late batch") }, failure: { _ in XCTFail() })
        while release == nil { await Task.yield() }
        feeder.stop()
        release?.resume()
        for _ in 0..<10 { await Task.yield() }
        feeder.refill(remaining: 0, receive: { _ in XCTFail() }, failure: { _ in XCTFail() })
    }

    func testEmptyBatchRetriesBoundedlyAndCanRetryLater() async throws {
        let empty = try batch(empty: true)
        var requests = 0, failures = 0
        let sleeps = RadioSleepRecorder()
        let feeder = RadioFMFeeder(fetch: { requests += 1; return empty }, sleep: { await sleeps.record($0) })
        feeder.refill(remaining: 0, receive: { _ in XCTFail() }, failure: { XCTAssertNil($0); failures += 1 })
        await feeder.waitForRefill()
        XCTAssertEqual(requests, 4)
        XCTAssertEqual(failures, 1)
        let delays = await sleeps.values
        XCTAssertEqual(delays, [1_000_000_000, 2_000_000_000, 4_000_000_000])
        feeder.refill(remaining: 0, receive: { _ in XCTFail() }, failure: { _ in failures += 1 })
        await feeder.waitForRefill()
        XCTAssertEqual(requests, 8)
    }

    func testFailureRetriesAndSuccessPreservesRepeatedTracks() async throws {
        let value = try batch()
        var requests = 0
        let feeder = RadioFMFeeder(fetch: {
            requests += 1
            if requests < 4 { throw URLError(.timedOut) }
            return value
        }, sleep: { _ in })
        var received: MusicV2RadioBatch?
        feeder.refill(remaining: 1, receive: { received = $0 }, failure: { _ in XCTFail() })
        await feeder.waitForRefill()
        XCTAssertEqual(requests, 4)
        XCTAssertEqual(received, value)
    }

    func testTrimPreservesCurrentAndBoundsNormalRefills() {
        XCTAssertEqual(RadioFMFeeder.trimCount(count: 49, currentIndex: 47), 0)
        XCTAssertEqual(RadioFMFeeder.trimCount(count: 54, currentIndex: 48), 4)
        XCTAssertEqual(RadioFMFeeder.trimCount(count: 54, currentIndex: 1), 1)
    }

    func testRadioCapabilitiesAndModeAreEnforcedAtControllerBoundary() async throws {
        let remote = RemoteCommandCoordinator()
        let controller = MusicPlaybackController(persistsPlayback: false, remoteCommandCoordinator: remote)
        let tracks = try playbackTracks(), url = try playbackWave()
        defer { controller.stop(); try? FileManager.default.removeItem(at: url) }
        controller.play(url: url, track: tracks[1], context: .radio(sessionID: "test", source: .sharedAlgorithmic(), label: nil), queueTracks: tracks, playMode: .random)
        XCTAssertFalse(controller.canPlayPrevious)
        XCTAssertFalse(remote.previousEnabled)
        XCTAssertFalse(try XCTUnwrap(controller.context).allowsQueueEdit)
        XCTAssertEqual(controller.playMode, .sequence)
        controller.setPlayMode(.loop)
        XCTAssertEqual(controller.playMode, .sequence)
        await controller.userSkip(by: -1)
        XCTAssertEqual(controller.currentQueueIndex, 1)
        controller.clearUpcomingTracks()
        controller.removeQueuedTrack(tracks[2])
        controller.moveQueueTracks(from: [0], to: 3)
        XCTAssertEqual(controller.queueTracks.map(\.id), tracks.map(\.id))
    }

    func testControllerRefillBlockAndLeavingRadio() async throws {
        let capture = MusicV2RequestCapture()
        let batch = try self.batch()
        let body = try JSONEncoder().encode(batch)
        MusicV2URLProtocol.handler = { request in
            if request.url?.path == "/user/music/v2/radio/fm" {
                capture.append(request)
                return .init(status: 200, body: body)
            }
            if request.url?.path == "/user/music/v2/radio/fm/block" {
                return .init(status: 204, body: Data())
            }
            return MusicV2Fixtures.response(for: request)
        }
        defer { MusicV2URLProtocol.handler = nil }
        let controller = MusicPlaybackController(persistsPlayback: false)
        defer { controller.stop() }
        controller.startRadio(client: makeMusicV2Client())
        await controller.waitForRadioRefill()
        XCTAssertEqual(capture.requests.count, 1)
        XCTAssertEqual(controller.queueTracks.count, 1)
        let track = try XCTUnwrap(controller.currentTrack)
        await controller.blockRadioTrack(track)
        await controller.waitForRadioRefill()
        XCTAssertTrue(controller.queueTracks.isEmpty)
        let tracks = try playbackTracks(), url = try playbackWave()
        defer { try? FileManager.default.removeItem(at: url) }
        controller.play(url: url, track: tracks[0], queueTracks: tracks)
        let before = capture.requests.count
        controller.retryRadio()
        await controller.waitForRadioRefill()
        XCTAssertEqual(capture.requests.count, before)
        XCTAssertFalse(try XCTUnwrap(controller.context).isInfinite)
    }

    func testRadioRouteRequiresExplicitFixtureFlag() {
        let action = MusicV2HomeAction.discovery(selection: "radio", label: nil)
        var flags = MusicFeatureFlags()
        XCTAssertNil(MusicDiscoverRoutes.route(action, flags: flags))
        flags.radioFMEnabled = true
        XCTAssertEqual(MusicDiscoverRoutes.route(action, flags: flags), .radioFM)
    }
}

private actor RadioSleepRecorder {
    var values: [UInt64] = []
    func record(_ value: UInt64) { values.append(value) }
}
