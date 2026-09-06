import Foundation
import Observation
import SetuIOSCore

struct MusicSongRowModel: Identifiable, Sendable {
    let song: MusicSong
    let title: String
    let artist: String
    let album: String
    let coverURLString: String?
    let hasMV: Bool
    var id: Int { song.id }

    init(song: MusicSong) {
        self.song = song
        title = song.name
        let names = song.artistNames
        artist = names.isEmpty ? "未知歌手" : names
        album = song.albumName
        coverURLString = song.coverURLString
        hasMV = (song.mv ?? 0) > 0
    }
}

enum MusicSearchSegment: String, CaseIterable, Identifiable {
    case songs, artists, albums
    var id: String { rawValue }
    var title: String {
        switch self { case .songs: "歌曲"; case .artists: "歌手"; case .albums: "专辑" }
    }
}

struct MusicSearchAggregateItem: Identifiable, Equatable, Sendable {
    let title: String
    let count: Int
    var id: String { title }
}

/// One UI session per MusicStore. Paging owns the result rows; the repository owns API pages.
/// Navigation does not cancel this session. Query changes and account reset do.
@MainActor @Observable
final class MusicSearchSession {
    var query = "" { didSet { if normalizedQuery != oldValue.trimmingCharacters(in: .whitespacesAndNewlines) { inputChanged() } } }
    var selectedSegment: MusicSearchSegment = .songs
    let pager = PagingController<MusicSongRowModel>(pageSize: 10)
    private(set) var executedKeyword = ""
    private(set) var resultKeyword = ""
    private(set) var artistItems: [MusicSearchAggregateItem] = []
    private(set) var albumItems: [MusicSearchAggregateItem] = []
    private(set) var resultsRevision = 0
    private(set) var isSearching = false
    private(set) var history: [String]
    @ObservationIgnored private var repository: MusicRepository
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let makeQuery: @Sendable (String, Int, Int) -> MusicQuery<MusicSearchResult>
    @ObservationIgnored private let historyDefaults: UserDefaults
    @ObservationIgnored private var fetchedAt: Date?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var activatedRouteID: UUID?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var pageTask: Task<Void, Never>?

    init(repository: MusicRepository, now: @escaping @Sendable () -> Date = { Date() },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         historyDefaults: UserDefaults = .standard,
         makeQuery: @escaping @Sendable (String, Int, Int) -> MusicQuery<MusicSearchResult> = {
             .search(keywords: $0, offset: $1, limit: $2)
         }) {
        self.repository = repository
        self.now = now
        self.sleep = sleep
        self.makeQuery = makeQuery
        self.historyDefaults = historyDefaults
        history = historyDefaults.stringArray(forKey: Self.historyKey) ?? []
    }

    deinit { debounceTask?.cancel(); searchTask?.cancel(); pageTask?.cancel() }

    var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var showsSkeleton: Bool { isSearching && pager.items.isEmpty }
    var hasResults: Bool { !pager.items.isEmpty }
    var canLoadMore: Bool {
        !isSearching && normalizedQuery == resultKeyword && !resultKeyword.isEmpty && pager.hasMore
    }

