import Foundation

@MainActor
final class PlaybackSnapshotStore {
    struct Snapshot: Codable, Sendable {
        let userID: Int
        let track: MusicPlaybackTrack
        let context: PlaybackContext
        let queueTracks: [MusicPlaybackTrack]
        let currentQueueIndex: Int?
        let currentTimeSeconds: Double
        let playMode: MusicPlayMode
        let updatedAt: Date
    }

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

    static let legacySnapshotKey = "icu.yukiryou.setu.musicPlaybackSnapshot"
    static let audioQualityKey = "icu.yukiryou.setu.musicAudioQuality"

    private let preferences: UserDefaults
    private let enabled: Bool
    private let now: () -> Date
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var revisions: [Int: UUID] = [:]
    private var lastWriteDates: [Int: Date] = [:]
    private(set) var userID: Int?

    init(enabled: Bool, preferences: UserDefaults, now: @escaping () -> Date = Date.init) {
        self.enabled = enabled
        self.preferences = preferences
        self.now = now
    }

    deinit {
        for task in tasks.values { task.cancel() }
    }

    static func snapshotKey(userID: Int) -> String {
        "\(legacySnapshotKey).user.\(userID)"
    }

    func setUserID(_ userID: Int?) {
        guard enabled else { return }
        self.userID = userID
        preferences.removeObject(forKey: Self.legacySnapshotKey)
    }

    func restore(for userID: Int) -> Snapshot? {
        guard enabled else { return nil }
        self.userID = userID
        let key = Self.snapshotKey(userID: userID)
        guard let data = preferences.data(forKey: key) else { return nil }
        if let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data), snapshot.userID == userID {
            return snapshot
        }
        if let legacy = try? JSONDecoder().decode(LegacySnapshot.self, from: data), legacy.userID == userID {
            return Snapshot(
                userID: legacy.userID,
                track: legacy.track,
                context: .unknown(reason: .legacySnapshot, label: legacy.queueName),
                queueTracks: legacy.queueTracks,
                currentQueueIndex: legacy.currentQueueIndex,
                currentTimeSeconds: legacy.currentTimeSeconds,
                playMode: legacy.playMode,
                updatedAt: legacy.updatedAt
            )
        }
        preferences.removeObject(forKey: key)
        return nil
    }

    func save(_ snapshot: Snapshot, throttled: Bool = false) {
        guard enabled else { return }
        let writeDate = now()
        let targetUserID = snapshot.userID
        if throttled,
           let lastWriteDate = lastWriteDates[targetUserID],
           writeDate.timeIntervalSince(lastWriteDate) < 15 {
            return
        }
        lastWriteDates[targetUserID] = writeDate
        tasks[targetUserID]?.cancel()
        let revision = UUID()
        revisions[targetUserID] = revision
        tasks[targetUserID] = Task { [weak self] in
            let data = await Task.detached(priority: .utility) { try? JSONEncoder().encode(snapshot) }.value
            guard let self, self.revisions[targetUserID] == revision, !Task.isCancelled, let data else { return }
            self.preferences.set(data, forKey: Self.snapshotKey(userID: targetUserID))
            self.tasks[targetUserID] = nil
        }
    }

    func clear(userID explicitUserID: Int? = nil) {
        guard enabled, let targetUserID = explicitUserID ?? userID else { return }
        lastWriteDates[targetUserID] = nil
        revisions[targetUserID] = UUID()
        tasks[targetUserID]?.cancel()
        tasks[targetUserID] = nil
        preferences.removeObject(forKey: Self.snapshotKey(userID: targetUserID))
    }

    func waitForWrites() async {
        for task in tasks.values { await task.value }
    }

    func cancelPendingWrites() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
    }
}
