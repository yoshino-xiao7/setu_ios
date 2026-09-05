import SetuIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct MusicHomeView: View {
    @Environment(RouterPath.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    @Environment(MusicStore.self) private var store
    private var hotState: LoadState<[MusicHotSearchItem]> { store.hotSearch.state }
    private var recommendedPlaylistState: LoadState<[MusicRecommendedPlaylist]> { store.recommendedPlaylists.state }
    private var newSongsState: LoadState<[MusicSong]> { store.newSongs.state }
    private var dailySongsState: LoadState<[MusicSong]> { store.dailySongs.state }
    private var recentHistoryState: LoadState<[MusicHistoryRecord]> { store.recentHistory.state }
    private var myPlaylistState: LoadState<[UserMusicPlaylist]> { store.playlists.state }
    @State private var selectedSong: MusicSong?
    @State private var mvSong: MusicSong?
    @State private var selectedRecommendedPlaylist: MusicRecommendedPlaylist?
    @State private var fileSharePayload: SystemFileSharePayload?
    @State private var searchQuery = ""

    var body: some View {
        List {
            if dynamicTypeSize.isAccessibilitySize {
                Section {
                    SetuCard {
                        TextField("搜索音乐", text: $searchQuery)
                            .font(.body)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.search)
                            .frame(minHeight: 44)
                            .accessibilityLabel("搜索歌曲、歌手或专辑")
                    }
                    .setuListRow()
                }
            }
            if let feedback = player.feedback {
                Section {
                    SetuFeedbackBanner(feedback: feedback)
                }
                .setuListRow()
            }
            if environment.config.musicFeatureFlags.usesV2Home {
                MusicHomeFeedContent(resource: store.homeFeed, flags: environment.config.musicFeatureFlags,
                                     userID: store.userID, retry: { await loadLandingContent(force: true) })
                    .environment(\.musicPlaybackIntent, MusicPlaybackIntent(player: player, store: store))
            } else {
                recentHistoryContent
                myPlaylistContent
                dailySongsContent
                newSongsContent
                recommendedPlaylistSection
                hotSearchContent
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .setuRefreshAfterLogin(environment.authSession) { Task { await loadLandingContent() } }
        .setuRetry { Task { await loadLandingContent() } }
        .accessibilityIdentifier("music.home.page")
        .modifier(
            MusicHomeSearchModifier(
                query: $searchQuery,
                usesNavigationSearch: !dynamicTypeSize.isAccessibilitySize
            )
        )
        .onSubmit(of: [.text, .search]) {
            openSearch()
        }
        .navigationTitle("音乐")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                MusicQualityMenu(player: player)
            }
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                toolbarLogo
            }
            #else
            ToolbarItem(placement: .automatic) {
                toolbarLogo
            }
            #endif
        }
        .sheet(item: $selectedSong) { song in
            AddSongToPlaylistSheet(environment: environment, song: song) { result in
                player.showFeedback(result)
            }
        }
        .sheet(item: $mvSong) { song in
            MusicMvSheet(environment: environment, player: player, song: song)
        }
        .sheet(item: $selectedRecommendedPlaylist) { playlist in
            RecommendedPlaylistSheet(environment: environment, player: player, playlist: playlist)
        }
        .sheet(item: $fileSharePayload) { payload in
            SystemFileShareSheet(fileURL: payload.fileURL) { result in
                player.showFeedback(fileShareFeedback(result))
            }
        }
        .task(id: store.sessionToken) { await loadLandingContent() }
        .refreshable { await loadLandingContent(force: true) }
    }

    private var toolbarLogo: some View {
        SetuToolbarLogo(assetName: "MusicHomeLogo", accessibilityLabel: "扣扣音乐")
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
                systemImage: "exclamationmark.triangle",
                actionTitle: "重试",
                action: { Task { await loadLandingContent() } }
            )
        case .loaded(let hots):
            if !hots.isEmpty {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "热门搜索", subtitle: "点一下直接搜索")
                            LazyVGrid(columns: hotSearchColumns, alignment: .leading, spacing: SetuSpacing.sm) {
                                ForEach(Array(hots.prefix(12).enumerated()), id: \.element.id) { index, item in
                                    Button {
                                        router.navigate(to: .musicSearch(item.first))
                                    } label: {
                                        MusicHomeKeywordLabel(query: item.first, index: index)
                                    }
                                    .setuButtonFeedback(cornerRadius: 22)
                                    .accessibilityIdentifier("music.hot.\(index)")
                                }
                            }
                        }
                    }
                    .setuListRow()
                    .accessibilityIdentifier("music.home.section.hot")
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
            MusicStateSection(
                title: "最近播放",
                stateTitle: "最近播放加载失败",
                message: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: "重试",
                action: { Task { await loadLandingContent() } }
            )
        case .loaded(let records):
            let visibleRecords = Array(records.prefix(8))
            if visibleRecords.isEmpty {
                MusicStateSection(
                    title: "继续听",
                    stateTitle: "还没有播放记录",
                    message: "找到喜欢的歌后，之后可以从这里继续听。",
                    systemImage: "clock.arrow.circlepath",
                    actionTitle: "去找一首歌",
                    action: { router.navigate(to: .musicSearch(nil)) }
                )
            } else {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "继续听", subtitle: "最近播放")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: SetuSpacing.md) {
                                    ForEach(visibleRecords) { record in
                                        MusicRecentHistoryCard(record: record) {
                                            Task {
                                                await play(
                                                    record.song,
                                                    context: .unknown(reason: .missingProvenance, label: "最近播放"),
                                                    queueTracks: visibleRecords.map { MusicPlaybackTrack(record: $0) }
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                            Button {
                                router.navigate(to: .musicHistory)
                            } label: {
                                HStack { Text("查看全部播放历史").fixedSize(horizontal: false, vertical: true); Spacer(); Image(systemName: "chevron.right") }
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(SetuColor.brandInk)
                                    .lineLimit(nil)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .padding(.vertical, SetuSpacing.xs)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                            .setuButtonFeedback()
                        }
                    }
                    .setuListRow()
                    .accessibilityIdentifier("music.home.section.history")
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
            MusicStateSection(
                title: "我的歌单",
                stateTitle: "我的歌单加载失败",
                message: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: "重试",
                action: { Task { await loadLandingContent() } }
            )
        case .loaded(let playlists):
            let visiblePlaylists = Array(playlists.prefix(6))
            if visiblePlaylists.isEmpty {
                MusicStateSection(
                    title: "我的歌单",
                    stateTitle: "还没有歌单",
                    message: "把喜欢的歌曲整理到自己的歌单中。",
                    systemImage: "music.note.list",
                    actionTitle: "创建第一个歌单",
                    action: { router.navigate(to: .playlists) }
                )
            } else {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "我的歌单", subtitle: "\(playlists.count) 个")
                            VStack(spacing: SetuSpacing.sm) {
                                ForEach(visiblePlaylists) { playlist in
                                    Button {
                                        router.navigate(to: .playlistDetail(playlist.id))
                                    } label: {
                                        MusicPlaylistCompactRow(playlist: playlist)
                                    }
                                    .setuButtonFeedback()
                                    .accessibilityIdentifier("music.playlist.\(playlist.id)")
                                }
                            }
                            Button {
                                router.navigate(to: .playlists)
                            } label: {
                                HStack { Text("管理全部歌单").fixedSize(horizontal: false, vertical: true); Spacer(); Image(systemName: "chevron.right") }
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(SetuColor.brandInk)
                                    .lineLimit(nil)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .padding(.vertical, SetuSpacing.xs)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                            .setuButtonFeedback()
                        }
                    }
                    .setuListRow()
                }
            }
        }
    }

    @ViewBuilder
    private var dailySongsContent: some View {
        musicSongSection(
            title: "每日推荐",
            loadingTitle: "正在加载每日推荐",
            emptyTitle: "暂无每日推荐",
            systemImage: "sparkles",
            context: .discovery(source: .sharedAlgorithmic(label: "每日推荐"), selectionKey: "dailyTracks", label: "每日推荐"),
            state: dailySongsState,
            retry: { Task { await loadLandingContent() } }
        )
    }

    @ViewBuilder
    private var newSongsContent: some View {
        musicSongSection(
            title: "推荐新歌",
            loadingTitle: "正在加载推荐新歌",
            emptyTitle: "暂无推荐新歌",
            systemImage: "music.note",
            context: .discovery(source: .sharedAlgorithmic(label: "推荐新歌"), selectionKey: "newTracks", label: "推荐新歌"),
            state: newSongsState,
            retry: { Task { await loadLandingContent() } }
        )
    }

    @ViewBuilder
    private func musicSongSection(
        title: String,
        loadingTitle: String,
        emptyTitle: String,
        systemImage: String,
        context: PlaybackContext,
        state: LoadState<[MusicSong]>,
        retry: @escaping () -> Void
    ) -> some View {
        switch state {
        case .idle, .loading:
            MusicStateSection(title: title, stateTitle: loadingTitle, systemImage: systemImage, isLoading: true)
        case .failed(let message):
            MusicStateSection(
                title: title,
                stateTitle: "\(title)加载失败",
                message: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: "重试",
                action: retry
            )
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
                                        context: context,
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
            MusicStateSection(
                title: "推荐歌单",
                stateTitle: "推荐歌单加载失败",
                message: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: "重试",
                action: { Task { await loadLandingContent() } }
            )
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
                                        if environment.config.musicFeatureFlags.usesV2PlaylistDetail {
                                            router.navigate(to: .playlistDetailV2("netease:playlist:\(playlist.id)"))
                                        } else {
                                            selectedRecommendedPlaylist = playlist
                                        }
                                    } label: {
                                        RecommendedPlaylistRow(playlist: playlist)
                                    }
                                    .setuButtonFeedback()

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

    private var hotSearchColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: 96), spacing: SetuSpacing.sm)]
    }

    private func loadLandingContent(force: Bool = false) async {
        if environment.config.musicFeatureFlags.usesV2Home {
            await store.loadHomeV2(client: environment.musicV2Client, force: force)
        } else {
            await store.loadHome(force: force)
        }
    }

    private func play(_ song: MusicSong, context: PlaybackContext? = nil, queueTracks: [MusicPlaybackTrack] = []) async {
        player.showFeedback(.info("正在准备播放"))
        let track = MusicPlaybackTrack(song: song)
        _ = await player.play(track: track, in: queueTracks, context: context)
    }

    private func download(_ song: MusicSong) async {
        player.showFeedback(.info("正在准备下载"))
        do {
            let response = try await environment.musicClient.url(songID: song.id, level: "exhigh")
            guard let item = response.data?.first, let urlString = item.playableURLString else {
                player.showFeedback(.error(response.unavailableMessage))
                return
            }
            let signed = try await environment.downloadClient.sign(url: urlString, filename: downloadFilename(for: song))
            guard let url = URL(string: signed.downloadUrl) else {
                player.showFeedback(.error("下载地址无效"))
                return
            }
            let fileURL = try await RemoteFileExportService.download(from: url, filename: downloadFilename(for: song))
            fileSharePayload = SystemFileSharePayload(fileURL: fileURL)
            player.showFeedback(.success("下载完成，请选择保存位置或分享方式"))
        } catch {
            player.showFeedback(.error(RemoteFileExportService.userMessage(for: error)))
        }
    }

    private func downloadFilename(for song: MusicSong) -> String {
        let artists = song.artistNames.isEmpty ? "未知歌手" : song.artistNames.replacingOccurrences(of: " / ", with: ", ")
        return "\(song.name) - \(artists).mp3"
    }

    private func fileShareFeedback(_ result: SystemFileShareResult) -> SetuFeedback {
        switch result {
        case .completed: .success("已完成保存或分享")
        case .cancelled: .info("已取消保存或分享")
        case .failed(let message): .error("保存或分享失败：\(message)")
        }
    }

    private func openSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        router.navigate(to: .musicSearch(query.isEmpty ? nil : query))
        searchQuery = ""
    }
}

