import SetuIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct MusicHomeView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    @State private var hotState: LoadState<[MusicHotSearchItem]> = .idle
    @State private var recommendedPlaylistState: LoadState<[MusicRecommendedPlaylist]> = .idle
    @State private var newSongsState: LoadState<[MusicSong]> = .idle
    @State private var dailySongsState: LoadState<[MusicSong]> = .idle
    @State private var recentHistoryState: LoadState<[MusicHistoryRecord]> = .idle
    @State private var myPlaylistState: LoadState<[UserMusicPlaylist]> = .idle
    @State private var selectedSong: MusicSong?
    @State private var mvSong: MusicSong?
    @State private var selectedRecommendedPlaylist: MusicRecommendedPlaylist?
    @State private var playbackMessage: String?

    var body: some View {
        List {
            Section {
                searchEntry
                .setuListRow()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            nowPlayingSection
            recentHistoryContent
            myPlaylistContent
            hotSearchContent
            recommendationsContent
        }
        .listStyle(.plain)
        .setuBackground()
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
        .safeAreaInset(edge: .bottom) {
            MusicMiniPlayerBar(environment: environment, player: player)
                .padding(.horizontal)
                .padding(.top, 6)
        }
    }

    private var searchEntry: some View {
        Button {
            router.navigate(to: .musicSearch(nil))
        } label: {
            HStack(spacing: SetuSpacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SetuColor.brandPink)
                    .frame(width: 44, height: 44)
                    .background(SetuColor.brandSoft.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                    Text("搜索音乐")
                        .font(SetuTypography.headline)
                        .foregroundStyle(SetuColor.textPrimary)
                    Text("歌曲、歌手、专辑")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SetuColor.textTertiary)
            }
            .padding(SetuSpacing.md)
            .frame(minHeight: 72)
            .background(SetuColor.surface, in: RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("搜索音乐")
    }

    @ViewBuilder
    private var nowPlayingSection: some View {
        if let track = player.currentTrack {
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "正在播放")
                        HStack(spacing: SetuSpacing.md) {
                            MusicArtworkView(urlString: track.coverURLString)
                            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                                Text(track.title)
                                    .font(SetuTypography.headline)
                                    .foregroundStyle(SetuColor.textPrimary)
                                    .lineLimit(2)
                                Text(track.artist)
                                    .font(SetuTypography.caption)
                                    .foregroundStyle(SetuColor.textSecondary)
                                if let message = playbackMessage ?? player.message {
                                    SetuPill(text: message, systemImage: "waveform", tone: .info)
                                }
                            }
                            Spacer()
                            MusicIconButton(
                                systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                                accessibilityLabel: player.isPlaying ? "暂停播放" : "继续播放",
                                tint: SetuColor.brandPink
                            ) {
                                player.toggle()
                            }
                            MusicIconButton(
                                systemImage: "stop.fill",
                                accessibilityLabel: "停止播放",
                                tint: SetuColor.danger
                            ) {
                                player.stop()
                            }
                        }
                    }
                }
                .setuListRow()
            }
        } else if let playbackMessage {
            Section {
                SetuCard {
                    SetuPill(text: playbackMessage, systemImage: "music.note", tone: .info)
                }
                .setuListRow()
            }
        }
    }

    @ViewBuilder
    private var hotSearchContent: some View {
        switch hotState {
        case .idle, .loading:
            MusicStateSection(
                title: "热门搜索",
                stateTitle: "正在加载热门搜索",
                systemImage: "magnifyingglass",
                isLoading: true
            )
        case .failed(let message):
            MusicStateSection(
                title: "热门搜索",
                stateTitle: "热门搜索加载失败",
                message: message,
                systemImage: "exclamationmark.triangle"
            )
        case .loaded(let hots):
            if !hots.isEmpty {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "热门搜索", subtitle: "点一下直接搜索")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: SetuSpacing.sm)], alignment: .leading, spacing: SetuSpacing.sm) {
                                ForEach(Array(hots.prefix(12).enumerated()), id: \.element.id) { index, item in
                                    Button {
                                        router.navigate(to: .musicSearch(item.first))
                                    } label: {
                                        Label(item.first, systemImage: index < 3 ? "flame.fill" : "magnifyingglass")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(index < 3 ? SetuColor.brandInk : SetuColor.textPrimary)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .padding(.horizontal, SetuSpacing.sm)
                                            .background(SetuColor.surfaceMuted, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .setuListRow()
                }
            }
        }
    }

    @ViewBuilder
    private var recentHistoryContent: some View {
        switch recentHistoryState {
        case .idle, .loading:
            MusicStateSection(title: "最近播放", stateTitle: "正在加载最近播放", systemImage: "clock.arrow.circlepath", isLoading: true)
        case .failed(let message):
            MusicStateSection(title: "最近播放", stateTitle: "最近播放加载失败", message: message, systemImage: "exclamationmark.triangle")
        case .loaded(let records):
            let visibleRecords = Array(records.prefix(8))
            if visibleRecords.isEmpty {
                MusicStateSection(title: "最近播放", stateTitle: "暂无播放历史", message: "播放过的歌曲会出现在这里。", systemImage: "clock.arrow.circlepath")
            } else {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "最近播放", subtitle: "\(visibleRecords.count) 首")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: SetuSpacing.md) {
                                    ForEach(visibleRecords) { record in
                                        Button {
                                            Task {
                                                await play(
                                                    record.song,
                                                    queueName: "最近播放",
                                                    queueTracks: visibleRecords.map { MusicPlaybackTrack(record: $0) }
                                                )
                                            }
                                        } label: {
                                            MusicRecentHistoryCard(record: record)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            Button {
                                router.navigate(to: .musicHistory)
                            } label: {
                                Label("查看全部播放历史", systemImage: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(SetuColor.brandInk)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .setuListRow()
                }
            }
        }
    }

    @ViewBuilder
    private var myPlaylistContent: some View {
        switch myPlaylistState {
        case .idle, .loading:
            MusicStateSection(title: "我的歌单", stateTitle: "正在加载我的歌单", systemImage: "music.note.list", isLoading: true)
        case .failed(let message):
            MusicStateSection(title: "我的歌单", stateTitle: "我的歌单加载失败", message: message, systemImage: "exclamationmark.triangle")
        case .loaded(let playlists):
            let visiblePlaylists = Array(playlists.prefix(6))
            if visiblePlaylists.isEmpty {
                MusicStateSection(title: "我的歌单", stateTitle: "暂无歌单", message: "创建歌单后会显示在这里。", systemImage: "music.note.list")
            } else {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "我的歌单", subtitle: "\(playlists.count) 个")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: SetuSpacing.md)], spacing: SetuSpacing.md) {
                                ForEach(visiblePlaylists) { playlist in
                                    Button {
                                        router.navigate(to: .playlistDetail(playlist.id))
                                    } label: {
                                        MusicPlaylistGridTile(playlist: playlist)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Button {
                                router.navigate(to: .playlists)
                            } label: {
                                Label("管理全部歌单", systemImage: "music.note.list")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(SetuColor.brandInk)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .setuListRow()
                }
            }
        }
    }

    @ViewBuilder
    private var recommendationsContent: some View {
        musicSongSection(
            title: "推荐新歌",
            loadingTitle: "正在加载推荐新歌",
            emptyTitle: "暂无推荐新歌",
            systemImage: "music.note",
            queueName: "推荐新歌",
            state: newSongsState
        )

        musicSongSection(
            title: "每日推荐",
            loadingTitle: "正在加载每日推荐",
            emptyTitle: "暂无每日推荐",
            systemImage: "sparkles",
            queueName: "每日推荐",
            state: dailySongsState
        )

        recommendedPlaylistSection
    }

    @ViewBuilder
    private func musicSongSection(
        title: String,
        loadingTitle: String,
        emptyTitle: String,
        systemImage: String,
        queueName: String,
        state: LoadState<[MusicSong]>
    ) -> some View {
        switch state {
        case .idle, .loading:
            MusicStateSection(title: title, stateTitle: loadingTitle, systemImage: systemImage, isLoading: true)
        case .failed(let message):
            MusicStateSection(title: title, stateTitle: "\(title)加载失败", message: message, systemImage: "exclamationmark.triangle")
        case .loaded(let songs):
            let visibleSongs = Array(songs.prefix(5))
            if visibleSongs.isEmpty {
                MusicStateSection(title: title, stateTitle: emptyTitle, systemImage: systemImage)
            } else {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: title)
                            MusicSongList(songs: visibleSongs) { song in
                                Task {
                                    await play(
                                        song,
                                        queueName: queueName,
                                        queueTracks: visibleSongs.map { MusicPlaybackTrack(song: $0) }
                                    )
                                }
                            } onPlayMv: { song in
                                mvSong = song
                            } onAddToPlaylist: { song in
                                selectedSong = song
                            } onDownload: { song in
                                Task { await download(song) }
                            }
                        }
                    }
                    .setuListRow()
                }
            }
        }
    }

    @ViewBuilder
    private var recommendedPlaylistSection: some View {
        switch recommendedPlaylistState {
        case .idle, .loading:
            MusicStateSection(title: "推荐歌单", stateTitle: "正在加载推荐歌单", systemImage: "music.note.list", isLoading: true)
        case .failed(let message):
            MusicStateSection(title: "推荐歌单", stateTitle: "推荐歌单加载失败", message: message, systemImage: "exclamationmark.triangle")
        case .loaded(let playlists):
            let visiblePlaylists = Array(playlists.prefix(6))
            if visiblePlaylists.isEmpty {
                MusicStateSection(title: "推荐歌单", stateTitle: "暂无推荐歌单", systemImage: "music.note.list")
            } else {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "推荐歌单")
                            VStack(spacing: 0) {
                                ForEach(Array(visiblePlaylists.enumerated()), id: \.element.id) { index, playlist in
                                    Button {
                                        selectedRecommendedPlaylist = playlist
                                    } label: {
                                        RecommendedPlaylistRow(playlist: playlist)
                                    }
                                    .buttonStyle(.plain)

                                    if index < visiblePlaylists.count - 1 {
                                        Divider().overlay(SetuColor.separator)
                                    }
                                }
                            }
                        }
                    }
                    .setuListRow()
                }
            }
        }
    }

    private func loadLandingContent() async {
        async let hot: Void = loadHotSearch()
        async let recommended: Void = loadRecommendations()
        async let recent: Void = loadRecentHistory()
        async let playlists: Void = loadMyPlaylists()
        _ = await (hot, recommended, recent, playlists)
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

    private func loadRecentHistory() async {
        recentHistoryState = .loading
        do {
            recentHistoryState = .loaded(try await environment.musicClient.history(limit: 8, offset: 0))
        } catch {
            recentHistoryState = .failed(error.localizedDescription)
        }
    }

    private func loadMyPlaylists() async {
        myPlaylistState = .loading
        do {
            myPlaylistState = .loaded(try await environment.musicClient.playlists())
        } catch {
            myPlaylistState = .failed(error.localizedDescription)
        }
    }

    private func play(_ song: MusicSong, queueName: String? = nil, queueTracks: [MusicPlaybackTrack] = []) async {
        playbackMessage = "正在准备播放"
        let track = MusicPlaybackTrack(song: song)
        guard let resolution = await player.resolveTrackURL?(track) else {
            playbackMessage = "播放器尚未准备好"
            return
        }
        switch resolution {
        case .success(let url, let notice):
            player.play(url: url, track: track, queueName: queueName, queueTracks: queueTracks, notice: notice)
            try? await environment.musicClient.addHistory(song: song)
            playbackMessage = notice ?? "已开始播放"
        case .unavailable(let reason):
            playbackMessage = reason
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

private struct MusicStateSection: View {
    let title: String
    let stateTitle: String
    var message: String?
    var systemImage: String
    var isLoading = false

    var body: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: title)
                    SetuEmptyState(
                        title: stateTitle,
                        message: message,
                        systemImage: systemImage,
                        isLoading: isLoading
                    )
                }
            }
            .setuListRow()
        }
    }
}

