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
    let hotSearch = MusicResource<[MusicHotSearchItem]>()
    let recommendedPlaylists = MusicResource<[MusicRecommendedPlaylist]>()
    let newSongs = MusicResource<[MusicSong]>()
    let dailySongs = MusicResource<[MusicSong]>()
    let recentHistory = MusicResource<[MusicHistoryRecord]>()
    let playlists = MusicResource<[UserMusicPlaylist]>()
    let history = MusicResource<MusicHistoryPage>()
    private(set) var playlistDetails: [Int: MusicResource<UserMusicPlaylistDetail>] = [:]
    private(set) var recommendedTracks: [Int: MusicResource<[MusicSong]>] = [:]
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
    }

    var sessionToken: UUID { generation }

    func reset(for userID: Int?) {
        guard self.userID != userID else { return }
        self.userID = userID
        generation = UUID()
        historyRevision = UUID()
        hotSearch.reset(); recommendedPlaylists.reset(); newSongs.reset(); dailySongs.reset()
        recentHistory.reset(); playlists.reset(); history.reset()
        for resource in playlistDetails.values { resource.reset() }
        for resource in recommendedTracks.values { resource.reset() }
        playlistDetails.removeAll(); recommendedTracks.removeAll()
        isLoadingMore = false
        historyMoreError = nil
        // Swap synchronously: no new-user read can race asynchronous cache clearing.
        let previous = repository
        repository = MusicRepository(client: client, now: now)
        searchSession.reset(repository: repository)
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

    func loadHome(force: Bool = false) async {
        async let hot: Void = load(hotSearch, .hotSearch, force: force)
        async let recommended: Void = load(recommendedPlaylists, .recommendedPlaylists, force: force)
        async let new: Void = load(newSongs, .newSongs, force: force)
        async let daily: Void = load(dailySongs, .dailySongs, force: force)
        async let recent: Void = load(recentHistory, .history(limit: 8), force: force)
        async let lists: Void = loadPlaylists(force: force)
        _ = await (hot, recommended, new, daily, recent, lists)
    }

    func loadPlaylists(force: Bool = false) async { await load(playlists, .playlists, force: force) }
    func loadDetail(_ id: Int, force: Bool = false) async { await load(detail(id), .playlist(id), force: force) }
    func loadTracks(_ id: Int, force: Bool = false) async { await load(tracks(id), .recommendedTracks(id), force: force) }

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
        try await write(keys: [.playlists, .playlist(id)]) { try await $0.add(request, toPlaylist: id) }
        let knownSongs = playlistDetails[id]?.value?.songs
        let knownCount = knownSongs.map { songs in songs.count + (songs.contains { $0.songId == request.songId } ? 0 : 1) }
        patchPlaylist(id, list: { $0.songCount = knownCount ?? (($0.songCount ?? 0) + 1) }, detail: {
            var songs = $0.songs ?? []
            if !songs.contains(where: { $0.songId == request.songId }) { songs.append(PlaylistSong(local: request)) }
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
