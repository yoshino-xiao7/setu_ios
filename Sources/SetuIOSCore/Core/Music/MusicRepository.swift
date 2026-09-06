import Foundation

public enum MusicCacheKey: Hashable, Sendable {
    case hotSearch, recommendedPlaylists, newSongs, dailySongs, playlists, historyCount
    case playlist(Int), recommendedTracks(Int), history(limit: Int, offset: Int)

    case search(keywords: String, offset: Int, limit: Int)

    // V2 cache entries remain session-owned: MusicStore replaces/resets its repository on user switch.
    case home
    case searchV2(keywords: String, scope: MusicV2SearchScope, offset: Int, limit: Int?)
    case searchSuggestions(String), hotSearchV2
    case track(String), tracksBatch([String]), lyrics(String)
    case artist(String), artistTracks(String, offset: Int, limit: Int), artistAlbums(String, offset: Int, limit: Int), artistMVs(String, offset: Int, limit: Int)
    case album(String)
    case providerPlaylist(String, offset: Int, limit: Int), providerPlaylistTracks(String, offset: Int, limit: Int)
    case rankings
    case recommendTracks, recommendPlaylists(limit: Int)
    case newReleaseTracks(area: MusicV2Area, offset: Int, limit: Int), newReleaseAlbums(area: MusicV2Area, offset: Int, limit: Int)
    // User-library HTTP responses are no-store, but this private process cache is allowed for 60s.
    case library, likedTracks(offset: Int, limit: Int), favoritePlaylists(offset: Int, limit: Int), historyV2(offset: Int, limit: Int)
    // Deliberately no radioFM key: each call must produce a fresh private batch.

    public var ttl: TimeInterval {
        switch self {
        case .hotSearch, .dailySongs: return 30 * 60
        case .recommendedPlaylists, .newSongs, .recommendedTracks, .search: return 10 * 60
        case .playlists, .playlist: return 5 * 60 // SWR fallback for changes from another device.
        case .history, .historyCount: return 60
        case .home: return 5 * 60
        case .searchV2, .searchSuggestions, .recommendPlaylists, .newReleaseTracks, .newReleaseAlbums: return 10 * 60
        case .hotSearchV2, .track, .tracksBatch, .artist, .artistTracks, .artistAlbums, .artistMVs, .album, .rankings: return 30 * 60
        case .lyrics: return 24 * 60 * 60
        case .providerPlaylist, .providerPlaylistTracks: return 5 * 60
        case .recommendTracks:
            // A stricter client policy is safe: never retain a "daily" result beyond one day.
            return 24 * 60 * 60
        case .library, .likedTracks, .favoritePlaylists, .historyV2: return 60
        }
    }

