import Foundation
import Observation
import SetuIOSCore

/// Value and refresh activity are independent: a refresh can never hide existing content.
@MainActor @Observable
final class MusicResource<Value: Sendable> {
    private(set) var value: Value?
    private(set) var error: UserFacingError?
    private(set) var isRefreshing = false
    private(set) var fetchedAt: Date?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var revision = UUID()

    var state: LoadState<Value> {
        if let value { return .loaded(value) }
        if let error { return .failed(error) }
        return isRefreshing ? .loading : .idle
    }

    func load(ttl: TimeInterval, now: Date, force: Bool,
              fetch: @escaping @Sendable () async throws -> (Value, Date)) async {
        if let task { await task.value; return }
        if !force, value != nil, let fetchedAt, now.timeIntervalSince(fetchedAt) < ttl { return }
        let ticket = revision
        isRefreshing = true
        error = nil
        // Store-owned work survives navigation cancellation; reset/invalidation owns cancellation.
        let work = Task { [weak self] in
            do {
                let (value, date) = try await fetch()
                guard let self, self.revision == ticket, !Task.isCancelled else { return }
                self.value = value
                self.fetchedAt = date
            } catch {
                guard let self, self.revision == ticket, !Task.isCancelled else { return }
                if !(error is CancellationError) { self.error = UserFacingErrorMapper.map(error) }
            }
            guard let self, self.revision == ticket else { return }
            self.isRefreshing = false
            self.task = nil
        }
        task = work
        await work.value
    }

    func update(markStale: Bool = true, _ transform: (inout Value?) -> Void) {
        let previousDate = fetchedAt
        invalidate()
        if !markStale { fetchedAt = previousDate }
        transform(&value)
        error = nil
    }

    func invalidate() {
        revision = UUID()
        task?.cancel()
        task = nil
        isRefreshing = false
        fetchedAt = nil
    }

    func reset() {
        invalidate()
        value = nil
        error = nil
    }
}

struct MusicHistoryPage: Sendable {
    var records: [MusicHistoryRecord]
    var count: Int
    var nextOffset: Int
}

@MainActor @Observable
final class MusicStore {
    let searchSession: MusicSearchSession
    let v2SearchSession: MusicCutoverSearchSession
    let canonicalHistory = MusicResource<MusicLibraryPage<MusicHistoryItem>>()
    private(set) var historyCohortPinned = false
    let hotSearch = MusicResource<[MusicHotSearchItem]>()
    let recommendedPlaylists = MusicResource<[MusicRecommendedPlaylist]>()
    let newSongs = MusicResource<[MusicSong]>()
    let dailySongs = MusicResource<[MusicSong]>()
    let recentHistory = MusicResource<[MusicHistoryRecord]>()
    let playlists = MusicResource<[UserMusicPlaylist]>()
    let history = MusicResource<MusicHistoryPage>()
    let library = MusicResource<MusicV2UserLibrary>()
    let likedTracks = MusicResource<MusicLibraryPage<MusicLibraryTrack>>()
    let favoritePlaylists = MusicResource<MusicLibraryPage<MusicLibraryPlaylist>>()
    private(set) var likedTrackIDs: Set<String> = []
    private(set) var savedPlaylistIDs: Set<String> = []
    private(set) var libraryWriting = false
    private(set) var libraryMoreLoading: Set<String> = []
    private(set) var libraryMoreErrors: [String: UserFacingError] = [:]
    @ObservationIgnored private var libraryRevision = UUID()
    @ObservationIgnored private var libraryKeys: Set<MusicCacheKey> = [.library]
    @ObservationIgnored private var likedPreparation: Task<Void, Never>?
    @ObservationIgnored private var savedPreparation: Task<Void, Never>?
    let homeFeed = MusicResource<MusicV2HomeFeed>()
    let rankings = MusicResource<MusicV2Rankings>()
    let v2RecommendedPlaylists = MusicResource<MusicV2RecommendedPlaylists>()
    let dailyRecommendations = MusicResource<MusicV2RecommendedTracks>()
    private(set) var newReleaseTracks: [MusicV2Area: MusicResource<MusicDiscoverPage<MusicV2Track>>] = [:]
    private(set) var newReleaseAlbums: [MusicV2Area: MusicResource<MusicDiscoverPage<MusicV2Album>>] = [:]
    private(set) var discoverMoreLoading: Set<String> = []
    private(set) var discoverMoreErrors: [String: UserFacingError] = [:]
    @ObservationIgnored private var discoverRevisions: [String: UUID] = [:]
    private(set) var playlistDetails: [Int: MusicResource<UserMusicPlaylistDetail>] = [:]
    private(set) var recommendedTracks: [Int: MusicResource<[MusicSong]>] = [:]
    private(set) var artistDetails: [String: MusicResource<MusicV2ArtistDetail>] = [:]
    private(set) var albumDetails: [String: MusicResource<MusicV2AlbumDetail>] = [:]
    private(set) var playlistDetailsV2: [String: MusicResource<MusicPlaylistDetailData>] = [:]
    private(set) var detailMoreLoading: Set<String> = []
    private(set) var detailMoreErrors: [String: UserFacingError] = [:]
    @ObservationIgnored private var detailRevisions: [String: UUID] = [:]
    private(set) var isLoadingMore = false
    private(set) var historyMoreError: UserFacingError?
    private(set) var userID: Int?
    @ObservationIgnored private let client: MusicClient
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var repository: MusicRepository
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var historyRevision = UUID()