private struct MusicHomeSearchModifier: ViewModifier {
    @Binding var query: String
    let usesNavigationSearch: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if usesNavigationSearch {
            content.searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索歌曲、歌手或专辑"
            )
        } else {
            content
        }
        #else
        content.searchable(text: $query, prompt: "搜索歌曲、歌手或专辑")
        #endif
    }
}

typealias MusicStateSection = SetuStateSection

struct MusicSongList: View {
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

struct MusicIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: Circle())
        }
        .setuButtonFeedback(cornerRadius: 22)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct MusicMetadataRow: View {
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

struct RecommendedPlaylistRow: View {
    let title: String
    let artwork: String?
    let description: String?
    let playCount: Int?
    init(playlist: MusicRecommendedPlaylist) {
        title = playlist.name; artwork = playlist.picUrl
        description = playlist.description; playCount = playlist.playCount
    }
    init(title: String, artwork: String?, description: String?, playCount: Int?) {
        self.title = title; self.artwork = artwork; self.description = description; self.playCount = playCount
    }

    var body: some View {
        HStack(spacing: SetuSpacing.md) {
            MusicArtworkView(urlString: artwork)
            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                Text(title)
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(2)
                if let description, !description.isEmpty {
                    Text(description)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .lineLimit(2)
                }
                if let playCount {
                    HStack(spacing: SetuSpacing.xs) {
                        Image(systemName: "play.circle")
                            .accessibilityHidden(true)
                        Text(formatPlayCount(playCount))
                            .fixedSize(horizontal: false, vertical: true)
                    }
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

    @Environment(MusicStore.self) private var store
    private var state: LoadState<[MusicSong]> { store.recommendedTracks[playlist.id]?.state ?? .idle }
    @State private var selectedSong: MusicSong?
    @State private var mvSong: MusicSong?
    @State private var feedback: SetuFeedback?

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

                if let feedback {
                    Section {
                        SetuFeedbackBanner(feedback: feedback)
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
        .setuFeedbackPresentation($feedback)
            .navigationTitle(playlist.name)
            .toolbar {
                Button("关闭") {
                    dismiss()
                }
            }
            .sheet(item: $selectedSong) { song in
                AddSongToPlaylistSheet(environment: environment, song: song) { result in
                    feedback = result
                }
            }
            .sheet(item: $mvSong) { song in
                MusicMvSheet(environment: environment, player: player, song: song)
            }
            .task { await load() }
            .refreshable { await load(force: true) }
        }
    }

    private func load(force: Bool = false) async {
        await store.loadTracks(playlist.id, force: force)
    }

    private func play(_ song: MusicSong, queueTracks: [MusicPlaybackTrack] = []) async {
        feedback = .info("正在准备播放")
        let track = MusicPlaybackTrack(song: song)
        _ = await player.play(
            track: track,
            in: queueTracks,
            context: .playlist(id: .provider(.legacy(playlist.id)), label: playlist.name)
        )
    }
}

#if DEBUG
#Preview("音乐首页 · 390 · 浅色") {
    SetuFeaturePreviewHost(playerState: .listening) { environment, player in
        MusicHomeView(environment: environment, player: player)
    }
    .frame(width: 390, height: 844)
    .preferredColorScheme(.light)
}
#endif
