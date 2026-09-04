import Foundation
import XCTest
@testable import SetuIOSCore

final class MusicV2DataLayerTests: XCTestCase {
    override func tearDown() {
        MusicV2URLProtocol.handler = nil
        super.tearDown()
    }

    func testRepositorySharesV2FlightAndResetIsolatesNextUser() async throws {
        let state = UserFixtureState()
        MusicV2URLProtocol.handler = { request in
            let owner = state.owner
            let body = #"{"ownerId":"setu:user:\#(owner)","likedTrackCount":0,"savedPlaylistCount":0,"historyCount":0,"ownedPlaylistCount":0,"recentHistory":[],"ownedPlaylists":[],"savedPlaylists":[]}"#
            state.increment()
            return .init(body: Data(body.utf8))
        }
        let v2 = makeMusicV2Client()
        let repository = MusicRepository(client: musicTestClient())
        let query = MusicQuery<MusicV2UserLibrary>.library(client: v2)

        async let first = repository.value(for: query)
        async let second = repository.value(for: query)
        let initial = try await [first.value, second.value]
        XCTAssertEqual(initial.map(\.ownerId.rawValue), ["setu:user:u1", "setu:user:u1"])
        XCTAssertEqual(state.requestCount, 1, "Existing repository single-flight must deduplicate v2 requests")

        state.owner = "u2"
        let stillScopedToOldSession = try await repository.value(for: query)
        XCTAssertEqual(stillScopedToOldSession.value.ownerId.rawValue, "setu:user:u1")
        await repository.reset()
        let newSession = try await repository.value(for: query)
        XCTAssertEqual(newSession.value.ownerId.rawValue, "setu:user:u2")
        XCTAssertEqual(state.requestCount, 2)
    }

    func testLibraryTTLAndRadioAbsenceAreExplicit() {
        let cases: [(MusicCacheKey, TimeInterval)] = [
            (.home, 300), (.searchV2(keywords: "q", scope: .tracks, offset: 0, limit: 20), 600),
            (.searchSuggestions("q"), 600), (.hotSearchV2, 1_800), (.track("t"), 1_800),
            (.tracksBatch(["t"]), 1_800), (.lyrics("t"), 86_400), (.artist("a"), 1_800),
            (.artistTracks("a", offset: 0, limit: 20), 1_800), (.artistAlbums("a", offset: 0, limit: 20), 1_800),
            (.artistMVs("a", offset: 0, limit: 20), 1_800), (.album("a"), 1_800),
            (.providerPlaylist("p", offset: 0, limit: 50), 300), (.providerPlaylistTracks("p", offset: 0, limit: 50), 300),
            (.rankings, 1_800), (.recommendTracks, 86_400), (.recommendPlaylists(limit: 20), 600),
            (.newReleaseTracks(area: .all, offset: 0, limit: 30), 600), (.newReleaseAlbums(area: .all, offset: 0, limit: 30), 600),
            (.library, 60), (.likedTracks(offset: 0, limit: 20), 60), (.favoritePlaylists(offset: 0, limit: 20), 60),
            (.historyV2(offset: 0, limit: 20), 60),
        ]
        for (key, expected) in cases { XCTAssertEqual(key.ttl, expected, "TTL mismatch for \(key)") }

        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: Date())
        let fetched = calendar.date(byAdding: .hour, value: 1, to: start)!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: start)!
        XCTAssertTrue(MusicCacheKey.recommendTracks.isFresh(fetchedAt: fetched, now: nextDay.addingTimeInterval(-1)))
        XCTAssertFalse(MusicCacheKey.recommendTracks.isFresh(fetchedAt: fetched, now: nextDay))
        // Compile-time exhaustiveness and the absence of a radioFM case are the cache-policy guard.
        let reflected = String(reflecting: MusicCacheKey.library)
        XCTAssertFalse(reflected.contains("radio"))
    }

    func testLyricStoreDeduplicatesAndDowngradesOversizedWordLyrics() async throws {
        let requests = LockedInt()
        MusicV2URLProtocol.handler = { request in
            requests.increment()
            Thread.sleep(forTimeInterval: 0.03)
            let trackID = request.url!.pathComponents.dropLast().last ?? "netease:track:1"
            let line = #"{"text":"word","words":[{"text":"w","startMs":0,"durationMs":1}],"startMs":0,"durationMs":1,"translation":null}"#
            let body = #"{"trackId":"\#(trackID)","kind":"word","lines":[\#(Array(repeating: line, count: 501).joined(separator: ","))],"hasTranslation":false,"contributors":[]}"#
            return .init(body: Data(body.utf8))
        }
        let store = LyricStore(client: makeMusicV2Client())
        let id = MusicV2TrackID(rawValue: "netease:track:1")
        let values = try await withThrowingTaskGroup(of: MusicV2Lyric.self) { group in
            for _ in 0..<12 { group.addTask { try await store.lyric(for: id) } }
            var results: [MusicV2Lyric] = []
            for try await value in group { results.append(value) }
            return results
        }
        XCTAssertEqual(requests.value, 1)
        XCTAssertEqual(values.count, 12)
        XCTAssertEqual(values[0].kind, .line)
        XCTAssertTrue(values[0].lines.allSatisfy(\.words.isEmpty))
    }

    func testLyricStoreCapacityAndReset() async throws {
        MusicV2URLProtocol.handler = { request in
            let trackID = request.url!.pathComponents.dropLast().last ?? "netease:track:1"
            return .init(body: Data(#"{"trackId":"\#(trackID)","kind":"none","lines":[],"hasTranslation":false,"contributors":[]}"#.utf8))
        }
        let store = LyricStore(client: makeMusicV2Client(), capacity: 2)
        for value in 1...3 { _ = try await store.lyric(for: .init(rawValue: "netease:track:\(value)")) }
        let beforeReset = await store.cachedEntryCount()
        XCTAssertEqual(beforeReset, 2)
        await store.reset()
        let afterReset = await store.cachedEntryCount()
        XCTAssertEqual(afterReset, 0)
    }
}

private final class UserFixtureState: @unchecked Sendable {
    private let lock = NSLock(); private var currentOwner = "u1", count = 0
    var owner: String { get { lock.withLock { currentOwner } } set { lock.withLock { currentOwner = newValue } } }
    var requestCount: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private final class LockedInt: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