    init(client: MusicClient, userID: Int? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.userID = userID
        self.now = now
        let repository = MusicRepository(client: client, now: now)
        self.repository = repository
        searchSession = MusicSearchSession(repository: repository, now: now)
        v2SearchSession = MusicCutoverSearchSession(repository: repository)
    }

    var sessionToken: UUID { generation }

    func reset(for userID: Int?) {
        guard self.userID != userID else { return }
        self.userID = userID
        generation = UUID()
        libraryRevision = UUID()
        likedPreparation?.cancel(); likedPreparation = nil
        savedPreparation?.cancel(); savedPreparation = nil
        library.reset(); likedTracks.reset(); favoritePlaylists.reset()
        likedTrackIDs.removeAll(); savedPlaylistIDs.removeAll()
        libraryWriting = false; libraryMoreLoading.removeAll(); libraryMoreErrors.removeAll()
        libraryKeys = [.library]
        historyRevision = UUID()
        hotSearch.reset(); recommendedPlaylists.reset(); newSongs.reset(); dailySongs.reset()
        recentHistory.reset(); playlists.reset(); history.reset()
        homeFeed.reset(); rankings.reset(); dailyRecommendations.reset()
        v2RecommendedPlaylists.reset()
        for resource in newReleaseTracks.values { resource.reset() }
        for resource in newReleaseAlbums.values { resource.reset() }
        newReleaseTracks.removeAll(); newReleaseAlbums.removeAll()
        discoverMoreLoading.removeAll(); discoverMoreErrors.removeAll(); discoverRevisions.removeAll()
        for resource in playlistDetails.values { resource.reset() }
        for resource in recommendedTracks.values { resource.reset() }
        playlistDetails.removeAll(); recommendedTracks.removeAll()
        for resource in artistDetails.values { resource.reset() }
        for resource in albumDetails.values { resource.reset() }
        for resource in playlistDetailsV2.values { resource.reset() }
        artistDetails.removeAll(); albumDetails.removeAll(); playlistDetailsV2.removeAll()
        detailMoreLoading.removeAll(); detailMoreErrors.removeAll(); detailRevisions.removeAll()
        isLoadingMore = false
        historyMoreError = nil
        // Swap synchronously: no new-user read can race asynchronous cache clearing.
        let previous = repository
        repository = MusicRepository(client: client, now: now)
        searchSession.reset(repository: repository)
        v2SearchSession.reset(repository: repository)
        canonicalHistory.reset(); historyCohortPinned = false
        Task { await previous.reset() }
    }

    func detail(_ id: Int) -> MusicResource<UserMusicPlaylistDetail> {
        if let resource = playlistDetails[id] { return resource }
        let resource = MusicResource<UserMusicPlaylistDetail>()
        playlistDetails[id] = resource
        return resource
    }

    func tracks(_ id: Int) -> MusicResource<[MusicSong]> {
        if let resource = recommendedTracks[id] { return resource }
        let resource = MusicResource<[MusicSong]>()
        recommendedTracks[id] = resource
        return resource
    }

    private func load<Value>(_ resource: MusicResource<Value>, _ query: MusicQuery<Value>, force: Bool) async {
        let repository = repository
        await resource.load(ttl: query.key.ttl, now: now(), force: force) {
            let result = try await repository.value(for: query, force: force)
            return (result.value, result.fetchedAt)
        }
    }

    func loadHome(force: Bool = false, historyClient: MusicV2Client? = nil) async {
        async let hot: Void = load(hotSearch, .hotSearch, force: force)
        async let recommended: Void = load(recommendedPlaylists, .recommendedPlaylists, force: force)
        async let new: Void = load(newSongs, .newSongs, force: force)
        async let daily: Void = load(dailySongs, .dailySongs, force: force)
        async let recent: Void = loadHomeHistory(client: historyClient, force: force)
        async let lists: Void = loadPlaylists(force: force)
        _ = await (hot, recommended, new, daily, recent, lists)
    }

    private func loadHomeHistory(client: MusicV2Client?, force: Bool) async {
        if let client {
            await loadCanonicalHistory(client: client, force: force)
        } else {
            await load(recentHistory, .history(limit: 8), force: force)
        }
    }

    func loadHomeV2(client: MusicV2Client, force: Bool = false) async {
        await load(homeFeed, .home(client: client), force: force)
    }

    /// The product dashboard owns history and retained capabilities separately from the v2 feed.
    /// Each resource retains its existing cache, deduplication and owner-reset behavior.
    func loadDashboard(client: MusicV2Client, force: Bool = false) async {
        async let feed: Void = loadDashboardDiscovery(client: client, force: force)
        async let history: Void = loadCanonicalHistory(client: client, force: force)
        async let daily: Void = loadLegacyDaily(force: force)
        async let hot: Void = load(hotSearch, .hotSearch, force: force)
        _ = await (feed, history, daily, hot)
    }

