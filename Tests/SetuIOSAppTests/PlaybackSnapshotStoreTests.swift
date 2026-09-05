import Foundation
import XCTest
@testable import SetuIOSApp

@MainActor
final class PlaybackSnapshotStoreTests: XCTestCase {
    private struct LegacySnapshot: Codable {
        let userID: Int
        let track: MusicPlaybackTrack
        let queueName: String?
        let queueTracks: [MusicPlaybackTrack]
        let currentQueueIndex: Int?
        let currentTimeSeconds: Double
        let playMode: MusicPlayMode
        let updatedAt: Date
    }

    private func track(_ id: Int = 7) -> MusicPlaybackTrack {
        MusicPlaybackTrack(id: id, title: "Song", artist: "Artist", album: "Album", coverURLString: nil, durationMilliseconds: 120_000, mvID: nil)
    }

    private func snapshot(userID: Int, trackID: Int, at date: Date) -> PlaybackSnapshotStore.Snapshot {
        PlaybackSnapshotStore.Snapshot(
            userID: userID,
            track: track(trackID),
            context: .singleTrack(trackID: .canonical(.init(rawValue: "track:\(trackID)")), label: nil),
            queueTracks: [track(trackID)],
            currentQueueIndex: 0,
            currentTimeSeconds: 0,
            playMode: .sequence,
            updatedAt: date
        )
    }

    func testLegacyQueueNameMigratesToUnknownContextWithoutInferringSource() throws {
        let suite = "snapshot-legacy-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacy = LegacySnapshot(userID: 9, track: track(), queueName: "旧队列", queueTracks: [track()], currentQueueIndex: 0, currentTimeSeconds: 4, playMode: .loop, updatedAt: Date())
        defaults.set(try JSONEncoder().encode(legacy), forKey: PlaybackSnapshotStore.snapshotKey(userID: 9))
        let restored = try XCTUnwrap(PlaybackSnapshotStore(enabled: true, preferences: defaults).restore(for: 9))
        XCTAssertEqual(restored.context, .unknown(reason: .legacySnapshot, label: "旧队列"))
        XCTAssertEqual(restored.currentQueueIndex, 0)
        XCTAssertEqual(restored.playMode, .loop)
    }

    func testCorruptSnapshotsAreDiscarded() throws {
        let suite = "snapshot-invalid-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = PlaybackSnapshotStore.snapshotKey(userID: 2)
        defaults.set(Data("bad".utf8), forKey: key)
        XCTAssertNil(PlaybackSnapshotStore(enabled: true, preferences: defaults).restore(for: 2))
        XCTAssertNil(defaults.data(forKey: key))
    }

    func testWrongOwnerSnapshotIsDiscarded() throws {
        let suite = "snapshot-owner-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = PlaybackSnapshotStore.snapshotKey(userID: 2)
        let wrongOwner = PlaybackSnapshotStore.Snapshot(
            userID: 1,
            track: track(),
            context: .singleTrack(trackID: .canonical(.init(rawValue: "track:7")), label: nil),
            queueTracks: [track()],
            currentQueueIndex: 0,
            currentTimeSeconds: 0,
            playMode: .sequence,
            updatedAt: Date()
        )
        defaults.set(try JSONEncoder().encode(wrongOwner), forKey: key)

        XCTAssertNil(PlaybackSnapshotStore(enabled: true, preferences: defaults).restore(for: 2))
        XCTAssertNil(defaults.data(forKey: key))
    }

    func testPerUserWritesRemainIsolated() async throws {
        let suite = "snapshot-users-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlaybackSnapshotStore(enabled: true, preferences: defaults)
        for userID in [1, 2] {
            let value = PlaybackSnapshotStore.Snapshot(userID: userID, track: track(userID), context: .singleTrack(trackID: .canonical(.init(rawValue: "track:\(userID)")), label: nil), queueTracks: [track(userID)], currentQueueIndex: 0, currentTimeSeconds: 0, playMode: .sequence, updatedAt: Date())
            store.save(value)
        }
        await store.waitForWrites()
        XCTAssertEqual(store.restore(for: 1)?.track.id, 1)
        XCTAssertEqual(store.restore(for: 2)?.track.id, 2)
    }

    func testThrottledWritesAreLimitedPerUserAndImmediateWriteBypassesThrottle() async throws {
        let suite = "snapshot-throttle-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var currentDate = Date(timeIntervalSince1970: 100)
        let store = PlaybackSnapshotStore(enabled: true, preferences: defaults, now: { currentDate })

        store.save(snapshot(userID: 1, trackID: 1, at: currentDate), throttled: true)
        await store.waitForWrites()
        currentDate.addTimeInterval(1)
        store.save(snapshot(userID: 1, trackID: 2, at: currentDate), throttled: true)
        store.save(snapshot(userID: 2, trackID: 3, at: currentDate), throttled: true)
        await store.waitForWrites()
        XCTAssertEqual(store.restore(for: 1)?.track.id, 1, "Same-owner progress writes are throttled for 15 seconds")
        XCTAssertEqual(store.restore(for: 2)?.track.id, 3, "One owner's throttle must not suppress a new owner's snapshot")

        store.save(snapshot(userID: 1, trackID: 4, at: currentDate))
        await store.waitForWrites()
        XCTAssertEqual(store.restore(for: 1)?.track.id, 4, "Stop and explicit saves bypass progress throttling")

        currentDate.addTimeInterval(15)
        store.save(snapshot(userID: 1, trackID: 5, at: currentDate), throttled: true)
        await store.waitForWrites()
        XCTAssertEqual(store.restore(for: 1)?.track.id, 5)
    }
}
