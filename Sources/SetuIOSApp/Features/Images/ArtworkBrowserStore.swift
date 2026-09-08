import Foundation
import Observation
import SetuIOSCore

@MainActor
@Observable
final class ArtworkChannelState {
    var items: [BrowserArtwork] = []
    var cursor: String?
    var loaded = false
    var loading = false
    var error: String?
    var query = ""
    var tag = ""
    var view = "recommended"
    var sort = "latest"
    var sourceFilter = "ALL"
    var ranking = "day"
    var artistID = ""
    var r18 = 0
    var excludeAI = true
    var scrollID: String?
    var generation = UUID()
}

@MainActor
@Observable
final class ArtworkBrowserStore {
    let client: ArtworkClient
    let images: ArtworkImageStore
    var importTasks: [String: String] = [:]
    private var details: [String: BrowserArtwork] = [:]
    private var detailOrder: [String] = []

    func cachedDetail(source: ArtworkSource, id: String) -> BrowserArtwork? {
        details["\(source.rawValue):\(id)"]
    }
    func rememberDetail(_ work: BrowserArtwork) {
        let key = work.transitionID
        details[key] = work
        detailOrder.removeAll { $0 == key }; detailOrder.append(key)
        while detailOrder.count > 24 { details[detailOrder.removeFirst()] = nil }
        update(work)
    }

    var pixiv = ArtworkChannelState()
    var gallery = ArtworkChannelState()
    var binding: PixivAccountBinding?
    var artists: [ArtworkArtist] = []
    var spotlights: [ArtworkSpotlight] = []
    var accountError: String?
    var homeError: String?
    var busyIDs: Set<String> = []
    private var accountGeneration = UUID()

    init(client: ArtworkClient) {
        self.client = client
        images = ArtworkImageStore(fetch: { try await client.media($0) })
    }
    func prefetchNeighbors(source: ArtworkSource, id: String) async {
        let items = state(source).items
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let neighbors = [index - 1, index + 1].filter { items.indices.contains($0) }.map { items[$0] }
        await withTaskGroup(of: Void.self) { group in
            for work in neighbors {
                guard let page = work.pages.first, let path = page.previewUrl else { continue }
                group.addTask { [images] in
                    _ = try? await images.load(path, identity: work.imageIdentity(page), quality: .preview)
                }
            }
        }
    }
    func state(_ source: ArtworkSource) -> ArtworkChannelState { source == .pixiv ? pixiv : gallery }

    func load(_ source: ArtworkSource, reset: Bool = false) async {
        let state = state(source)
        guard reset || (!state.loading && (!state.loaded || state.cursor != nil)) else { return }
        guard source != .pixiv || binding?.bound == true else { return }
        let generation = UUID()
        state.generation = generation
        state.loading = true
        state.error = nil
        if reset { state.items = []; state.cursor = nil; state.loaded = false; state.scrollID = nil }
        var params = ["view": state.query.isEmpty ? state.view : "search", "query": state.query,
                      "tag": state.tag, "sort": state.sort, "source": state.sourceFilter, "ranking": state.ranking, "authorId": state.artistID,
                      "r18": String(state.r18), "excludeAI": String(state.excludeAI)]
        params["cursor"] = state.cursor
        defer { if state.generation == generation { state.loading = false } }
        do {
            let page = try await client.works(source: source, params: params)
            guard state.generation == generation, !Task.isCancelled else { return }
            let seen = Set(state.items.map(\.id))
            state.items += page.items.filter { !seen.contains($0.id) }
            if state.items.count > 240 { state.items.removeFirst(state.items.count - 240) }
            state.cursor = page.nextCursor
            state.loaded = true
        } catch is CancellationError { }
        catch { if state.generation == generation { state.error = error.localizedDescription } }
    }

    func loadAccount() async {
        let generation = UUID()
        accountGeneration = generation
        accountError = nil
        do {
            let result = try await client.binding()
            guard accountGeneration == generation, !Task.isCancelled else { return }
            if binding?.version != result.version || binding?.bound != result.bound {
                images.clear(); details.removeAll(); detailOrder.removeAll()
                pixiv.generation = UUID()
                pixiv = ArtworkChannelState()
                artists = []; spotlights = []
            }
            binding = result
            guard result.bound else { return }
            await load(.pixiv)
            async let artistResult = fetchArtists()
            async let spotlightResult = fetchSpotlights()
            let results = await (artistResult, spotlightResult)
            guard accountGeneration == generation, !Task.isCancelled else { return }
            artists = results.0 ?? []
            spotlights = results.1 ?? []
            homeError = results.0 == nil || results.1 == nil ? "部分推荐暂不可用，下拉刷新可重试" : nil
        } catch { if accountGeneration == generation { accountError = error.localizedDescription } }
    }
    private func fetchArtists() async -> [ArtworkArtist]? { try? await client.artists() }
    private func fetchSpotlights() async -> [ArtworkSpotlight]? { try? await client.spotlights() }

    func bookmark(_ work: BrowserArtwork) async throws {
        guard !busyIDs.contains(work.id) else { return }
        busyIDs.insert(work.id)
        defer { busyIDs.remove(work.id) }
        try await client.bookmark(work, enabled: !work.bookmarked)
        var updated = work; updated.bookmarked.toggle(); update(updated)
    }
    func update(_ work: BrowserArtwork) {
        if details[work.transitionID] != nil { details[work.transitionID] = work }
        let state = state(work.source)
        if let index = state.items.firstIndex(where: { $0.id == work.id }) { state.items[index] = work }
    }
    func selectArtist(_ id: String) async {
        pixiv.artistID = id; pixiv.view = "artist"; pixiv.query = ""
        await load(.pixiv, reset: true)
    }
    func selectTag(_ tag: String, source: ArtworkSource) async {
        if source == .pixiv { pixiv.query = tag }
        else { gallery.tag = tag }
        await load(source, reset: true)
    }
}
