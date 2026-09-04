import Foundation
import XCTest
@testable import SetuIOSCore

final class MusicV2ContractDecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testOpaqueIDsNeverPassThroughNumber() throws {
        let huge = "netease:track:900719925474099312345678901234567890"
        let id = try decoder.decode(MusicV2TrackID.self, from: Data("\"\(huge)\"".utf8))
        XCTAssertEqual(id.rawValue, huge)
        XCTAssertEqual(try JSONEncoder().encode(id), Data("\"\(huge)\"".utf8))
    }

    func testRequiredNullableRejectsMissingButAcceptsNull() throws {
        let explicitNull = #"{"name":"Unknown artist","id":null,"artwork":null}"#
        let decoded = try decoder.decode(MusicV2ArtistBrief.self, from: Data(explicitNull.utf8))
        XCTAssertNil(decoded.id)
        XCTAssertThrowsError(try decoder.decode(MusicV2ArtistBrief.self, from: Data(#"{"name":"Unknown artist","artwork":null}"#.utf8)))
    }

    func testNullableLibraryProjectionAndExactPaginationDecode() throws {
        let body = #"{"items":[{"ownerId":"setu:user:opaque","trackId":"netease:track:1","likedAt":"2026-09-03T08:00:00Z","track":null}],"offset":20,"limit":20,"hasMore":true,"total":41,"nextOffset":40}"#
        let page = try decoder.decode(MusicV2LikedPage.self, from: Data(body.utf8))
        XCTAssertNil(page.items[0].track)
        XCTAssertEqual(page.total, 41)
        XCTAssertEqual(page.nextOffset, 40)
        XCTAssertEqual(page.offset, 20)
    }

    func testUnknownEnumsAndDiscriminatorsCannotBecomePlayableSuccess() throws {
        let availability = try decoder.decode(
            MusicV2TrackAvailability.self,
            from: Data(#"{"status":"futureStatus","reason":"future","maxQuality":null}"#.utf8)
        )
        XCTAssertEqual(availability.status, .unrecognized("futureStatus"))

        let resolution = try decoder.decode(
            MusicV2PlaybackResolution.self,
            from: Data(#"{"kind":"futurePlayback","url":"https://must-not-play.test"}"#.utf8)
        )
        XCTAssertEqual(resolution, .unsupported(kind: "futurePlayback"))
    }

    func testUnknownHomeSectionIsSkippedButKnownMalformedSectionFails() throws {
        let unknown = #"{"generatedAt":"2026-09-03T08:00:00Z","sections":[{"id":"future","kind":"futureSection","payload":{"secret":"ignored"}}]}"#
        XCTAssertEqual(try decoder.decode(MusicV2HomeFeed.self, from: Data(unknown.utf8)).sections, [])

        let malformedKnown = #"{"generatedAt":"2026-09-03T08:00:00Z","sections":[{"id":"daily","kind":"dailyTracks","title":"Daily","items":[{"kind":"track"}],"degraded":false,"subtitle":null,"source":null,"action":null}]}"#
        XCTAssertThrowsError(try decoder.decode(MusicV2HomeFeed.self, from: Data(malformedKnown.utf8)))
    }

    func testSearchUnknownSectionIsSkippedAndFailedStatePreservesMusicError() throws {
        let body = #"{"query":"q","scope":"all","sections":[{"scope":"future","status":"loaded","items":{},"error":null},{"scope":"tracks","status":"failed","items":null,"error":{"code":"UPSTREAM_RATE_LIMITED","message":"later","retryable":true,"traceId":null}}],"best":null}"#
        let result = try decoder.decode(MusicV2SearchResult.self, from: Data(body.utf8))
        XCTAssertEqual(result.sections.count, 1)
        guard case .failed(let scope, let error) = result.sections[0] else { return XCTFail("Expected failed section") }
        XCTAssertEqual(scope, .tracks)
        XCTAssertEqual(error.code, .upstreamRateLimited)
    }
}

final class MusicFeatureRoutingTests: XCTestCase {
    func testEveryFeatureDefaultsFalse() {
        let flags = MusicFeatureFlags()
        let routes: [MusicFeatureRoute] = [.search, .playback, .lyrics, .home, .playlistDetail, .artistDetail, .albumDetail, .rankings, .newReleases, .radioFM, .likedTracks, .favoritePlaylists, .wordByWordLyrics, .airPlayPicker]
        XCTAssertTrue(routes.allSatisfy { !flags.isEnabled($0) })
    }

    func testFalseUsesLegacyOnlyAndTrueUsesV2Only() async throws {
        let counter = RouteCounter()
        let off = try await MusicDataLayerRouter(flags: .init()).value(for: .search) {
            await counter.legacy(); return "v1"
        } v2: {
            await counter.v2(); return "v2"
        }
        XCTAssertEqual(off, "v1")

        var enabled = MusicFeatureFlags(); enabled.usesV2Search = true
        let on = try await MusicDataLayerRouter(flags: enabled).value(for: .search) {
            await counter.legacy(); return "v1"
        } v2: {
            await counter.v2(); return "v2"
        }
        XCTAssertEqual(on, "v2")
        let counts = await counter.counts
        XCTAssertEqual(counts.legacy, 1); XCTAssertEqual(counts.v2, 1)
    }
}

private actor RouteCounter {
    private var legacyCount = 0, v2Count = 0
    func legacy() { legacyCount += 1 }
    func v2() { v2Count += 1 }
    var counts: (legacy: Int, v2: Int) { (legacyCount, v2Count) }
}