    func activate(initialQuery: String?, routeID: UUID = UUID()) async {
        let isNewRoute = activatedRouteID != routeID
        activatedRouteID = routeID
        if isNewRoute, let initialQuery, !initialQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            query = initialQuery
        }
        if !normalizedQuery.isEmpty { await submit() }
    }

    private func inputChanged() {
        cancelWork()
        guard !normalizedQuery.isEmpty else {
            pager.invalidate(clearExisting: true)
            executedKeyword = ""; resultKeyword = ""; fetchedAt = nil
            rebuildAggregates()
            return
        }
        let ticket = generation
        let sleep = sleep
        debounceTask = Task { [weak self] in
            do { try await sleep(.milliseconds(400)) } catch { return }
            guard !Task.isCancelled, self?.generation == ticket else { return }
            let work = self?.startSearch()
            await work?.value
        }
    }

    func submit() async {
        let started = ProcessInfo.processInfo.systemUptime
        let work = startSearch()
        await work?.value
        if work != nil, pager.initialError == nil { MusicClientObservation.emit("search.ready", start: started, v2: false) }
    }

    private func startSearch() -> Task<Void, Never>? {
        debounceTask?.cancel(); debounceTask = nil
        let keyword = normalizedQuery
        guard !keyword.isEmpty else { return nil }
        let updatedHistory = Array(([keyword] + history.filter { $0 != keyword }).prefix(10))
        if updatedHistory != history {
            history = updatedHistory
            historyDefaults.set(history, forKey: Self.historyKey)
        }
        if executedKeyword == keyword, let searchTask { return searchTask }
        if resultKeyword == keyword, pager.initialError == nil,
           let fetchedAt, now().timeIntervalSince(fetchedAt) < MusicCacheKey.search(keywords: keyword, offset: 0, limit: 10).ttl {
            return nil
        }
        cancelWork()
        executedKeyword = keyword
        isSearching = true
        let ticket = generation
        let repository = repository
        let request = makeQuery(keyword, 0, pager.pageSize)
        let pager = pager
        let now = now
        let work = Task { [weak self] in
            // Cached pages become visible before any stale revalidation begins.
            if let cached = await repository.cached(for: request) {
                guard !Task.isCancelled, self?.generation == ticket else { return }
                if self?.resultKeyword != keyword {
                    await pager.loadFirstPage { _ in Self.page(cached.value, offset: 0) }
                    self?.publish(keyword: keyword, date: cached.fetchedAt)
                }
                if now().timeIntervalSince(cached.fetchedAt) < request.key.ttl {
                    self?.finishSearch(ticket: ticket)
                    return
                }
            }
            guard !Task.isCancelled, self?.generation == ticket else { return }
            var date: Date?
            await pager.loadFirstPage { _ in
                let result = try await repository.value(for: request)
                try Task.checkCancellation()
                date = result.fetchedAt
                return Self.page(result.value, offset: 0)
            }
            guard !Task.isCancelled, self?.generation == ticket else { return }
            if let date { self?.publish(keyword: keyword, date: date) }
            self?.finishSearch(ticket: ticket)
        }
        searchTask = work
        return work
    }

    /// Called for a genuinely visible near-end row (or the explicit retry footer).
    func loadMore(near rowID: Int? = nil) async {
        guard canLoadMore, pageTask == nil, pager.phase == .idle else { return }
        if let rowID {
            guard pager.loadMoreError == nil, pager.items.suffix(3).contains(where: { $0.id == rowID }) else { return }
        }
        let ticket = generation
        let keyword = resultKeyword
        let repository = repository
        let pager = pager
        let makeQuery = makeQuery
        let work = Task { [weak self] in
            await pager.loadMore { page in
                let offset = (page - 1) * pager.pageSize
                let result = try await repository.value(for: makeQuery(keyword, offset, pager.pageSize))
                try Task.checkCancellation()
                return Self.page(result.value, offset: offset)
            }
            guard !Task.isCancelled, self?.generation == ticket else { return }
            if pager.loadMoreError == nil { self?.rebuildAggregates() }
            self?.pageTask = nil
        }
        pageTask = work
        await work.value
    }

    func reset(repository: MusicRepository) {
        cancelWork()
        query = ""
        self.repository = repository
        pager.invalidate(clearExisting: true)
        executedKeyword = ""; resultKeyword = ""; fetchedAt = nil
        selectedSegment = .songs
        // Keep the established device history preference; no prior user's active results survive.
        rebuildAggregates()
    }

    func removeHistory(_ keyword: String) {
        history.removeAll { $0 == keyword }
        historyDefaults.set(history, forKey: Self.historyKey)
    }

    func clearHistory() {
        history = []
        historyDefaults.removeObject(forKey: Self.historyKey)
    }

    private static let historyKey = "icu.yukiryou.setu.musicSearchHistory"

    private func cancelWork() {
        generation = UUID()
        debounceTask?.cancel(); debounceTask = nil
        searchTask?.cancel(); searchTask = nil
        pageTask?.cancel(); pageTask = nil
        pager.invalidate()
        isSearching = false
    }

    private func finishSearch(ticket: UUID) {
        guard generation == ticket else { return }
        isSearching = false
        searchTask = nil
    }

    private func publish(keyword: String, date: Date) {
        resultKeyword = keyword
        fetchedAt = date
        rebuildAggregates()
    }

    private func rebuildAggregates() {
        artistItems = Self.aggregate(pager.items.flatMap {
            $0.artist == "未知歌手" ? [] : $0.artist.split(separator: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        })
        albumItems = Self.aggregate(pager.items.map(\.album).filter { $0 != "未知专辑" && !$0.isEmpty })
        resultsRevision += 1
    }

    private static func aggregate(_ values: [String]) -> [MusicSearchAggregateItem] {
        var counts: [String: Int] = [:]
        for value in values where !value.isEmpty { counts[value, default: 0] += 1 }
        return counts.map { MusicSearchAggregateItem(title: $0.key, count: $0.value) }.sorted {
            $0.count == $1.count ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.count > $1.count
        }
    }

    private static func page(_ result: MusicSearchResult, offset: Int) -> PagingController<MusicSongRowModel>.PageResult {
        .init(items: result.result.songs.map(MusicSongRowModel.init), total: result.result.songCount,
              hasMore: !result.result.songs.isEmpty && offset + result.result.songs.count < result.result.songCount)
    }
}
