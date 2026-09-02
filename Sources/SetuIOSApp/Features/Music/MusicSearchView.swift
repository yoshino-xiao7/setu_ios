import SetuIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#endif


struct MusicSearchView: View {
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    let initialQuery: String?

    @State private var query = ""
    @State private var state: LoadState<MusicSearchResultState> = .idle
    @State private var selectedSong: MusicSong?
    @State private var mvSong: MusicSong?
    @State private var feedback: SetuFeedback?
    @State private var searchKeyword = ""
    @State private var isLoadingMore = false
    @State private var loadMoreError: UserFacingError?
    @State private var searchRevision = 0
    @State private var searchHistory: [String] = MusicSearchHistoryStore.load()
    @State private var didRunInitialSearch = false
    @State private var selectedSegment: MusicSearchSegment = .songs
    @State private var fileSharePayload: SystemFileSharePayload?

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

            if let feedback {
                Section {
                    SetuFeedbackBanner(feedback: feedback)
                    .setuListRow()
                }
            }

            historySection
            resultSection
        }
        .listStyle(.plain)
        .setuBackground()
        .setuFeedbackPresentation($feedback)
        .navigationTitle("搜索音乐")
        .sheet(item: $selectedSong) { song in
            AddSongToPlaylistSheet(environment: environment, song: song) { result in
                feedback = result
            }
        }
        .sheet(item: $mvSong) { song in
            MusicMvSheet(environment: environment, player: player, song: song)
        }
        .sheet(item: $fileSharePayload) { payload in
            SystemFileShareSheet(fileURL: payload.fileURL) { result in
                switch result {
                case .completed:
                    feedback = .success("已完成保存或分享")
                case .cancelled:
                    feedback = .info("已取消保存或分享")
                case .failed(let text):
                    feedback = .error("保存或分享失败：\(text)")
                }
            }
        }
        .task {
            guard !didRunInitialSearch else { return }
            didRunInitialSearch = true
            if let initialQuery, !initialQuery.isEmpty {
                query = initialQuery
                await search()
            }
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
                                    .setuButtonFeedback()

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
                        .setuButtonFeedback()
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
                                Color.clear
                                    .frame(height: 1)
                                    .onAppear {
                                        Task { await loadMore() }
                                    }
                            }
                            SetuLoadMoreFooter(state: searchLoadMoreState(for: result)) {
                                Task { await loadMore() }
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
        searchRevision += 1
        let revision = searchRevision
        isLoadingMore = false
        loadMoreError = nil
        state = .loading
        feedback = nil
        do {
            let result = try await environment.musicClient.search(keywords: keywords, limit: pageSize, offset: 0)
            guard revision == searchRevision else { return }
            state = .loaded(MusicSearchResultState(result: result))
        } catch {
            guard revision == searchRevision else { return }
            state = .failed(UserFacingErrorMapper.map(error))
        }
    }

    private func loadMore() async {
        guard case .loaded(let current) = state,
              current.hasMore,
              !isLoadingMore else { return }
        let revision = searchRevision
        let requestedOffset = current.songs.count
        isLoadingMore = true
        loadMoreError = nil
        defer {
            if revision == searchRevision {
                isLoadingMore = false
            }
        }
        do {
            let result = try await environment.musicClient.search(
                keywords: searchKeyword,
                limit: pageSize,
                offset: requestedOffset
            )
            guard revision == searchRevision,
                  case .loaded(let latest) = state,
                  latest.songs.count == requestedOffset else { return }
            state = .loaded(latest.appending(result))
        } catch {
            guard revision == searchRevision else { return }
            loadMoreError = UserFacingErrorMapper.map(error)
        }
    }

    private func searchLoadMoreState(for result: MusicSearchResultState) -> SetuLoadMoreFooterState {
        if isLoadingMore { return .loading }
        if let loadMoreError { return .failed(loadMoreError) }
        if !result.hasMore { return .complete("已加载全部 \(result.total) 首歌曲") }
        return .idle
    }

    private func play(_ song: MusicSong, queueTracks: [MusicPlaybackTrack]) async {
        feedback = .info("正在准备播放")
        let track = MusicPlaybackTrack(song: song)
        guard let resolution = await player.resolveTrackURL?(track) else {
            feedback = .error("播放器尚未准备好")
            return
        }
        switch resolution {
        case .success(let url, let notice):
            player.play(url: url, track: track, queueName: "搜索结果", queueTracks: queueTracks, notice: notice)
            try? await environment.musicClient.addHistory(song: song)
            feedback = notice.map(SetuFeedback.warning) ?? .success("已开始播放")
        case .unavailable(let reason):
            feedback = .error(reason)
        }
    }

    private func download(_ song: MusicSong) async {
        feedback = .info("正在准备下载")
        do {
            let response = try await environment.musicClient.url(songID: song.id, level: "exhigh")
            guard let item = response.data?.first, let urlString = item.playableURLString else {
                feedback = .error(response.unavailableMessage)
                return
            }
            let artists = song.artistNames.isEmpty ? "未知歌手" : song.artistNames.replacingOccurrences(of: " / ", with: ", ")
            let signed = try await environment.downloadClient.sign(url: urlString, filename: "\(song.name) - \(artists).mp3")
            guard let url = URL(string: signed.downloadUrl) else {
                feedback = .error("下载暂时不可用")
                return
            }
            let filename = "\(song.name) - \(artists).mp3"
            let fileURL = try await RemoteFileExportService.download(from: url, filename: filename)
            fileSharePayload = SystemFileSharePayload(fileURL: fileURL)
            feedback = .success("下载完成，请选择保存位置或分享方式")
        } catch {
            feedback = .error(RemoteFileExportService.userMessage(for: error))
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

struct MusicRecentHistoryCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let record: MusicHistoryRecord
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                MusicArtworkView(
                    urlString: record.coverUrl,
                    width: dynamicTypeSize.isAccessibilitySize ? 168 : 116,
                    height: dynamicTypeSize.isAccessibilitySize ? 168 : 116,
                    cornerRadius: SetuRadius.md,
                    allowsTapToRetry: false
                )
                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                    Text(record.songName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SetuColor.textPrimary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .truncationMode(.tail)
                    Text(record.artistName)
                        .font(.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: dynamicTypeSize.isAccessibilitySize ? 184 : 132, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .setuButtonFeedback()
        .accessibilityLabel("播放 \(record.songName)，歌手 \(record.artistName)")
        .accessibilityIdentifier("music.history.\(record.id)")
    }
}

struct MusicPlaylistCompactRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let playlist: UserMusicPlaylist

    var body: some View {
        HStack(spacing: SetuSpacing.sm) {
            MusicArtworkView(urlString: playlist.coverUrl, width: 64, height: 64, cornerRadius: SetuRadius.sm)

            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                Text(playlist.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .truncationMode(.tail)

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                            playlistStats
                        }
                    } else {
                        HStack(spacing: SetuSpacing.sm) {
                            playlistStats
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(SetuColor.textSecondary)
            }
            .layoutPriority(1)

            Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 0 : SetuSpacing.sm)

            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SetuColor.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(SetuSpacing.sm)
        .background(SetuColor.surfaceMuted, in: RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var playlistStats: some View {
        HStack(spacing: SetuSpacing.xs) {
            Image(systemName: "music.note").accessibilityHidden(true)
            Text("\(playlist.songCount ?? 0) 首")
                .fixedSize(horizontal: false, vertical: true)
        }
        if let playCount = playlist.playCount {
            HStack(spacing: SetuSpacing.xs) {
                Image(systemName: "play.circle").accessibilityHidden(true)
                Text("播放 \(playCount) 次")
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                    .setuButtonFeedback()

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