private struct MusicSongList: View {
    let songs: [MusicSong]
    let onPlay: (MusicSong) -> Void
    var onPlayMv: ((MusicSong) -> Void)?
    var onAddToPlaylist: ((MusicSong) -> Void)?
    var onDownload: ((MusicSong) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                MusicSongRow(
                    song: song,
                    onPlay: { onPlay(song) },
                    onPlayMv: onPlayMv.map { handler in { handler(song) } },
                    onAddToPlaylist: onAddToPlaylist.map { handler in { handler(song) } },
                    onDownload: onDownload.map { handler in { handler(song) } }
                )

                if index < songs.count - 1 {
                    Divider().overlay(SetuColor.separator)
                }
            }
        }
    }
}

private struct MusicIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct MusicMetadataRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: SetuSpacing.md) {
            Text(title)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(SetuTypography.body)
                .foregroundStyle(SetuColor.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 32)
    }
}

private struct RecommendedPlaylistRow: View {
    let playlist: MusicRecommendedPlaylist

    var body: some View {
        HStack(spacing: SetuSpacing.md) {
            MusicArtworkView(urlString: playlist.picUrl)
            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                Text(playlist.name)
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(2)
                if let description = playlist.description, !description.isEmpty {
                    Text(description)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .lineLimit(2)
                }
                if let playCount = playlist.playCount {
                    Label(formatPlayCount(playCount), systemImage: "play.circle")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SetuColor.textTertiary)
        }
        .padding(.vertical, SetuSpacing.sm)
        .contentShape(Rectangle())
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
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "歌单")
                            RecommendedPlaylistRow(playlist: playlist)
                        }
                    }
                    .setuListRow()
                }

                if let message {
                    Section {
                        SetuCard {
                            SetuPill(text: message, systemImage: "waveform", tone: .info)
                        }
                        .setuListRow()
                    }
                }

                switch state {
                case .idle, .loading:
                    MusicStateSection(title: "歌曲", stateTitle: "正在加载歌单歌曲", systemImage: "music.note.list", isLoading: true)
                case .failed(let message):
                    MusicStateSection(title: "歌曲", stateTitle: "歌单加载失败", message: message, systemImage: "exclamationmark.triangle")
                case .loaded(let songs):
                    if songs.isEmpty {
                        MusicStateSection(title: "歌曲", stateTitle: "暂无歌曲", systemImage: "music.note")
                    } else {
                        Section {
                            SetuCard {
                                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                                    SetuSectionHeader(title: "歌曲", subtitle: "\(songs.count) 首")
                                    MusicSongList(songs: songs) { song in
                                        Task {
                                            await play(
                                                song,
                                                queueTracks: songs.map { MusicPlaybackTrack(song: $0) }
                                            )
                                        }
                                    } onPlayMv: { song in
                                        mvSong = song
                                    } onAddToPlaylist: { song in
                                        selectedSong = song
                                    }
                                }
                            }
                            .setuListRow()
                        }
                    }
                }
            }
            .listStyle(.plain)
            .setuBackground()
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

    private func play(_ song: MusicSong, queueTracks: [MusicPlaybackTrack] = []) async {
        message = "正在准备播放"
        let track = MusicPlaybackTrack(song: song)
        guard let resolution = await player.resolveTrackURL?(track) else {
            message = "播放器尚未准备好"
            return
        }
        switch resolution {
        case .success(let url, let notice):
            player.play(url: url, track: track, queueName: playlist.name, queueTracks: queueTracks, notice: notice)
            try? await environment.musicClient.addHistory(song: song)
            message = notice ?? "已开始播放《\(playlist.name)》"
        case .unavailable(let reason):
            message = reason
        }
    }
}

