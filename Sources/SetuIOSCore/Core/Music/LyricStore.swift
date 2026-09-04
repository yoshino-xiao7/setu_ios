import Foundation

/// Session-owned structured lyric cache. UI progress ticks consume the decoded value and never
/// reparse it. A caller must reset the store when its authenticated Setu session changes.
public actor LyricStore {
    private struct Entry: Sendable {
        let lyric: MusicV2Lyric
        let fetchedAt: Date
        var access: UInt64
    }

    private let client: MusicV2Client
    private let now: @Sendable () -> Date
    private let capacity: Int
    private let ttl: TimeInterval
    private var access: UInt64 = 0
    private var entries: [MusicV2TrackID: Entry] = [:]
    private var flights: [MusicV2TrackID: Task<MusicV2Lyric, Error>] = [:]

    public init(
        client: MusicV2Client,
        now: @escaping @Sendable () -> Date = { Date() },
        capacity: Int = 32,
        ttl: TimeInterval = 24 * 60 * 60
    ) {
        self.client = client
        self.now = now
        self.capacity = max(1, capacity)
        self.ttl = max(0, ttl)
    }

    public func lyric(for trackID: MusicV2TrackID, force: Bool = false) async throws -> MusicV2Lyric {
        if !force, var entry = entries[trackID], now().timeIntervalSince(entry.fetchedAt) < ttl {
            access &+= 1; entry.access = access; entries[trackID] = entry
            return entry.lyric
        }
        let task: Task<MusicV2Lyric, Error>
        if let existing = flights[trackID] { task = existing }
        else {
            let client = client
            task = Task { try await client.lyrics(trackID: trackID) }
            flights[trackID] = task
        }
        defer { flights[trackID] = nil }
        let fetched = try await task.value
        let normalized = Self.storageForm(fetched)
        access &+= 1
        entries[trackID] = Entry(lyric: normalized, fetchedAt: now(), access: access)
        while entries.count > capacity, let victim = entries.min(by: { $0.value.access < $1.value.access })?.key {
            entries[victim] = nil
        }
        return normalized
    }

    public func reset() {
        entries.removeAll()
        for task in flights.values { task.cancel() }
        flights.removeAll()
    }

    #if DEBUG
    func cachedEntryCount() -> Int { entries.count }
    #endif

    private static func storageForm(_ lyric: MusicV2Lyric) -> MusicV2Lyric {
        guard lyric.lines.count > 500, lyric.lines.contains(where: { !$0.words.isEmpty }) else { return lyric }
        let lines = lyric.lines.map {
            MusicV2LyricLine(text: $0.text, words: [], startMs: $0.startMs, durationMs: $0.durationMs, translation: $0.translation)
        }
        return MusicV2Lyric(trackId: lyric.trackId, kind: .line, lines: lines, hasTranslation: lyric.hasTranslation, contributors: lyric.contributors)
    }
}
