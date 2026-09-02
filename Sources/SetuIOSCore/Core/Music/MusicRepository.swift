import Foundation

public enum MusicCacheKey: Hashable, Sendable {
    case hotSearch, recommendedPlaylists, newSongs, dailySongs, playlists, historyCount
    case playlist(Int), recommendedTracks(Int), history(limit: Int, offset: Int)

    case search(keywords: String, offset: Int, limit: Int)

    public var ttl: TimeInterval {
        switch self {
        case .hotSearch, .dailySongs: return 30 * 60
        case .recommendedPlaylists, .newSongs, .recommendedTracks, .search: return 10 * 60
        case .playlists, .playlist: return 5 * 60 // SWR fallback for changes from another device.
        case .history, .historyCount: return 60
        }
    }
}

/// A typed endpoint keeps cache keys and decoded value types together.
public struct MusicQuery<Value: Sendable>: Sendable {
    public let key: MusicCacheKey
    let fetch: @Sendable (MusicClient) async throws -> Value

    init(key: MusicCacheKey, fetch: @escaping @Sendable (MusicClient) async throws -> Value) {
        self.key = key
        self.fetch = fetch
    }
}

public extension MusicQuery where Value == [MusicHotSearchItem] {
    static var hotSearch: Self { .init(key: .hotSearch) { try await $0.hotSearch().result.hots } }
}
public extension MusicQuery where Value == [MusicRecommendedPlaylist] {
    static var recommendedPlaylists: Self { .init(key: .recommendedPlaylists) { try await $0.personalizedPlaylists(limit: 6).result } }
}
public extension MusicQuery where Value == [MusicSong] {
    static var newSongs: Self { .init(key: .newSongs) { try await $0.personalizedNewSongs().result } }
    static var dailySongs: Self { .init(key: .dailySongs) { try await $0.recommendSongs().data.dailySongs } }
    static func recommendedTracks(_ id: Int) -> Self {
        .init(key: .recommendedTracks(id)) { try await $0.playlistTracks(id: id).songs }
    }
}
public extension MusicQuery where Value == [UserMusicPlaylist] {
    static var playlists: Self { .init(key: .playlists) { try await $0.playlists() } }
}
public extension MusicQuery where Value == UserMusicPlaylistDetail {
    static func playlist(_ id: Int) -> Self { .init(key: .playlist(id)) { try await $0.playlist(id: id) } }
}
public extension MusicQuery where Value == [MusicHistoryRecord] {
    static func history(limit: Int, offset: Int = 0) -> Self {
        .init(key: .history(limit: limit, offset: offset)) { try await $0.history(limit: limit, offset: offset) }
    }
}
public extension MusicQuery where Value == Int {
    static var historyCount: Self { .init(key: .historyCount) { try await $0.historyCount() } }
}

public extension MusicQuery where Value == MusicSearchResult {
    static func search(keywords: String, offset: Int = 0, limit: Int = 10) -> Self {
        let normalized = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(key: .search(keywords: normalized, offset: offset, limit: limit)) {
            try await $0.search(keywords: normalized, limit: limit, offset: offset)
        }
    }
}

public struct MusicCachedValue<Value: Sendable>: Sendable {
    public let value: Value
    public let fetchedAt: Date
}