    private func loadDashboardDiscovery(client: MusicV2Client, force: Bool) async {
        let owner = generation
        await loadHomeV2(client: client, force: force)
        guard generation == owner, homeFeed.error?.action != .signIn else { return }
        let hasRecommendations = homeFeed.value?.sections.contains {
            $0.kind == .recommendedPlaylists && !$0.items.isEmpty
        } ?? false
        if !hasRecommendations {
            // Home has a short section deadline. The standalone supported endpoint gets one
            // normal cached request, not an automatic retry loop or an unsupported v1 substitute.
            await loadRecommendedPlaylists(client: client, force: force)
        }
    }

    func loadRankings(client: MusicV2Client, force: Bool = false) async {
        await load(rankings, .rankings(client: client), force: force)
    }

    func loadRecommendedPlaylists(client: MusicV2Client, force: Bool = false) async {
        await load(v2RecommendedPlaylists, .recommendedPlaylistsV2(client: client), force: force)
    }

    func loadLegacyDaily(force: Bool = false) async { await load(dailySongs, .dailySongs, force: force) }

    func loadDailyRecommendations(client: MusicV2Client, force: Bool = false) async {
        // MusicResource has a duration TTL; apply P9's day boundary before entering it.
        let stale = dailyRecommendations.fetchedAt.map { !MusicCacheKey.recommendTracks.isFresh(fetchedAt: $0, now: now()) } ?? false
        await load(dailyRecommendations, .recommendedTracksV2(client: client), force: force || stale)
    }

    func releaseTracks(_ area: MusicV2Area) -> MusicResource<MusicDiscoverPage<MusicV2Track>> {
        if let value = newReleaseTracks[area] { return value }
        let value = MusicResource<MusicDiscoverPage<MusicV2Track>>()
        newReleaseTracks[area] = value; return value
    }

    func releaseAlbums(_ area: MusicV2Area) -> MusicResource<MusicDiscoverPage<MusicV2Album>> {
        if let value = newReleaseAlbums[area] { return value }
        let value = MusicResource<MusicDiscoverPage<MusicV2Album>>()
        newReleaseAlbums[area] = value; return value
    }

    func loadNewTracks(_ area: MusicV2Area, client: MusicV2Client, force: Bool = false, more: Bool = false) async {
        await loadDiscoverPage(releaseTracks(area), key: "tracks:" + area.rawValue, force: force, more: more,
            query: { .newReleaseTracks(client: client, area: area, offset: $0) },
            project: { MusicDiscoverPage(items: $0.items.items, source: $0.source, nextOffset: $0.items.nextOffset, loadedOffsets: [$0.items.offset]) })
    }

    func loadNewAlbums(_ area: MusicV2Area, client: MusicV2Client, force: Bool = false, more: Bool = false) async {
        await loadDiscoverPage(releaseAlbums(area), key: "albums:" + area.rawValue, force: force, more: more,
            query: { .newReleaseAlbums(client: client, area: area, offset: $0) },
            project: { MusicDiscoverPage(items: $0.items.items, source: $0.source, nextOffset: $0.items.nextOffset, loadedOffsets: [$0.items.offset]) })
    }

    private func loadDiscoverPage<Item, Response>(_ resource: MusicResource<MusicDiscoverPage<Item>>, key: String,
        force: Bool, more: Bool, query: @escaping @Sendable (Int) -> MusicQuery<Response>,
        project: @escaping @Sendable (Response) -> MusicDiscoverPage<Item>) async {
        let repository = repository
        if more {
            guard !resource.isRefreshing, !discoverMoreLoading.contains(key),
                  let offset = resource.value?.nextOffset else { return }
            let owner = generation, revision = discoverRevisions[key]
            discoverMoreLoading.insert(key); discoverMoreErrors[key] = nil
            do {
                let result = try await repository.value(for: query(offset))
                guard owner == generation, revision == discoverRevisions[key] else { return }
                let page = project(result.value)
                resource.update(markStale: false) { value in
                    value?.items.append(contentsOf: page.items)
                    value?.nextOffset = page.nextOffset
                    value?.loadedOffsets.append(offset)
                }
            } catch {
                guard owner == generation, revision == discoverRevisions[key] else { return }
                discoverMoreErrors[key] = UserFacingErrorMapper.map(error)
            }
            discoverMoreLoading.remove(key)
        } else {
            let first = query(0)
            if !resource.isRefreshing, force || resource.fetchedAt.map({ !first.key.isFresh(fetchedAt: $0, now: now()) }) != false {
                discoverRevisions[key] = UUID(); discoverMoreLoading.remove(key); discoverMoreErrors[key] = nil
            }
            let offsets = resource.value?.loadedOffsets ?? []
            await resource.load(ttl: first.key.ttl, now: now(), force: force) {
                if force { await repository.invalidate(Set(offsets.map { query($0).key })) }
                let result = try await repository.value(for: first, force: force)
                return (project(result.value), result.fetchedAt)
            }
        }
    }