struct MusicSearchView: View {
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    let initialQuery: String?

    @State private var query = ""
    @State private var state: LoadState<MusicSearchResultState> = .idle
    @State private var selectedSong: MusicSong?
    @State private var mvSong: MusicSong?
    @State private var message: String?
    @State private var page = 1
    @State private var searchKeyword = ""
    @State private var searchHistory: [String] = MusicSearchHistoryStore.load()
    @State private var didRunInitialSearch = false
    @State private var selectedSegment: MusicSearchSegment = .songs

    private let searchHistoryLimit = 10
    private let pageSize = 10

    var body: some View {
        List {
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "搜索")
                        TextField("歌曲、歌手或专辑", text: $query)
                            .modifier(MusicSearchInputModifier())
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                Task { await search() }
                            }

                        SetuPrimaryButton {
                            Task { await search() }
                        } label: {
                            Label("搜索音乐", systemImage: "magnifyingglass")
                        }
                        .opacity(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .setuListRow()
            }

            if let message {
                Section {
                    SetuCard {
                        SetuPill(text: message, systemImage: "waveform", tone: .info)
                    }
                    .setuListRow()
                }
            }

            historySection
            resultSection
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("搜索音乐")
        .sheet(item: $selectedSong) { song in
            AddSongToPlaylistSheet(environment: environment, song: song)
        }
        .sheet(item: $mvSong) { song in
            MusicMvSheet(environment: environment, song: song)
        }
        .task {
            guard !didRunInitialSearch else { return }
            didRunInitialSearch = true
            if let initialQuery, !initialQuery.isEmpty {
                query = initialQuery
                await search()
            }
        }
        .safeAreaInset(edge: .bottom) {
            MusicMiniPlayerBar(environment: environment, player: player)
                .padding(.horizontal)
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !searchHistory.isEmpty {
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "搜索历史")
                        VStack(spacing: 0) {
                            ForEach(Array(searchHistory.enumerated()), id: \.element) { index, keyword in
                                HStack(spacing: SetuSpacing.md) {
                                    Button {
                                        query = keyword
                                        Task { await search() }
                                    } label: {
                                        Label(keyword, systemImage: "clock.arrow.circlepath")
                                            .font(SetuTypography.body)
                                            .foregroundStyle(SetuColor.textPrimary)
                                            .lineLimit(1)
                                    }
                                    .buttonStyle(.plain)

                                    Spacer()

                                    MusicIconButton(
                                        systemImage: "xmark",
                                        accessibilityLabel: "删除搜索记录",
                                        tint: SetuColor.danger
                                    ) {
                                        removeSearchHistory(keyword)
                                    }

                                    if index < searchHistory.count - 1 {
                                        EmptyView()
                                    }
                                }
                                .frame(minHeight: 44)

                                if index < searchHistory.count - 1 {
                                    Divider().overlay(SetuColor.separator)
                                }
                            }
                        }

                        Button(role: .destructive) {
                            clearSearchHistory()
                        } label: {
                            Label("清空搜索历史", systemImage: "trash")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(SetuColor.danger)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .setuListRow()
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        switch state {
        case .idle:
            MusicStateSection(title: "搜索结果", stateTitle: "搜索音乐", message: "输入歌曲、歌手或专辑开始搜索。", systemImage: "magnifyingglass")
        case .loading:
            MusicStateSection(title: "搜索结果", stateTitle: "正在搜索", systemImage: "magnifyingglass", isLoading: true)
        case .failed(let message):
            MusicStateSection(title: "搜索结果", stateTitle: "搜索失败", message: message, systemImage: "exclamationmark.triangle")
        case .loaded(let result):
            if result.songs.isEmpty {
                MusicStateSection(title: "搜索结果", stateTitle: "没有找到音乐", systemImage: "magnifyingglass")
            } else {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "搜索结果", subtitle: "\(result.songs.count)/\(result.total)")
                            Picker("搜索分类", selection: $selectedSegment) {
                                ForEach(MusicSearchSegment.allCases) { segment in
                                    Text(segment.title).tag(segment)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityLabel("搜索分类")

                            switch selectedSegment {
                            case .songs:
                                MusicSongList(songs: result.songs) { song in
                                    Task {
                                        await play(
                                            song,
                                            queueTracks: result.songs.map { MusicPlaybackTrack(song: $0) }
                                        )
                                    }
                                } onPlayMv: { song in
                                    mvSong = song
                                } onAddToPlaylist: { song in
                                    selectedSong = song
                                } onDownload: { song in
                                    Task { await download(song) }
                                }
                            case .artists:
                                MusicSearchAggregateList(
                                    items: result.artistItems,
                                    emptyTitle: "当前结果暂无歌手信息",
                                    systemImage: "music.mic"
                                ) { item in
                                    query = item.title
                                    Task { await search() }
                                }
                            case .albums:
                                MusicSearchAggregateList(
                                    items: result.albumItems,
                                    emptyTitle: "当前结果暂无专辑信息",
                                    systemImage: "rectangle.stack"
                                ) { item in
                                    query = item.title
                                    Task { await search() }
                                }
                            }

                            if result.hasMore {
                                Button {
                                    Task { await loadMore() }
                                } label: {
                                    Label("加载更多 \(result.songs.count)/\(result.total)", systemImage: "plus.circle")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(SetuColor.brandInk)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.plain)
                            } else {
                                SetuPill(text: "已加载全部 \(result.total) 首歌曲", systemImage: "checkmark.circle", tone: .success)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    }
                    .setuListRow()
                }
            }
        }
    }

    private func search() async {
        let keywords = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keywords.isEmpty else { return }
        saveSearchHistory(keywords)
        searchKeyword = keywords
        page = 1
        state = .loading
        message = nil
        do {
            let result = try await environment.musicClient.search(keywords: keywords, limit: pageSize, offset: 0)
            state = .loaded(MusicSearchResultState(result: result))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func loadMore() async {
        guard case .loaded(let current) = state, current.hasMore else { return }
        page += 1
        do {
            let result = try await environment.musicClient.search(
                keywords: searchKeyword,
                limit: pageSize,
                offset: (page - 1) * pageSize
            )
            state = .loaded(current.appending(result))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func play(_ song: MusicSong, queueTracks: [MusicPlaybackTrack]) async {
        message = "正在准备播放"
        let track = MusicPlaybackTrack(song: song)
        guard let resolution = await player.resolveTrackURL?(track) else {
            message = "播放器尚未准备好"
            return
        }
        switch resolution {
        case .success(let url, let notice):
            player.play(url: url, track: track, queueName: "搜索结果", queueTracks: queueTracks, notice: notice)
            try? await environment.musicClient.addHistory(song: song)
            message = notice ?? "已开始播放"
        case .unavailable(let reason):
            message = reason
        }
    }

    private func download(_ song: MusicSong) async {
        message = "正在准备下载"
        do {
            let response = try await environment.musicClient.url(songID: song.id, level: "exhigh")
            guard let item = response.data?.first, let urlString = item.playableURLString else {
                message = response.data?.first?.unavailableMessage ?? response.playabilityReason ?? response.message ?? "这首歌暂时无法下载"
                return
            }
            let artists = song.artistNames.isEmpty ? "未知歌手" : song.artistNames.replacingOccurrences(of: " / ", with: ", ")
            let signed = try await environment.downloadClient.sign(url: urlString, filename: "\(song.name) - \(artists).mp3")
            guard let url = URL(string: signed.downloadUrl) else {
                message = "下载暂时不可用"
                return
            }
            #if os(iOS)
            await UIApplication.shared.open(url)
            #endif
            message = "已打开下载"
        } catch {
            message = error.localizedDescription
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
}

private struct MusicRecentHistoryCard: View {
    let record: MusicHistoryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            MusicArtworkView(urlString: record.coverUrl, width: 116, height: 116, cornerRadius: SetuRadius.md)
            Text(record.songName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SetuColor.textPrimary)
                .lineLimit(2)
            Text(record.artistName)
                .font(.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 132, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct MusicPlaylistGridTile: View {
    let playlist: UserMusicPlaylist

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            MusicArtworkView(urlString: playlist.coverUrl, width: 96, height: 96, cornerRadius: SetuRadius.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(playlist.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SetuColor.textPrimary)
                .lineLimit(2)
            HStack(spacing: SetuSpacing.xs) {
                Label("\(playlist.songCount ?? 0)", systemImage: "music.note")
                if let playCount = playlist.playCount {
                    Label("\(playCount)", systemImage: "play.circle")
                }
            }
            .font(.caption2)
            .foregroundStyle(SetuColor.textSecondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .padding(SetuSpacing.sm)
        .background(SetuColor.surfaceMuted, in: RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
        .contentShape(Rectangle())
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

    var artistItems: [MusicSearchAggregateItem] {
        aggregate(
            songs.flatMap { song in
                song.artistNames
                    .split(separator: "/")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    var albumItems: [MusicSearchAggregateItem] {
        aggregate(songs.map(\.albumName).filter { !$0.isEmpty && $0 != "未知专辑" })
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

    private func aggregate(_ values: [String]) -> [MusicSearchAggregateItem] {
        var counts: [String: Int] = [:]
        for value in values {
            counts[value, default: 0] += 1
        }
        return counts
            .map { MusicSearchAggregateItem(title: $0.key, count: $0.value) }
            .sorted {
                if $0.count == $1.count {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                return $0.count > $1.count
            }
    }
}

private enum MusicSearchSegment: String, CaseIterable, Identifiable {
    case songs
    case artists
    case albums

    var id: String { rawValue }

    var title: String {
        switch self {
        case .songs: "歌曲"
        case .artists: "歌手"
        case .albums: "专辑"
        }
    }
}

private struct MusicSearchAggregateItem: Identifiable, Sendable {
    let title: String
    let count: Int

    var id: String { title }
}

private struct MusicSearchAggregateList: View {
    let items: [MusicSearchAggregateItem]
    let emptyTitle: String
    let systemImage: String
    let onSelect: (MusicSearchAggregateItem) -> Void

    var body: some View {
        if items.isEmpty {
            SetuEmptyState(title: emptyTitle, systemImage: systemImage)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        onSelect(item)
                    } label: {
                        HStack(spacing: SetuSpacing.md) {
                            Image(systemName: systemImage)
                                .font(.title3)
                                .foregroundStyle(SetuColor.brandPink)
                                .frame(width: 44, height: 44)
                                .background(SetuColor.brandSoft.opacity(0.16), in: Circle())
                            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                                Text(item.title)
                                    .font(SetuTypography.headline)
                                    .foregroundStyle(SetuColor.textPrimary)
                                    .lineLimit(1)
                                Text("\(item.count) 首相关歌曲")
                                    .font(SetuTypography.caption)
                                    .foregroundStyle(SetuColor.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(SetuColor.textTertiary)
                        }
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < items.count - 1 {
                        Divider().overlay(SetuColor.separator)
                    }
                }
            }
        }
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
        HStack(spacing: SetuSpacing.md) {
            MusicArtworkView(urlString: song.coverURLString)
            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                Text(song.name)
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(2)
                Text(song.artistNames.isEmpty ? "未知歌手" : song.artistNames)
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                Text(song.albumName)
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(spacing: SetuSpacing.xs) {
                if let onPlay {
                    MusicIconButton(
                        systemImage: "play.fill",
                        accessibilityLabel: "播放 \(song.name)",
                        tint: SetuColor.brandPink
                    ) {
                        onPlay()
                    }
                }
                if song.mv ?? 0 > 0 {
                    if let onPlayMv {
                        MusicIconButton(
                            systemImage: "play.rectangle.fill",
                            accessibilityLabel: "播放 MV",
                            tint: SetuColor.info
                        ) {
                            onPlayMv()
                        }
                    } else {
                        Image(systemName: "play.rectangle")
                            .foregroundStyle(SetuColor.brandPink)
                            .frame(width: 44, height: 44)
                    }
                }
                if let onAddToPlaylist {
                    MusicIconButton(
                        systemImage: "text.badge.plus",
                        accessibilityLabel: "加入歌单",
                        tint: SetuColor.brandInk
                    ) {
                        onAddToPlaylist()
                    }
                }
                if let onDownload {
                    MusicIconButton(
                        systemImage: "arrow.down",
                        accessibilityLabel: "下载 \(song.name)",
                        tint: SetuColor.success
                    ) {
                        onDownload()
                    }
                }
            }
        }
        .padding(.vertical, SetuSpacing.sm)
        .contentShape(Rectangle())
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
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "歌曲")
                            MusicSongRow(song: song)
                        }
                    }
                    .setuListRow()
                }

                if let message {
                    Section {
                        SetuCard {
                            SetuPill(text: message, systemImage: "checkmark.circle", tone: .success)
                        }
                        .setuListRow()
                    }
                }

                switch state {
                case .idle, .loading:
                    MusicStateSection(title: "选择歌单", stateTitle: "正在加载歌单", systemImage: "music.note.list", isLoading: true)
                case .failed(let message):
                    MusicStateSection(title: "选择歌单", stateTitle: "歌单加载失败", message: message, systemImage: "exclamationmark.triangle")
                case .loaded(let playlists):
                    if playlists.isEmpty {
                        MusicStateSection(title: "选择歌单", stateTitle: "暂无歌单", systemImage: "music.note.list")
                    } else {
                        Section {
                            SetuCard {
                                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                                    SetuSectionHeader(title: "选择歌单")
                                    VStack(spacing: 0) {
                                        ForEach(Array(playlists.enumerated()), id: \.element.id) { index, playlist in
                                            Button {
                                                Task { await add(to: playlist) }
                                            } label: {
                                                HStack(spacing: SetuSpacing.md) {
                                                    Image(systemName: "music.note.list")
                                                        .foregroundStyle(SetuColor.brandPink)
                                                        .frame(width: 36, height: 36)
                                                        .background(SetuColor.brandSoft.opacity(0.18), in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
                                                    Text(playlist.name)
                                                        .font(SetuTypography.body)
                                                        .foregroundStyle(SetuColor.textPrimary)
                                                        .lineLimit(2)
                                                    Spacer()
                                                    Image(systemName: "plus.circle.fill")
                                                        .foregroundStyle(SetuColor.brandInk)
                                                }
                                                .frame(minHeight: 44)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)

                                            if index < playlists.count - 1 {
                                                Divider().overlay(SetuColor.separator)
                                            }
                                        }
                                    }
                                }
                            }
                            .setuListRow()
                        }
                    }
                }
            }
            .listStyle(.plain)
            .setuBackground()
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
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "歌曲")
                            MusicSongRow(song: song)
                        }
                    }
                    .setuListRow()
                }

                detailSection
                urlSection
            }
            .listStyle(.plain)
            .setuBackground()
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
        switch detailState {
        case .idle, .loading:
            MusicStateSection(title: "MV 详情", stateTitle: "正在加载 MV 详情", systemImage: "play.rectangle", isLoading: true)
        case .failed(let message):
            MusicStateSection(title: "MV 详情", stateTitle: "MV 详情加载失败", message: message, systemImage: "exclamationmark.triangle")
        case .loaded(let detail):
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "MV 详情")
                        if let cover = detail.cover {
                            MusicMvCoverView(urlString: cover)
                        }
                        VStack(spacing: SetuSpacing.sm) {
                            MusicMetadataRow(title: "标题", value: detail.name)
                            MusicMetadataRow(title: "艺人", value: detail.artistName ?? detail.artists?.map(\.name).joined(separator: " / ") ?? song.artistNames)
                            if let publishTime = detail.publishTime {
                                MusicMetadataRow(title: "发布时间", value: publishTime)
                            }
                            if let playCount = detail.playCount {
                                MusicMetadataRow(title: "播放量", value: "\(playCount)")
                            }
                            if let duration = detail.duration {
                                MusicMetadataRow(title: "时长", value: formatDuration(duration))
                            }
                        }
                        if let description = detail.desc ?? detail.briefDesc, !description.isEmpty {
                            Text(description)
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                        }
                        if let brs = detail.brs, !brs.isEmpty {
                            Picker("清晰度", selection: $selectedResolution) {
                                Text("默认").tag(Optional<Int>.none)
                                ForEach(brs) { quality in
                                    Text("\(quality.br)p").tag(Optional(quality.br))
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: selectedResolution) {
                                Task { await loadUrl() }
                            }
                        }
                    }
                }
                .setuListRow()
            }
        }
    }

    @ViewBuilder
    private var urlSection: some View {
        switch urlState {
        case .idle, .loading:
            MusicStateSection(title: "播放 MV", stateTitle: "正在准备 MV", systemImage: "play.rectangle", isLoading: true)
        case .failed(let message):
            MusicStateSection(title: "播放 MV", stateTitle: "MV 暂时不可播放", message: message, systemImage: "exclamationmark.triangle")
        case .loaded(let data):
            if let data, let urlString = data.httpsURLString, let url = URL(string: urlString) {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "播放 MV")
                            if let resolution = data.r ?? data.br {
                                MusicMetadataRow(title: "清晰度", value: "\(resolution)p")
                            }
                            if let size = data.size {
                                MusicMetadataRow(title: "大小", value: "\(size)")
                            }
                            if let type = data.type {
                                MusicMetadataRow(title: "类型", value: type)
                            }
                            Link(destination: url) {
                                Label("打开 MV", systemImage: "play.rectangle")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(SetuColor.heroGradient, in: Capsule())
                            }
                        }
                    }
                    .setuListRow()
                }
            } else {
                MusicStateSection(title: "播放 MV", stateTitle: "暂未拿到播放地址", message: "可以尝试切换清晰度或稍后重试。", systemImage: "play.rectangle")
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
        MusicArtworkView(
            urlString: urlString,
            width: nil,
            height: 180,
            cornerRadius: 8,
            artworkSize: .lockScreen,
            systemImage: "play.rectangle"
        )
        .frame(maxWidth: .infinity)
    }
}