    public func isFresh(fetchedAt: Date, now: Date) -> Bool {
        if self == .recommendTracks {
            let calendar = Calendar.autoupdatingCurrent
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: fetchedAt)) else { return false }
            return now < nextDay
        }
        return now.timeIntervalSince(fetchedAt) < ttl
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
        if !force, let entry = cached(for: query), query.key.isFresh(fetchedAt: entry.fetchedAt, now: now()) {
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
                let leftExpired = !lhs.key.isFresh(fetchedAt: lhs.value.fetchedAt, now: date)
                let rightExpired = !rhs.key.isFresh(fetchedAt: rhs.value.fetchedAt, now: date)
                if leftExpired != rightExpired { return leftExpired }
                return lhs.value.access < rhs.value.access
            }?.key
            guard let victim else { return }
            cache[victim] = nil
        }
    }

    private func cancelSearchConsumer(_ consumer: UUID, key: MusicCacheKey, flightID: UUID) {
        let isSearch: Bool
        switch key { case .search, .searchV2: isSearch = true; default: isSearch = false }
        guard isSearch, flights[key]?.id == flightID else { return }
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

// V2 queries reuse the existing repository/cache/SWR/single-flight implementation. The client is
// captured by the typed query so no parallel repository or networking stack is introduced.
public extension MusicQuery {
    init(key: MusicCacheKey, client: MusicV2Client, fetch: @escaping @Sendable (MusicV2Client) async throws -> Value) {
        self.init(key: key) { _ in try await fetch(client) }
    }
}

public extension MusicQuery where Value == MusicV2HomeFeed {
    static func home(client: MusicV2Client) -> Self { .init(key: .home, client: client) { try await $0.home() } }
}
public extension MusicQuery where Value == MusicV2SearchResult {
    static func searchV2(client: MusicV2Client, keywords: String, scope: MusicV2SearchScope = .tracks, limit: Int? = nil, offset: Int = 0) -> Self {
        let normalized = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(key: .searchV2(keywords: normalized, scope: scope, offset: offset, limit: limit), client: client) {
            try await $0.search(keywords: normalized, scope: scope, limit: limit, offset: offset)
        }
    }
}
public extension MusicQuery where Value == MusicV2SearchSuggestions {
    static func searchSuggestions(client: MusicV2Client, keywords: String) -> Self {
        let normalized = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(key: .searchSuggestions(normalized), client: client) { try await $0.searchSuggestions(keywords: normalized) }
    }
}
public extension MusicQuery where Value == MusicV2HotSearch { static func hotSearchV2(client: MusicV2Client) -> Self { .init(key: .hotSearchV2, client: client) { try await $0.hotSearch() } } }
public extension MusicQuery where Value == MusicV2Track { static func track(client: MusicV2Client, id: MusicV2TrackID) -> Self { .init(key: .track(id.rawValue), client: client) { try await $0.track(id) } } }
public extension MusicQuery where Value == MusicV2TrackBatch { static func tracks(client: MusicV2Client, ids: [MusicV2TrackID]) -> Self { .init(key: .tracksBatch(ids.map(\.rawValue)), client: client) { try await $0.tracks(ids) } } }
public extension MusicQuery where Value == MusicV2Lyric { static func lyrics(client: MusicV2Client, id: MusicV2TrackID) -> Self { .init(key: .lyrics(id.rawValue), client: client) { try await $0.lyrics(trackID: id) } } }
public extension MusicQuery where Value == MusicV2ArtistDetail { static func artist(client: MusicV2Client, id: MusicV2ArtistID) -> Self { .init(key: .artist(id.rawValue), client: client) { try await $0.artist(id) } } }
public extension MusicQuery where Value == MusicV2TrackPage { static func artistTracks(client: MusicV2Client, id: MusicV2ArtistID, limit: Int = 20, offset: Int = 0) -> Self { .init(key: .artistTracks(id.rawValue, offset: offset, limit: limit), client: client) { try await $0.artistTracks(id, limit: limit, offset: offset) } } }
public extension MusicQuery where Value == MusicV2AlbumPage { static func artistAlbums(client: MusicV2Client, id: MusicV2ArtistID, limit: Int = 20, offset: Int = 0) -> Self { .init(key: .artistAlbums(id.rawValue, offset: offset, limit: limit), client: client) { try await $0.artistAlbums(id, limit: limit, offset: offset) } } }
public extension MusicQuery where Value == MusicV2MvPage { static func artistMVs(client: MusicV2Client, id: MusicV2ArtistID, limit: Int = 20, offset: Int = 0) -> Self { .init(key: .artistMVs(id.rawValue, offset: offset, limit: limit), client: client) { try await $0.artistMVs(id, limit: limit, offset: offset) } } }
public extension MusicQuery where Value == MusicV2AlbumDetail { static func album(client: MusicV2Client, id: MusicV2AlbumID) -> Self { .init(key: .album(id.rawValue), client: client) { try await $0.album(id) } } }
public extension MusicQuery where Value == MusicV2PlaylistDetail { static func playlistV2(client: MusicV2Client, id: MusicV2PlaylistID, limit: Int = 50, offset: Int = 0) -> Self { .init(key: .providerPlaylist(id.rawValue, offset: offset, limit: limit), client: client) { try await $0.playlist(id, limit: limit, offset: offset) } } }
public extension MusicQuery where Value == MusicV2MembershipPage { static func playlistTracksV2(client: MusicV2Client, id: MusicV2PlaylistID, limit: Int = 50, offset: Int = 0) -> Self { .init(key: .providerPlaylistTracks(id.rawValue, offset: offset, limit: limit), client: client) { try await $0.playlistTracks(id, limit: limit, offset: offset) } } }
public extension MusicQuery where Value == MusicV2Rankings { static func rankings(client: MusicV2Client) -> Self { .init(key: .rankings, client: client) { try await $0.rankings() } } }
public extension MusicQuery where Value == MusicV2RecommendedTracks { static func recommendedTracksV2(client: MusicV2Client) -> Self { .init(key: .recommendTracks, client: client) { try await $0.recommendedTracks() } } }
public extension MusicQuery where Value == MusicV2RecommendedPlaylists { static func recommendedPlaylistsV2(client: MusicV2Client, limit: Int = 20) -> Self { .init(key: .recommendPlaylists(limit: limit), client: client) { try await $0.recommendedPlaylists(limit: limit) } } }
public extension MusicQuery where Value == MusicV2NewTracks { static func newReleaseTracks(client: MusicV2Client, area: MusicV2Area = .all, limit: Int = 30, offset: Int = 0) -> Self { .init(key: .newReleaseTracks(area: area, offset: offset, limit: limit), client: client) { try await $0.newReleaseTracks(area: area, limit: limit, offset: offset) } } }
public extension MusicQuery where Value == MusicV2NewAlbums { static func newReleaseAlbums(client: MusicV2Client, area: MusicV2Area = .all, limit: Int = 30, offset: Int = 0) -> Self { .init(key: .newReleaseAlbums(area: area, offset: offset, limit: limit), client: client) { try await $0.newReleaseAlbums(area: area, limit: limit, offset: offset) } } }
public extension MusicQuery where Value == MusicV2UserLibrary { static func library(client: MusicV2Client) -> Self { .init(key: .library, client: client) { try await $0.library() } } }
public extension MusicQuery where Value == MusicV2LikedPage { static func likedTracks(client: MusicV2Client, limit: Int = 20, offset: Int = 0) -> Self { .init(key: .likedTracks(offset: offset, limit: limit), client: client) { try await $0.likedTracks(limit: limit, offset: offset) } } }
public extension MusicQuery where Value == MusicV2SavedPage { static func favoritePlaylists(client: MusicV2Client, limit: Int = 20, offset: Int = 0) -> Self { .init(key: .favoritePlaylists(offset: offset, limit: limit), client: client) { try await $0.favoritePlaylists(limit: limit, offset: offset) } } }
public extension MusicQuery where Value == MusicV2HistoryPage {
    static func historyV2(client: MusicV2Client, limit: Int = 20, offset: Int = 0) -> Self {
        .init(key: .historyV2(offset: offset, limit: limit), client: client) { client in
            let page = try await client.history(limit: limit, offset: offset)
            let missing = page.items.filter { $0.track == nil }.map(\.trackId)
            guard !missing.isEmpty else { return page }
            // History membership is durable even when catalog details are unavailable.
            let tracks: [MusicV2Track]
            do { tracks = try await client.tracks(missing).items }
            catch {
                try Task.checkCancellation()
                return page
            }
            let items = page.items.map { entry in
                var entry = entry
                if entry.track == nil { entry.track = tracks.first { $0.id == entry.trackId } }
                return entry
            }
            return MusicV2HistoryPage(items: items, offset: page.offset, limit: page.limit,
                hasMore: page.hasMore, total: page.total, nextOffset: page.nextOffset)
        }
    }
}