    func loadPlaylists(force: Bool = false) async { await load(playlists, .playlists, force: force) }
    func loadDetail(_ id: Int, force: Bool = false) async { await load(detail(id), .playlist(id), force: force) }
    func loadTracks(_ id: Int, force: Bool = false) async { await load(tracks(id), .recommendedTracks(id), force: force) }

    func artistDetail(_ id: String) -> MusicResource<MusicV2ArtistDetail> {
        if let value = artistDetails[id] { return value }
        let value = MusicResource<MusicV2ArtistDetail>(); artistDetails[id] = value; return value
    }

    func albumDetail(_ id: String) -> MusicResource<MusicV2AlbumDetail> {
        if let value = albumDetails[id] { return value }
        let value = MusicResource<MusicV2AlbumDetail>(); albumDetails[id] = value; return value
    }

    func playlistDetailV2(_ id: String) -> MusicResource<MusicPlaylistDetailData> {
        if let value = playlistDetailsV2[id] { return value }
        let value = MusicResource<MusicPlaylistDetailData>(); playlistDetailsV2[id] = value; return value
    }

    func loadArtistDetail(_ id: String, client: MusicV2Client, force: Bool = false) async {
        await load(artistDetail(id), .artist(client: client, id: .init(rawValue: id)), force: force)
    }

    func loadAlbumDetail(_ id: String, client: MusicV2Client, force: Bool = false) async {
        await load(albumDetail(id), .album(client: client, id: .init(rawValue: id)), force: force)
    }

    func loadPlaylistDetailV2(_ id: MusicV2PlaylistID, client: MusicV2Client, force: Bool = false) async {
        let resource = playlistDetailV2(id.rawValue)
        let repository = repository
        let query = MusicQuery<MusicV2PlaylistDetail>.playlistV2(client: client, id: id)
        let needsLoad = force || resource.value == nil || resource.fetchedAt.map { now().timeIntervalSince($0) >= query.key.ttl } != false
        if !resource.isRefreshing, needsLoad {
            detailRevisions[id.rawValue] = UUID(); detailMoreErrors[id.rawValue] = nil
        }
        let offsets = resource.value?.loadedOffsets ?? []
        await resource.load(ttl: query.key.ttl, now: now(), force: force) {
            if force {
                await repository.invalidate(Set(offsets.map { .providerPlaylistTracks(id.rawValue, offset: $0, limit: 50) }))
            }
            let result = try await repository.value(for: query, force: force)
            return (MusicPlaylistDetailData(result.value), result.fetchedAt)
        }
    }

    func invalidateLegacyPlaylistReadsAfterDetailWrite() async {
        let owner = generation, repository = repository
        let keys = Set([MusicCacheKey.playlists] + playlistDetails.keys.map(MusicCacheKey.playlist))
        await repository.invalidate(keys)
        guard owner == generation else { return }
        playlists.invalidate()
        for resource in playlistDetails.values { resource.invalidate() }
    }

    func loadMorePlaylistDetail(_ id: MusicV2PlaylistID, client: MusicV2Client) async {
        let key = id.rawValue, resource = playlistDetailV2(id.rawValue)
        guard let value = resource.value, let offset = value.nextOffset,
              !resource.isRefreshing, !detailMoreLoading.contains(key) else { return }
        let owner = generation, revision = detailRevisions[key], repository = repository
        detailMoreLoading.insert(key); detailMoreErrors[key] = nil
        defer { if generation == owner { detailMoreLoading.remove(key) } }
        do {
            let page = try await repository.value(for: .playlistTracksV2(client: client, id: id, offset: offset))
            guard generation == owner, detailRevisions[key] == revision, !resource.isRefreshing,
                  resource.value?.nextOffset == offset else { return }
            guard page.value.offset == offset, !page.value.hasMore || (page.value.nextOffset ?? offset) > offset else {
                throw UserFacingError(message: "歌单分页信息无效，请刷新后重试")
            }
            resource.update(markStale: false) { $0?.append(page.value) }
        } catch {
            guard generation == owner, detailRevisions[key] == revision else { return }
            detailMoreErrors[key] = UserFacingErrorMapper.map(error)
        }
    }

    func loadHistory(force: Bool = false) async {
        if !history.isRefreshing,
           force || history.fetchedAt.map({ now().timeIntervalSince($0) >= MusicCacheKey.historyCount.ttl }) != false {
            historyRevision = UUID()
            isLoadingMore = false
            historyMoreError = nil
        }
        let repository = repository
        await history.load(ttl: MusicCacheKey.historyCount.ttl, now: now(), force: force) {
            async let records = repository.value(for: .history(limit: 20), force: force)
            async let count = repository.value(for: .historyCount, force: force)
            let (rows, total) = try await (records, count)
            return (MusicHistoryPage(records: rows.value, count: total.value, nextOffset: rows.value.count),
                    min(rows.fetchedAt, total.fetchedAt))
        }
    }

