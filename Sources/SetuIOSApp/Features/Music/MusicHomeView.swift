import SetuIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct MusicHomeView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    @State private var query = ""
    @State private var hotState: LoadState<[MusicHotSearchItem]> = .idle
    @State private var recommendedPlaylistState: LoadState<[MusicRecommendedPlaylist]> = .idle
    @State private var newSongsState: LoadState<[MusicSong]> = .idle
    @State private var dailySongsState: LoadState<[MusicSong]> = .idle
    @State private var searchState: LoadState<MusicSearchResultState> = .idle
    @State private var selectedSong: MusicSong?
    @State private var mvSong: MusicSong?
    @State private var selectedRecommendedPlaylist: MusicRecommendedPlaylist?
    @State private var playbackMessage: String?
    @State private var searchPage = 1
    @State private var searchKeyword = ""
    @State private var searchHistory: [String] = MusicSearchHistoryStore.load()

    private let searchHistoryLimit = 10
    private let searchPageSize = 10

    var body: some View {
        List {
            Section {
                Button {
                    router.navigate(to: .playlists)
                } label: {
                    Label("我的歌单", systemImage: "music.note.list")
                }
                Button {
                    router.navigate(to: .musicHistory)
                } label: {
                    Label("播放历史", systemImage: "clock.arrow.circlepath")
                }
            }

            Section("搜索") {
                TextField("歌曲、歌手或专辑", text: $query)
                    .modifier(MusicSearchInputModifier())
                    .onSubmit {
                        Task { await search() }
                    }
                Button("搜索音乐") {
                    Task { await search() }
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            nowPlayingSection
            recommendationsContent
            searchHistorySection
            searchContent
            hotSearchContent
        }
        .navigationTitle("音乐")
        .sheet(item: $selectedSong) { song in
            AddSongToPlaylistSheet(environment: environment, song: song)
        }
        .sheet(item: $mvSong) { song in
            MusicMvSheet(environment: environment, song: song)
        }
        .sheet(item: $selectedRecommendedPlaylist) { playlist in
            RecommendedPlaylistSheet(environment: environment, player: player, playlist: playlist)
        }
        .task { await loadLandingContent() }
        .refreshable { await loadLandingContent() }
    }

    @ViewBuilder
    private var searchHistorySection: some View {
        if !searchHistory.isEmpty {
            Section {
                ForEach(searchHistory, id: \.self) { keyword in
                    HStack {
                        Button {
                            query = keyword
                            Task { await search() }
                        } label: {
                            Label(keyword, systemImage: "clock.arrow.circlepath")
                        }
                        Spacer()
                        Button(role: .destructive) {
                            removeSearchHistory(keyword)
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button(role: .destructive) {
                    clearSearchHistory()
                } label: {
                    Label("清空搜索历史", systemImage: "trash")
                }
            } header: {
                Text("搜索历史")
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        switch searchState {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView("正在搜索")
        case .failed(let message):
            Section {
                Text(message)
                    .foregroundStyle(.red)
            }
        case .loaded(let result):
            Section("搜索结果 \(result.songs.count)/\(result.total)") {
                if result.songs.isEmpty {
                    ContentUnavailableView("没有找到音乐", systemImage: "magnifyingglass")
                } else {
                    ForEach(result.songs) { song in
                        MusicSongRow(song: song) {
                            Task { await play(song, queueName: "搜索结果") }
                        } onPlayMv: {
                            mvSong = song
                        } onAddToPlaylist: {
                            selectedSong = song
                        } onDownload: {
                            Task { await download(song) }
                        }
                    }
                    if result.hasMore {
                        Button {
                            Task { await loadMoreSearchResults() }
                        } label: {
                            Label("加载更多 (\(result.songs.count)/\(result.total))", systemImage: "plus.circle")
                        }
                    } else {
                        Label("已加载全部 \(result.total) 首歌曲", systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var nowPlayingSection: some View {
        if let track = player.currentTrack {
            Section("正在播放") {
                HStack(spacing: 12) {
                    MusicArtworkView(urlString: track.coverURLString)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text(track.artist)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let message = playbackMessage ?? player.message {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        player.toggle()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    Button(role: .destructive) {
                        player.stop()
                    } label: {
                        Image(systemName: "stop.circle")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                }
            }
        } else if let playbackMessage {
            Section {
                Text(playbackMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var hotSearchContent: some View {
        switch hotState {
        case .idle, .loading:
            ProgressView("正在加载热门搜索")
        case .failed(let message):
            Section("热门搜索") {
                Text(message)
                    .foregroundStyle(.red)
            }
        case .loaded(let hots):
            if !hots.isEmpty {
                Section("热门搜索") {
                    ForEach(hots.prefix(10)) { item in
                        Button {
                            query = item.first
                            Task { await search() }
                        } label: {
                            HStack {
                                Text(item.first)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if let score = item.second {
                                    Text("\(score)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recommendationsContent: some View {
        Section("推荐新歌") {
            switch newSongsState {
            case .idle, .loading:
                ProgressView("正在加载推荐新歌")
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
            case .loaded(let songs):
                if songs.isEmpty {
                    ContentUnavailableView("暂无推荐新歌", systemImage: "music.note")
                } else {
                    ForEach(songs.prefix(5)) { song in
                        MusicSongRow(song: song) {
                            Task { await play(song, queueName: "推荐新歌") }
                        } onPlayMv: {
                            mvSong = song
                        } onAddToPlaylist: {
                            selectedSong = song
                        } onDownload: {
                            Task { await download(song) }
                        }
                    }
                }
            }
        }

        Section("每日推荐") {
            switch dailySongsState {
            case .idle, .loading:
                ProgressView("正在加载每日推荐")
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
            case .loaded(let songs):
                if songs.isEmpty {
                    ContentUnavailableView("暂无每日推荐", systemImage: "sparkles")
                } else {
                    ForEach(songs.prefix(5)) { song in
                        MusicSongRow(song: song) {
                            Task { await play(song, queueName: "每日推荐") }
                        } onPlayMv: {
                            mvSong = song
                        } onAddToPlaylist: {
                            selectedSong = song
                        } onDownload: {
                            Task { await download(song) }
                        }
                    }
                }
            }
        }

        Section("推荐歌单") {
            switch recommendedPlaylistState {
            case .idle, .loading:
                ProgressView("正在加载推荐歌单")
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
            case .loaded(let playlists):
                if playlists.isEmpty {
                    ContentUnavailableView("暂无推荐歌单", systemImage: "music.note.list")
                } else {
                    ForEach(playlists.prefix(6)) { playlist in
                        Button {
                            selectedRecommendedPlaylist = playlist
                        } label: {
                            RecommendedPlaylistRow(playlist: playlist)
                        }
                    }
                }
            }
        }
    }

    private func loadLandingContent() async {
        async let hot: Void = loadHotSearch()
        async let recommended: Void = loadRecommendations()
        _ = await (hot, recommended)
    }

    private func loadHotSearch() async {
        hotState = .loading
        do {
            hotState = .loaded(try await environment.musicClient.hotSearch().result.hots)
        } catch {
            hotState = .failed(error.localizedDescription)
        }
    }

    private func loadRecommendations() async {
        recommendedPlaylistState = .loading
        newSongsState = .loading
        dailySongsState = .loading

        async let playlists = environment.musicClient.personalizedPlaylists(limit: 6)
        async let newSongs = environment.musicClient.personalizedNewSongs()
        async let dailySongs = environment.musicClient.recommendSongs()

        do {
            recommendedPlaylistState = .loaded(try await playlists.result)
        } catch {
            recommendedPlaylistState = .failed(error.localizedDescription)
        }

        do {
            newSongsState = .loaded(try await newSongs.result)
        } catch {
            newSongsState = .failed(error.localizedDescription)
        }

        do {
            dailySongsState = .loaded(try await dailySongs.data.dailySongs)
        } catch {
            dailySongsState = .failed(error.localizedDescription)
        }
    }

    private func search() async {
        let keywords = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keywords.isEmpty else { return }
        saveSearchHistory(keywords)
        searchKeyword = keywords
        searchPage = 1
        searchState = .loading
        do {
            let result = try await environment.musicClient.search(keywords: keywords, limit: searchPageSize, offset: 0)
            searchState = .loaded(MusicSearchResultState(result: result))
        } catch {
            searchState = .failed(error.localizedDescription)
        }
    }

    private func loadMoreSearchResults() async {
        guard case .loaded(let current) = searchState, current.hasMore else { return }
        searchPage += 1
        do {
            let result = try await environment.musicClient.search(
                keywords: searchKeyword,
                limit: searchPageSize,
                offset: (searchPage - 1) * searchPageSize
            )
            searchState = .loaded(current.appending(result))
        } catch {
            searchState = .failed(error.localizedDescription)
        }
    }

    private func saveSearchHistory(_ keyword: String) {
        let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let nextHistory = [normalized] + searchHistory.filter { $0 != normalized }
        searchHistory = Array(nextHistory.prefix(searchHistoryLimit))
        MusicSearchHistoryStore.save(searchHistory)
    }

    private func removeSearchHistory(_ keyword: String) {
        searchHistory.removeAll { $0 == keyword }
        MusicSearchHistoryStore.save(searchHistory)
    }

    private func clearSearchHistory() {
        searchHistory = []
        MusicSearchHistoryStore.clear()
    }

    private func play(_ song: MusicSong, queueName: String? = nil) async {
        playbackMessage = "正在获取播放地址"
        do {
            let response = try await environment.musicClient.url(songID: song.id, level: "standard")
            guard let item = response.data?.first, let urlString = item.playableURLString, let url = URL(string: urlString) else {
                playbackMessage = response.data?.first?.unavailableMessage ?? response.playabilityReason ?? response.message ?? "暂无可播放地址"
                return
            }
            player.play(url: url, track: MusicPlaybackTrack(song: song), queueName: queueName)
            try? await environment.musicClient.addHistory(song: song)
            playbackMessage = "已开始播放"
        } catch {
            playbackMessage = error.localizedDescription
        }
    }

    private func download(_ song: MusicSong) async {
        playbackMessage = "正在准备下载"
        do {
            let response = try await environment.musicClient.url(songID: song.id, level: "exhigh")
            guard let item = response.data?.first, let urlString = item.playableURLString else {
                playbackMessage = response.data?.first?.unavailableMessage ?? response.playabilityReason ?? response.message ?? "暂无可下载地址"
                return
            }
            let signed = try await environment.downloadClient.sign(url: urlString, filename: downloadFilename(for: song))
            guard let url = URL(string: signed.downloadUrl) else {
                playbackMessage = "下载地址无效"
                return
            }
            openExternalURL(url)
            playbackMessage = "已打开下载地址"
        } catch {
            playbackMessage = error.localizedDescription
        }
    }

    private func downloadFilename(for song: MusicSong) -> String {
        let artists = song.artistNames.isEmpty ? "未知歌手" : song.artistNames.replacingOccurrences(of: " / ", with: ", ")
        return "\(song.name) - \(artists).mp3"
    }

    private func openExternalURL(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #endif
    }
}

private struct RecommendedPlaylistRow: View {
    let playlist: MusicRecommendedPlaylist

    var body: some View {
        HStack(spacing: 12) {
            MusicArtworkView(urlString: playlist.picUrl)
            VStack(alignment: .leading, spacing: 5) {
                Text(playlist.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let description = playlist.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let playCount = playlist.playCount {
                    Label(formatPlayCount(playCount), systemImage: "play.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formatPlayCount(_ value: Int) -> String {
        if value >= 10_000 {
            return "\(value / 10_000) 万次播放"
        }
        return "\(value) 次播放"
    }
}

private struct RecommendedPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    let playlist: MusicRecommendedPlaylist

    @State private var state: LoadState<[MusicSong]> = .idle
    @State private var selectedSong: MusicSong?
    @State private var mvSong: MusicSong?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section("歌单") {
                    RecommendedPlaylistRow(playlist: playlist)
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                switch state {
                case .idle, .loading:
                    ProgressView("正在加载歌单歌曲")
                case .failed(let message):
                    ContentUnavailableView("歌单加载失败", systemImage: "music.note.list", description: Text(message))
                case .loaded(let songs):
                    if songs.isEmpty {
                        ContentUnavailableView("暂无歌曲", systemImage: "music.note")
                    } else {
                        Section("歌曲") {
                            ForEach(songs) { song in
                                MusicSongRow(song: song) {
                                    Task { await play(song) }
                                } onPlayMv: {
                                    mvSong = song
                                } onAddToPlaylist: {
                                    selectedSong = song
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(playlist.name)
            .toolbar {
                Button("关闭") {
                    dismiss()
                }
            }
            .sheet(item: $selectedSong) { song in
                AddSongToPlaylistSheet(environment: environment, song: song)
            }
            .sheet(item: $mvSong) { song in
                MusicMvSheet(environment: environment, song: song)
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.musicClient.playlistTracks(id: playlist.id).songs)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func play(_ song: MusicSong) async {
        message = "正在获取播放地址"
        do {
            let response = try await environment.musicClient.url(songID: song.id, level: "standard")
            guard let item = response.data?.first, let urlString = item.playableURLString, let url = URL(string: urlString) else {
                message = response.data?.first?.unavailableMessage ?? response.playabilityReason ?? response.message ?? "暂无可播放地址"
                return
            }
            player.play(url: url, track: MusicPlaybackTrack(song: song), queueName: playlist.name)
            try? await environment.musicClient.addHistory(song: song)
            message = "已开始播放《\(playlist.name)》"
        } catch {
            message = error.localizedDescription
        }
    }
}

private enum MusicSearchHistoryStore {
    private static let key = "icu.yukiryou.setu.musicSearchHistory"

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func save(_ history: [String]) {
        UserDefaults.standard.set(history, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

private struct MusicSearchResultState: Sendable {
    let songs: [MusicSong]
    let total: Int

    var hasMore: Bool {
        songs.count < total
    }

    init(result: MusicSearchResult) {
        self.songs = result.result.songs
        self.total = result.result.songCount
    }

    private init(songs: [MusicSong], total: Int) {
        self.songs = songs
        self.total = total
    }

    func appending(_ result: MusicSearchResult) -> MusicSearchResultState {
        MusicSearchResultState(
            songs: songs + result.result.songs,
            total: result.result.songCount
        )
    }
}

private struct MusicSearchInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.textInputAutocapitalization(.never)
        #else
        content
        #endif
    }
}

struct MusicSongRow: View {
    let song: MusicSong
    var onPlay: (() -> Void)?
    var onPlayMv: (() -> Void)?
    var onAddToPlaylist: (() -> Void)?
    var onDownload: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            MusicArtworkView(urlString: song.coverURLString)
            VStack(alignment: .leading, spacing: 5) {
                Text(song.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(song.artistNames.isEmpty ? "未知歌手" : song.artistNames)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(song.albumName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 10) {
                if let onPlay {
                    Button(action: onPlay) {
                        Image(systemName: "play.circle")
                    }
                    .buttonStyle(.borderless)
                }
                if song.mv ?? 0 > 0 {
                    if let onPlayMv {
                        Button(action: onPlayMv) {
                            Image(systemName: "play.rectangle")
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Image(systemName: "play.rectangle")
                            .foregroundStyle(.pink)
                    }
                }
                if let onAddToPlaylist {
                    Button(action: onAddToPlaylist) {
                        Image(systemName: "text.badge.plus")
                    }
                    .buttonStyle(.borderless)
                }
                if let onDownload {
                    Button(action: onDownload) {
                        Image(systemName: "arrow.down.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct MusicArtworkView: View {
    let urlString: String?

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.pink.opacity(0.12))
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(.pink)
            }
    }
}

struct AddSongToPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let song: MusicSong
    @State private var state: LoadState<[UserMusicPlaylist]> = .idle
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section("歌曲") {
                    MusicSongRow(song: song)
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                switch state {
                case .idle, .loading:
                    ProgressView("正在加载歌单")
                case .failed(let message):
                    ContentUnavailableView("歌单加载失败", systemImage: "music.note.list", description: Text(message))
                case .loaded(let playlists):
                    if playlists.isEmpty {
                        ContentUnavailableView("暂无歌单", systemImage: "music.note.list")
                    } else {
                        Section("选择歌单") {
                            ForEach(playlists) { playlist in
                                Button {
                                    Task { await add(to: playlist) }
                                } label: {
                                    Text(playlist.name)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("加入歌单")
            .toolbar {
                Button("关闭") {
                    dismiss()
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.musicClient.playlists())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func add(to playlist: UserMusicPlaylist) async {
        do {
            try await environment.musicClient.add(song: song, toPlaylist: playlist.id)
            message = "已加入 \(playlist.name)"
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct MusicPlaybackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let song: MusicSong

    @State private var quality = "standard"
    @State private var urlState: LoadState<MusicUrlItem?> = .idle
    @State private var lyricState: LoadState<MusicLyricResponse> = .idle
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section("歌曲") {
                    MusicSongRow(song: song)
                    Picker("音质", selection: $quality) {
                        Text("standard").tag("standard")
                        Text("higher").tag("higher")
                        Text("exhigh").tag("exhigh")
                        Text("lossless").tag("lossless")
                        Text("hires").tag("hires")
                    }
                    .onChange(of: quality) {
                        Task { await loadPlayback() }
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                playbackSection
                lyricSection
            }
            .navigationTitle("播放信息")
            .toolbar {
                Button("关闭") {
                    dismiss()
                }
            }
            .task {
                await load()
            }
            .refreshable {
                await load()
            }
        }
    }

    @ViewBuilder
    private var playbackSection: some View {
        Section("播放地址") {
            switch urlState {
            case .idle, .loading:
                ProgressView("正在获取播放地址")
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
            case .loaded(let item):
                if let item, let urlString = item.playableURLString, let url = URL(string: urlString) {
                    LabeledContent("状态", value: "完整可播")
                    if let level = item.level {
                        LabeledContent("音质", value: level)
                    }
                    if let size = item.size {
                        LabeledContent("大小", value: "\(size)")
                    }
                    Link(destination: url) {
                        Label("打开播放地址", systemImage: "arrow.up.forward.square")
                    }
                    Button {
                        Task { await recordHistory() }
                    } label: {
                        Label("记录播放", systemImage: "clock.arrow.circlepath")
                    }
                } else if let item {
                    LabeledContent("状态", value: item.playability ?? "不可播放")
                    Text(item.unavailableMessage)
                        .foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("暂无播放地址", systemImage: "music.note")
                }
            }
        }
    }

    @ViewBuilder
    private var lyricSection: some View {
        Section("歌词") {
            switch lyricState {
            case .idle, .loading:
                ProgressView("正在加载歌词")
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
            case .loaded(let lyric):
                let rawLyric = lyric.lrc?.lyric ?? ""
                let translation = lyric.tlyric?.lyric ?? ""
                if rawLyric.isEmpty && translation.isEmpty {
                    ContentUnavailableView("暂无歌词", systemImage: "text.quote")
                } else {
                    if !rawLyric.isEmpty {
                        Text(rawLyric)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                    if !translation.isEmpty {
                        DisclosureGroup("翻译歌词") {
                            Text(translation)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        await loadPlayback()
        await loadLyric()
    }

    private func loadPlayback() async {
        urlState = .loading
        do {
            let response = try await environment.musicClient.url(songID: song.id, level: quality)
            urlState = .loaded(response.data?.first)
        } catch {
            urlState = .failed(error.localizedDescription)
        }
    }

    private func loadLyric() async {
        lyricState = .loading
        do {
            lyricState = .loaded(try await environment.musicClient.lyric(songID: song.id))
        } catch {
            lyricState = .failed(error.localizedDescription)
        }
    }

    private func recordHistory() async {
        do {
            try await environment.musicClient.addHistory(song: song)
            message = "已记录到播放历史"
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct MusicMvSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let song: MusicSong

    @State private var detailState: LoadState<MusicMvDetail> = .idle
    @State private var urlState: LoadState<MusicMvUrlData?> = .idle
    @State private var selectedResolution: Int?

    var body: some View {
        NavigationStack {
            List {
                Section("歌曲") {
                    MusicSongRow(song: song)
                }

                detailSection
                urlSection
            }
            .navigationTitle("MV")
            .toolbar {
                Button("关闭") {
                    dismiss()
                }
            }
            .task {
                await load()
            }
            .refreshable {
                await load()
            }
        }
    }

    @ViewBuilder
    private var detailSection: some View {
        Section("MV 详情") {
            switch detailState {
            case .idle, .loading:
                ProgressView("正在加载 MV 详情")
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
            case .loaded(let detail):
                if let cover = detail.cover {
                    MusicMvCoverView(urlString: cover)
                }
                LabeledContent("标题", value: detail.name)
                LabeledContent("艺人", value: detail.artistName ?? detail.artists?.map(\.name).joined(separator: " / ") ?? song.artistNames)
                if let publishTime = detail.publishTime {
                    LabeledContent("发布时间", value: publishTime)
                }
                if let playCount = detail.playCount {
                    LabeledContent("播放量", value: "\(playCount)")
                }
                if let duration = detail.duration {
                    LabeledContent("时长", value: formatDuration(duration))
                }
                if let description = detail.desc ?? detail.briefDesc, !description.isEmpty {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let brs = detail.brs, !brs.isEmpty {
                    Picker("清晰度", selection: $selectedResolution) {
                        Text("默认").tag(Optional<Int>.none)
                        ForEach(brs) { quality in
                            Text("\(quality.br)p").tag(Optional(quality.br))
                        }
                    }
                    .onChange(of: selectedResolution) {
                        Task { await loadUrl() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var urlSection: some View {
        Section("播放地址") {
            switch urlState {
            case .idle, .loading:
                ProgressView("正在获取 MV 地址")
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
            case .loaded(let data):
                if let data, let urlString = data.httpsURLString, let url = URL(string: urlString) {
                    if let resolution = data.r ?? data.br {
                        LabeledContent("清晰度", value: "\(resolution)p")
                    }
                    if let size = data.size {
                        LabeledContent("大小", value: "\(size)")
                    }
                    if let type = data.type {
                        LabeledContent("类型", value: type)
                    }
                    Link(destination: url) {
                        Label("打开 MV 播放地址", systemImage: "arrow.up.forward.square")
                    }
                } else {
                    ContentUnavailableView("暂无 MV 地址", systemImage: "play.rectangle")
                }
            }
        }
    }

    private func load() async {
        guard let mvID = song.mv, mvID > 0 else {
            detailState = .failed("该歌曲没有 MV")
            urlState = .failed("该歌曲没有 MV")
            return
        }
        await loadDetail(mvID: mvID)
        await loadUrl()
    }

    private func loadDetail(mvID: Int) async {
        detailState = .loading
        do {
            let response = try await environment.musicClient.mvDetail(id: mvID)
            detailState = .loaded(response.data)
        } catch {
            detailState = .failed(error.localizedDescription)
        }
    }

    private func loadUrl() async {
        guard let mvID = song.mv, mvID > 0 else { return }
        urlState = .loading
        do {
            let response = try await environment.musicClient.mvUrl(id: mvID, resolution: selectedResolution)
            urlState = .loaded(response.data)
        } catch {
            urlState = .failed(error.localizedDescription)
        }
    }

    private func formatDuration(_ milliseconds: Int) -> String {
        let seconds = milliseconds / 1000
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

private struct MusicMvCoverView: View {
    let urlString: String

    var body: some View {
        Group {
            if let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.pink.opacity(0.12))
            .overlay {
                Image(systemName: "play.rectangle")
                    .foregroundStyle(.pink)
            }
    }
}