/// Memory-only cache. Shared requests belong to the repository, not a disappearing View.
/// Invalidation cancels the request AND revokes its ticket, even for cancellation-ignoring loaders.
public actor MusicRepository {
    private struct Entry: Sendable {
        let ticket: UUID
        let value: any Sendable
        let fetchedAt: Date
        var access: UInt64 = 0
    }
    private struct Flight {
        let id: UUID
        let task: Task<Entry, Error>
        var consumers: Set<UUID> = []
        var committed = false
    }
    private let client: MusicClient
    private let now: @Sendable () -> Date
    private let capacity: Int
    private var access: UInt64 = 0
    private var cache: [MusicCacheKey: Entry] = [:]
    private var flights: [MusicCacheKey: Flight] = [:]

    public init(client: MusicClient, now: @escaping @Sendable () -> Date = { Date() }, capacity: Int = 128) {
        self.client = client
        self.now = now
        self.capacity = max(1, capacity)
    }

    public func cached<Value>(for query: MusicQuery<Value>) -> MusicCachedValue<Value>? {
        guard let entry = cache[query.key], let value = entry.value as? Value else { return nil }
        access &+= 1
        cache[query.key]?.access = access
        return MusicCachedValue(value: value, fetchedAt: entry.fetchedAt)
    }

    public func value<Value>(for query: MusicQuery<Value>, force: Bool = false) async throws -> MusicCachedValue<Value> {
        try Task.checkCancellation()
        if !force, let entry = cached(for: query), now().timeIntervalSince(entry.fetchedAt) < query.key.ttl {
            return entry
        }
        let flight: Flight
        if let existing = flights[query.key] {
            flight = existing
        } else {
            let client = client
            let now = now
            let ticket = UUID()
            flight = Flight(id: ticket, task: Task {
                let value = try await query.fetch(client)
                try Task.checkCancellation()
                return Entry(ticket: ticket, value: value, fetchedAt: now())
            })
            flights[query.key] = flight
        }
        let consumer = UUID()
        flights[query.key]?.consumers.insert(consumer)
        defer { finishConsumer(consumer, key: query.key, flightID: flight.id) }
        let entry = try await withTaskCancellationHandler {
            try await flight.task.value
        } onCancel: {
            // Search input owns demand. Other resources continue warming their SWR cache.
            Task { await self.cancelSearchConsumer(consumer, key: query.key, flightID: flight.id) }
        }
        // Keep the ticket until every waiter finishes. Cache eviction must not revoke a response.
        guard flights[query.key]?.id == flight.id else { throw CancellationError() }
        if flights[query.key]?.committed == false {
            access &+= 1
            var cachedEntry = entry
            cachedEntry.access = access
            cache[query.key] = cachedEntry
            flights[query.key]?.committed = true
            trimCache()
        }
        try Task.checkCancellation()
        guard let value = entry.value as? Value else { throw CancellationError() }
        return MusicCachedValue(value: value, fetchedAt: entry.fetchedAt)
    }

    #if DEBUG
    // Read-only diagnostic used to synchronize concurrency tests without timing sleeps.
    func inFlightConsumerCount(for key: MusicCacheKey) -> Int { flights[key]?.consumers.count ?? 0 }
    func cachedEntryCount() -> Int { cache.count }
    #endif

    private func finishConsumer(_ consumer: UUID, key: MusicCacheKey, flightID: UUID) {
        guard flights[key]?.id == flightID else { return }
        flights[key]?.consumers.remove(consumer)
        if flights[key]?.consumers.isEmpty == true { flights[key] = nil }
    }

    /// Retain stale values for SWR until capacity pressure. Evict expired entries first,
    /// then least recently accessed; reads never extend TTL. Flights are independent.
    private func trimCache() {
        let date = now()
        while cache.count > capacity {
            let victim = cache.min { lhs, rhs in
                let leftExpired = date.timeIntervalSince(lhs.value.fetchedAt) >= lhs.key.ttl
                let rightExpired = date.timeIntervalSince(rhs.value.fetchedAt) >= rhs.key.ttl
                if leftExpired != rightExpired { return leftExpired }
                return lhs.value.access < rhs.value.access
            }?.key
            guard let victim else { return }
            cache[victim] = nil
        }
    }

    private func cancelSearchConsumer(_ consumer: UUID, key: MusicCacheKey, flightID: UUID) {
        guard case .search = key, flights[key]?.id == flightID else { return }
        flights[key]?.consumers.remove(consumer)
        if flights[key]?.consumers.isEmpty == true {
            flights.removeValue(forKey: key)?.task.cancel()
        }
    }

    public func invalidate(_ keys: Set<MusicCacheKey>) {
        for key in keys {
            cache[key] = nil
            flights.removeValue(forKey: key)?.task.cancel()
        }
    }

    public func invalidateHistory() {
        invalidate(Set(cache.keys).union(flights.keys).filter {
            switch $0 { case .history, .historyCount: return true; default: return false }
        })
    }

    public func reset() {
        cache.removeAll()
        for flight in flights.values { flight.task.cancel() }
        flights.removeAll()
    }
}