    func loadMoreHistory() async {
        guard let page = history.value, page.nextOffset < page.count,
              !history.isRefreshing, !isLoadingMore else { return }
        let ticket = historyRevision
        let owner = generation
        isLoadingMore = true
        historyMoreError = nil
        defer { if owner == generation, ticket == historyRevision { isLoadingMore = false } }
        do {
            let result = try await repository.value(for: .history(limit: 20, offset: page.nextOffset))
            guard owner == generation, ticket == historyRevision, !history.isRefreshing,
                  history.value?.nextOffset == page.nextOffset else { return }
            history.update(markStale: false) { value in
                guard var current = value else { return }
                let existing = Set(current.records.map(\.songId))
                current.records.append(contentsOf: result.value.filter { !existing.contains($0.songId) })
                current.nextOffset += result.value.count
                if result.value.count < 20 { current.count = current.nextOffset }
                value = current
            }
        } catch {
            guard owner == generation, ticket == historyRevision else { return }
            if !(error is CancellationError) { historyMoreError = UserFacingErrorMapper.map(error) }
        }
    }

    func usesCanonicalHistory(config: AppConfig) -> Bool {
        historyCohortPinned || MusicHistoryCohort.usesV2(base: config.apiBaseURL, owner: userID,
                                                       flag: config.musicFeatureFlags.usesV2History)
    }
    func pinHistory(config: AppConfig) {
        guard let userID else { return }
        MusicHistoryCohort.pin(base: config.apiBaseURL, owner: userID)
        historyCohortPinned = true
    }
    func loadCanonicalHistory(client: MusicV2Client, force: Bool = false, more: Bool = false) async {
        await loadLibraryPage(canonicalHistory, name: "history", force: force, more: more,
            query: { .historyV2(client: client, offset: $0) },
            project: { MusicLibraryPage(items: $0.items.map(MusicHistoryItem.init), nextOffset: $0.nextOffset, total: $0.total) })
    }
    func recordCanonicalHistory(id: MusicV2TrackID, client: MusicV2Client) async throws {
        let owner = generation
        try await write(keys: libraryKeys) { _ in try await client.recordHistory(trackID: id) }
        guard generation == owner else { throw CancellationError() }
        canonicalHistory.invalidate(); library.invalidate()
        Task { [weak self] in
            guard let self, self.generation == owner else { return }
            await self.loadCanonicalHistory(client: client, force: true)
        }
    }
    func clearCanonicalHistory(client: MusicV2Client) async throws {
        guard !libraryWriting else { throw UserFacingError(message: "请等待当前操作完成") }
        let before = canonicalHistory.value, owner = generation
        beginLibraryWrite()
        canonicalHistory.update { $0 = .init(items: [], nextOffset: nil, total: 0) }
        defer {
            if generation == owner {
                libraryWriting = false
                Task { [weak self] in
                    guard let self, self.generation == owner else { return }
                    await self.loadCanonicalHistory(client: client, force: true)
                }
            }
        }
        do {
            try await write(keys: libraryKeys, historyChanged: true) { _ in try await client.clearHistory() }
            guard generation == owner else { throw CancellationError() }
            history.reset(); recentHistory.reset(); library.invalidate()
        } catch {
            guard generation == owner else { throw CancellationError() }
            canonicalHistory.update { $0 = before }
            throw error
        }
    }

    func loadLibrary(client: MusicV2Client, force: Bool = false) async {
        guard !libraryWriting else { return }
        await load(library, .library(client: client), force: force)
    }

    func loadLikedTracks(client: MusicV2Client, force: Bool = false, more: Bool = false) async {
        await loadLibraryPage(likedTracks, name: "liked", force: force, more: more,
            query: { .likedTracks(client: client, offset: $0) },
            project: { MusicLibraryPage(items: $0.items.map(MusicLibraryTrack.init), nextOffset: $0.nextOffset, total: $0.total) })
        likedTrackIDs = Set(likedTracks.value?.items.map { $0.id.rawValue } ?? [])
    }

    func loadFavoritePlaylists(client: MusicV2Client, force: Bool = false, more: Bool = false) async {
        await loadLibraryPage(favoritePlaylists, name: "saved", force: force, more: more,
            query: { .favoritePlaylists(client: client, offset: $0) },
            project: { MusicLibraryPage(items: $0.items.map(MusicLibraryPlaylist.init), nextOffset: $0.nextOffset, total: $0.total) })
        savedPlaylistIDs = Set(favoritePlaylists.value?.items.map { $0.id.rawValue } ?? [])
    }

