import XCTest
@testable import SetuIOSCore

final class MusicPlaybackURLResolverTests: XCTestCase {
    func testBatchMatchesForwardAndReverseOrderAndMissingID() async throws {
        for ids in [[1, 2], [2, 1]] {
            let resolver = PlaybackURLResolver { _, _ in try playbackResponse(ids: ids) }
            let result = try await resolver.resolve(ids: [1, 2, 3], quality: .standard)
            XCTAssertEqual(try result[1]?.get().url.lastPathComponent, "1.wav")
            XCTAssertEqual(try result[2]?.get().url.lastPathComponent, "2.wav")
            guard case .failure = result[3] else { return XCTFail("Missing ID cannot borrow another URL") }
        }
    }

    func testCacheTTLExpiryForceAndQualityKeys() async throws {
        let clock = MusicTestClock(), counter = MusicTestCounter()
        let resolver = PlaybackURLResolver(now: { clock.now }) { ids, quality in
            _ = await counter.next()
            return try playbackResponse(ids: ids, quality: quality, expi: 30)
        }
        let first = try await resolver.resolve(trackID: 1, quality: .exhigh)
        XCTAssertEqual(first.expiresAt.timeIntervalSince(first.resolvedAt), 25)
        _ = try await resolver.resolve(trackID: 1, quality: .exhigh)
        var count = await counter.count; XCTAssertEqual(count, 1)
        clock.advance(26)
        _ = try await resolver.resolve(trackID: 1, quality: .exhigh)
        _ = try await resolver.resolve(trackID: 1, quality: .exhigh, force: true)
        _ = try await resolver.resolve(trackID: 1, quality: .lossless)
        count = await counter.count; XCTAssertEqual(count, 4)
    }

    func testBatchFallbackOnlyRequestsUnavailableIDAndStrictQualityDoesNotUseFallbackCache() async throws {
        let calls = PlaybackRequestLog()
        let resolver = PlaybackURLResolver { ids, quality in
            await calls.append(ids, quality)
            if quality == .exhigh { return try playbackResponse(ids: ids, quality: quality, unavailable: [2]) }
            return try playbackResponse(ids: ids, quality: quality)
        }
        let result = try await resolver.resolve(ids: [1, 2], quality: .exhigh)
        XCTAssertEqual(try result[1]?.get().effectiveLevel, "exhigh")
        XCTAssertEqual(try result[2]?.get().effectiveLevel, "standard")
        let entries = await calls.entries
        XCTAssertEqual(entries.map(\.0), [[1, 2], [2]])
        do {
            _ = try await resolver.resolve(trackID: 2, quality: .exhigh, allowsFallback: false)
            XCTFail("Explicit quality must not accept standard fallback")
        } catch is UserFacingError {} catch { XCTFail("\(error)") }
    }

    func testVIPTrialAndCopyrightAreNotRetried() async throws {
        for marker in ["VIP", "TRIAL", "REGION_RESTRICTED"] {
            let counter = MusicTestCounter()
            let resolver = PlaybackURLResolver { _, _ in
                _ = await counter.next()
                return try JSONDecoder().decode(MusicUrlResponse.self, from: Data("{\"data\":[{\"id\":1,\"playability\":\"\(marker)\",\"fullPlayable\":false}]}".utf8))
            }
            do { _ = try await resolver.resolve(trackID: 1, quality: .exhigh); XCTFail("Restricted song") } catch {}
            let count = await counter.count; XCTAssertEqual(count, 1)
        }
    }

    func testNetworkFailureFallbackAndFailureDoesNotPoisonCache() async throws {
        let counter = MusicTestCounter()
        let resolver = PlaybackURLResolver { ids, quality in
            let call = await counter.next()
            if call <= 2 { throw URLError(.notConnectedToInternet) }
            return try playbackResponse(ids: ids, quality: quality)
        }
        do { _ = try await resolver.resolve(trackID: 1, quality: .exhigh); XCTFail("Offline") } catch {}
        let recovered = try await resolver.resolve(trackID: 1, quality: .exhigh)
        XCTAssertEqual(recovered.trackID, 1)
        let count = await counter.count; XCTAssertEqual(count, 3)
    }

    func testConcurrentBatchAndSingleShareRequests() async throws {
        let gate = MusicTestGate(), counter = MusicTestCounter()
        let started = expectation(description: "batch request")
        let resolver = PlaybackURLResolver { ids, quality in
            _ = await counter.next(); started.fulfill(); await gate.wait()
            return try playbackResponse(ids: ids, quality: quality)
        }
        let batch = Task { try await resolver.resolve(ids: [1, 2], quality: .exhigh) }
        await fulfillment(of: [started], timeout: 2)
        let single = Task { try await resolver.resolve(trackID: 2, quality: .exhigh) }
        await gate.open()
        _ = try await batch.value
        let value = try await single.value
        XCTAssertEqual(value.trackID, 2)
        let count = await counter.count; XCTAssertEqual(count, 1)
    }

    func testResetRejectsOldResponseAndCancelledWaiterDoesNotBreakOtherConsumer() async throws {
        let gate = MusicTestGate(), started = expectation(description: "started")
        let resolver = PlaybackURLResolver { ids, quality in
            started.fulfill(); await gate.wait(); return try playbackResponse(ids: ids, quality: quality)
        }
        let old = Task { try await resolver.resolve(trackID: 1, quality: .exhigh) }
        await fulfillment(of: [started], timeout: 2)
        await resolver.reset(); await gate.open()
        do { _ = try await old.value; XCTFail("Old session") } catch is CancellationError {} catch { XCTFail("\(error)") }

        let gate2 = MusicTestGate(), started2 = expectation(description: "shared")
        let shared = PlaybackURLResolver { ids, quality in
            started2.fulfill(); await gate2.wait(); return try playbackResponse(ids: ids, quality: quality)
        }
        let cancelled = Task { try await shared.resolve(trackID: 2, quality: .exhigh) }
        await fulfillment(of: [started2], timeout: 2)
        cancelled.cancel(); await gate2.open()
        do { _ = try await cancelled.value; XCTFail("Cancelled consumer") } catch is CancellationError {} catch { XCTFail("\(error)") }
        let cached = try await shared.resolve(trackID: 2, quality: .exhigh)
        XCTAssertEqual(cached.trackID, 2)
    }
}

actor PlaybackRequestLog {
    private(set) var entries: [([Int], MusicAudioQuality)] = []
    func append(_ ids: [Int], _ quality: MusicAudioQuality) { entries.append((ids, quality)) }
}

func playbackResponse(ids: [Int], quality: MusicAudioQuality = .exhigh, expi: Int = 600,
                      unavailable: Set<Int> = [], url: URL? = nil) throws -> MusicUrlResponse {
    let data: [[String: Any]] = ids.map { id in
        ["id": id, "url": (url ?? URL(fileURLWithPath: "/tmp/\(id).wav")).absoluteString,
         "level": quality.rawValue, "expi": expi,
         "fullPlayable": !unavailable.contains(id), "playability": unavailable.contains(id) ? "UNAVAILABLE" : "FULL"]
    }
    return try JSONDecoder().decode(MusicUrlResponse.self, from: JSONSerialization.data(withJSONObject: ["data": data]))
}