    private func loadLibraryPage<Wire: Sendable, Item: Identifiable & Sendable>(
        _ resource: MusicResource<MusicLibraryPage<Item>>, name: String, force: Bool, more: Bool,
        query: (Int) -> MusicQuery<Wire>, project: @escaping @Sendable (Wire) -> MusicLibraryPage<Item>
    ) async where Item.ID: Sendable {
        guard !libraryWriting, !libraryMoreLoading.contains(name) else { return }
        let owner = generation, revision = libraryRevision, repository = repository
        if more {
            guard !resource.isRefreshing, let offset = resource.value?.nextOffset else { return }
            libraryMoreLoading.insert(name); libraryMoreErrors[name] = nil
            defer { if owner == generation, revision == libraryRevision { libraryMoreLoading.remove(name) } }
            let request = query(offset); libraryKeys.insert(request.key)
            do {
                let response = try await repository.value(for: request, force: force)
                guard owner == generation, revision == libraryRevision, !resource.isRefreshing,
                      resource.value?.nextOffset == offset else { return }
                let page = project(response.value)
                guard page.nextOffset == nil || page.nextOffset! > offset else { throw UserFacingError(message: "分页未前进，请刷新后重试") }
                resource.update(markStale: false) { value in
                    guard var current = value else { return }
                    let existing = Set(current.items.map(\.id))
                    current.items.append(contentsOf: page.items.filter { !existing.contains($0.id) })
                    current.nextOffset = page.nextOffset; current.total = page.total; value = current
                }
            } catch {
                guard owner == generation, revision == libraryRevision else { return }
                if !(error is CancellationError) { libraryMoreErrors[name] = UserFacingErrorMapper.map(error) }
            }
        } else {
            let request = query(0); libraryKeys.insert(request.key)
            await resource.load(ttl: request.key.ttl, now: now(), force: force) {
                let response = try await repository.value(for: request, force: force)
                return (project(response.value), response.fetchedAt)
            }
        }
    }

    /// Absence is known only after the complete relation list, never from a Home preview.
    func likedState(_ id: MusicV2TrackID) -> Bool? {
        if likedTrackIDs.contains(id.rawValue) { return true }
        return likedTracks.value?.nextOffset == nil && likedTracks.value != nil ? false : nil
    }
    func savedState(_ id: MusicV2ProviderPlaylistID) -> Bool? {
        if savedPlaylistIDs.contains(id.rawValue) { return true }
        return favoritePlaylists.value?.nextOffset == nil && favoritePlaylists.value != nil ? false : nil
    }

    func prepareLikedState(client: MusicV2Client) async {
        if let task = likedPreparation { await task.value; return }
        let owner = generation
        let task = Task { [weak self] in
            guard let self else { return }
            await self.loadLikedTracks(client: client)
            while self.generation == owner, !Task.isCancelled, self.likedTracks.value?.nextOffset != nil {
                let offset = self.likedTracks.value?.nextOffset
                await self.loadLikedTracks(client: client, more: true)
                if self.likedTracks.value?.nextOffset == offset { break }
            }
        }
        likedPreparation = task; await task.value
        if generation == owner { likedPreparation = nil }
    }
    func prepareSavedState(client: MusicV2Client) async {
        if let task = savedPreparation { await task.value; return }
        let owner = generation
        let task = Task { [weak self] in
            guard let self else { return }
            await self.loadFavoritePlaylists(client: client)
            while self.generation == owner, !Task.isCancelled, self.favoritePlaylists.value?.nextOffset != nil {
                let offset = self.favoritePlaylists.value?.nextOffset
                await self.loadFavoritePlaylists(client: client, more: true)
                if self.favoritePlaylists.value?.nextOffset == offset { break }
            }
        }
        savedPreparation = task; await task.value
        if generation == owner { savedPreparation = nil }
    }

    func toggleLike(_ id: MusicV2TrackID, track: MusicV2Track? = nil, client: MusicV2Client, enabled: Bool) async throws {
        guard enabled, let userID, !libraryWriting, let wasLiked = likedState(id) else {
            throw UserFacingError(message: "喜欢状态尚未就绪，请重试")
        }
        let before = likedTracks.value, ids = likedTrackIDs, owner = generation
        let snapshot = try track.map { try JSONDecoder().decode(MusicV2TrackDisplaySnapshot.self, from: JSONEncoder().encode($0)) }
        beginLibraryWrite()
        if wasLiked { likedTrackIDs.remove(id.rawValue) } else { likedTrackIDs.insert(id.rawValue) }
        likedTracks.update { value in
            guard var page = value else { return }
            page.items.removeAll { $0.id == id }
            if !wasLiked { page.items.insert(.init(id: id, ownerID: "setu:user:\(userID)", track: track), at: 0) }
            page.total = max(0, page.total + (wasLiked ? -1 : 1)); value = page
        }
        do {
            try await write(keys: libraryKeys) { _ in
                if wasLiked { try await client.unlike(id) } else { try await client.like(id, snapshot: snapshot) }
            }
            guard generation == owner else { throw CancellationError() }
            finishLibraryWrite(client: client, liked: true)
        } catch {
            guard generation == owner else { throw CancellationError() }
            likedTracks.update { $0 = before }; likedTrackIDs = ids
            finishLibraryWrite(client: client, liked: true)
            throw error
        }
    }

    func toggleFavoritePlaylist(_ id: MusicV2ProviderPlaylistID, playlist: MusicV2ProviderPlaylist? = nil,
                                client: MusicV2Client, enabled: Bool) async throws {
        guard enabled, let userID, !libraryWriting, let wasSaved = savedState(id) else {
            throw UserFacingError(message: "收藏状态尚未就绪，请重试")
        }
        let before = favoritePlaylists.value, ids = savedPlaylistIDs, owner = generation
        let snapshot = try playlist.map { try JSONDecoder().decode(MusicV2PlaylistDisplaySnapshot.self, from: JSONEncoder().encode($0)) }
        beginLibraryWrite()
        if wasSaved { savedPlaylistIDs.remove(id.rawValue) } else { savedPlaylistIDs.insert(id.rawValue) }
        favoritePlaylists.update { value in
            guard var page = value else { return }
            page.items.removeAll { $0.id == id }
            if !wasSaved { page.items.insert(.init(id: id, ownerID: "setu:user:\(userID)", playlist: playlist), at: 0) }
            page.total = max(0, page.total + (wasSaved ? -1 : 1)); value = page
        }
        do {
            try await write(keys: libraryKeys) { _ in
                if wasSaved { try await client.unsavePlaylist(id) } else { try await client.savePlaylist(id, snapshot: snapshot) }
            }
            guard generation == owner else { throw CancellationError() }
            finishLibraryWrite(client: client, liked: false)
        } catch {
            guard generation == owner else { throw CancellationError() }
            favoritePlaylists.update { $0 = before }; savedPlaylistIDs = ids
            finishLibraryWrite(client: client, liked: false)
            throw error
        }
    }
    private func beginLibraryWrite() {
        libraryWriting = true; libraryRevision = UUID()
        likedPreparation?.cancel(); likedPreparation = nil
        savedPreparation?.cancel(); savedPreparation = nil
        library.invalidate(); likedTracks.invalidate(); favoritePlaylists.invalidate(); homeFeed.invalidate()
        libraryMoreLoading.removeAll(); libraryMoreErrors.removeAll()
    }
    private func finishLibraryWrite(client: MusicV2Client, liked: Bool) {
        let owner = generation, revision = libraryRevision
        // Serialize reconciliation with writes so an older GET cannot erase a newer intent.
        Task { [weak self] in
            guard let self, self.generation == owner, self.libraryRevision == revision else { return }
            await self.repository.invalidate(self.libraryKeys.union([.home]))
            guard self.generation == owner, self.libraryRevision == revision else { return }
            self.libraryWriting = false
            if liked { await self.loadLikedTracks(client: client, force: true) }
            else { await self.loadFavoritePlaylists(client: client, force: true) }
            guard self.generation == owner, self.libraryRevision == revision else { return }
            if self.library.value != nil { await self.loadLibrary(client: client, force: true) }
        }
    }

    /// Every mutation uses the repository captured BEFORE suspension and checks account ownership.
    private func write<Value: Sendable>(keys: Set<MusicCacheKey>, historyChanged: Bool = false,
                                       operation: @Sendable (MusicClient) async throws -> Value) async throws -> Value {
        let owner = generation
        let repository = repository
        let result = try await operation(client)
        guard owner == generation else { throw CancellationError() }
        await repository.invalidate(keys)
        if historyChanged { await repository.invalidateHistory() }
        guard owner == generation else { throw CancellationError() }
        return result
    }

    func createPlaylist(name: String, description: String?, isPublic: Int) async throws {
        let playlist = try await write(keys: [.playlists]) {
            try await $0.createPlaylist(name: name, description: description, isPublic: isPublic)
        }
        let needsReconciliation = playlists.value == nil
        playlists.update { value in
            var items = value ?? []
            items.removeAll { $0.id == playlist.id }
            items.insert(playlist, at: 0)
            value = items
        }
        if needsReconciliation {
            let owner = generation
            Task { [weak self] in
                guard let self, self.generation == owner else { return }
                await self.loadPlaylists(force: true)
            }
        }
    }

    func deletePlaylist(id: Int) async throws {
        try await write(keys: [.playlists, .playlist(id)]) { try await $0.deletePlaylist(id: id) }
        playlists.update { $0?.removeAll { $0.id == id } }
        playlistDetails[id]?.reset()
        playlistDetails[id] = nil
    }

    func updatePlaylist(id: Int, name: String, description: String?, coverUrl: String?, isPublic: Int) async throws {
        try await write(keys: [.playlists, .playlist(id)]) {
            try await $0.updatePlaylist(id: id, name: name, description: description, coverUrl: coverUrl, isPublic: isPublic)
        }
        playlists.update { value in
            guard let index = value?.firstIndex(where: { $0.id == id }) else { return }
            value?[index].updateMetadata(name: name, description: description, coverUrl: coverUrl, isPublic: isPublic)
        }
        playlistDetails[id]?.update { $0?.updateMetadata(name: name, description: description, coverUrl: coverUrl, isPublic: isPublic) }
    }

    func setPlayMode(playlistID: Int, playMode: String) async throws {
        try await write(keys: [.playlists, .playlist(playlistID)]) { try await $0.setPlayMode(playlistID: playlistID, playMode: playMode) }
        patchPlaylist(playlistID, list: { $0.playMode = playMode }, detail: { $0.playMode = playMode })
    }

    func recordPlaylistPlay(id: Int) async throws {
        try await write(keys: [.playlists, .playlist(id)]) { try await $0.recordPlaylistPlay(id: id) }
        patchPlaylist(id, list: { $0.playCount = ($0.playCount ?? 0) + 1 }, detail: { $0.playCount = ($0.playCount ?? 0) + 1 })
    }

    func add(_ request: AddSongToPlaylistRequest, toPlaylist id: Int) async throws {
        let owner = generation
        try await write(keys: [.playlists, .playlist(id)]) { try await $0.add(request, toPlaylist: id) }
        let localDetails = playlistDetailsV2.filter { $0.value.value?.ownedLocal(by: userID) != nil }
        var detailKeys = Set<MusicCacheKey>()
        for (key, resource) in localDetails {
            detailKeys.insert(.providerPlaylist(key, offset: 0, limit: 50))
            for offset in resource.value?.loadedOffsets ?? [] {
                detailKeys.insert(.providerPlaylistTracks(key, offset: offset, limit: 50))
            }
        }
        await repository.invalidate(detailKeys)
        guard owner == generation else { throw CancellationError() }
        for resource in localDetails.values { resource.invalidate() }
        if request.songId == nil {
            // The server owns canonical-to-legacy identity translation. Refresh rather than invent a local numeric ID.
            playlists.invalidate(); playlistDetails[id]?.invalidate()
            if let resource = playlistDetails[id] { await load(resource, .playlist(id), force: true) }
            guard owner == generation else { throw CancellationError() }
            await loadPlaylists(force: true)
            guard owner == generation else { throw CancellationError() }
            return
        }
        let knownSongs = playlistDetails[id]?.value?.songs
        let knownCount = knownSongs.map { songs in songs.count + (songs.contains { $0.songId == request.songId } ? 0 : 1) }
        patchPlaylist(id, list: { $0.songCount = knownCount ?? (($0.songCount ?? 0) + 1) }, detail: {
            var songs = $0.songs ?? []
            if !songs.contains(where: { $0.songId == request.songId }), let song = PlaylistSong(local: request) { songs.append(song) }
            $0.songs = songs
            $0.songCount = songs.count
        })
    }

    func removeSong(playlistID: Int, song: PlaylistSong) async throws {
        let owner = generation
        var recordID = song.id
        // POST returns only "ok". Resolve the server relation ID for a newly inserted local row.
        if recordID < 0 {
            let result = try await repository.value(for: .playlist(playlistID), force: true)
            guard owner == generation else { throw CancellationError() }
            guard let record = result.value.songs?.first(where: { $0.songId == song.songId }) else { return }
            recordID = record.id
        }
        let serverID = recordID
        try await write(keys: [.playlists, .playlist(playlistID)]) { try await $0.removeSong(playlistID: playlistID, songID: serverID) }
        let knownCount = playlistDetails[playlistID]?.value?.songs?.filter { $0.songId != song.songId }.count
        patchPlaylist(playlistID, list: { $0.songCount = knownCount ?? max(0, ($0.songCount ?? 0) - 1) }, detail: {
            $0.songs?.removeAll { $0.songId == song.songId }
            $0.songCount = $0.songs?.count
        })
    }

    private func patchPlaylist(_ id: Int, list: (inout UserMusicPlaylist) -> Void,
                               detail: (inout UserMusicPlaylistDetail) -> Void) {
        playlists.update { value in
            guard let index = value?.firstIndex(where: { $0.id == id }) else { return }
            list(&value![index])
        }
        playlistDetails[id]?.update { value in
            guard value != nil else { return }
            detail(&value!)
        }
    }

    func addHistory(_ request: AddMusicHistoryRequest) async throws {
        try await write(keys: [], historyChanged: true) { try await $0.addHistory(request) }
        guard let userID else { return }
        let record = MusicHistoryRecord(local: request, userID: userID, date: now())
        historyRevision = UUID()
        isLoadingMore = false
        recentHistory.update { value in
            guard value != nil else { return }
            value?.removeAll { $0.songId == record.songId }
            value?.insert(record, at: 0)
            value = value.map { Array($0.prefix(8)) }
        }
        history.update { value in
            guard var page = value else { return }
            let existed = page.records.contains { $0.songId == record.songId }
            page.records.removeAll { $0.songId == record.songId }
            page.records.insert(record, at: 0)
            page.records = Array(page.records.prefix(50))
            // The count may be uncertain for a song in an unloaded page; refresh before paging.
            if !existed { page.count = min(50, page.count + 1) }
            page.nextOffset = page.records.count
            value = page
        }
        // Reconcile server IDs/count/order silently, keeping optimistic content visible.
        let owner = generation
        Task { [weak self] in
            guard let self, self.generation == owner else { return }
            await self.loadHistory(force: true)
            guard self.generation == owner else { return }
            await self.load(self.recentHistory, .history(limit: 8), force: true)
        }
    }

    func clearHistory() async throws {
        try await write(keys: [], historyChanged: true) { try await $0.clearHistory() }
        historyRevision = UUID()
        isLoadingMore = false
        historyMoreError = nil
        history.update { $0 = MusicHistoryPage(records: [], count: 0, nextOffset: 0) }
        recentHistory.update { $0 = [] }
    }
}
