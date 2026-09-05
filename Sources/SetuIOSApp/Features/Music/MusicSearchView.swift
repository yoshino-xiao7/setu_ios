import SetuIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#endif


struct MusicSearchView: View {
    @Environment(MusicStore.self) private var store
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    let initialQuery: String?

    @State private var routeID = UUID()
    @State private var selectedSong: MusicSong?
    @State private var mvSong: MusicSong?
    @State private var feedback: SetuFeedback?
    @State private var fileSharePayload: SystemFileSharePayload?


    // Presentation-only viewport state; all query/results/paging live in MusicStore.
    @State private var scrolledKeyword: String?
    @State private var visibleNearEndIDs: Set<Int> = []
    @State private var viewport = CGRect.zero
    private var session: MusicSearchSession { store.searchSession }

    private func artistCallback(_ song: MusicSong) -> (() -> Void)? {
        guard let id = (song.artists ?? song.ar)?.first?.id, id > 0,
              let route = MusicDetailRoutes.artist(.init(rawValue: "netease:artist:\(id)"), flags: environment.config.musicFeatureFlags) else { return nil }
        return { router.navigate(to: route) }
    }
    private func albumCallback(_ song: MusicSong) -> (() -> Void)? {
        guard let id = (song.album ?? song.al)?.id, id > 0,
              let route = MusicDetailRoutes.album(.init(rawValue: "netease:album:\(id)"), flags: environment.config.musicFeatureFlags) else { return nil }
        return { router.navigate(to: route) }
    }

    var body: some View {
        @Bindable var session = session
        List {
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "搜索")
                        TextField("歌曲、歌手或专辑", text: $session.query)
                            .modifier(MusicSearchInputModifier())
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                Task { await session.submit() }
                            }

                        SetuPrimaryButton {
                            Task { await session.submit() }
                        } label: {
                            Label("搜索音乐", systemImage: "magnifyingglass")
                        }
                        .opacity(session.normalizedQuery.isEmpty ? 0.55 : 1)
                        .disabled(session.normalizedQuery.isEmpty)
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
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { viewport = $0 }
        .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in
            scrolledKeyword = session.resultKeyword
            requestVisiblePage()
        })
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
        .task { await session.activate(initialQuery: initialQuery, routeID: routeID) }
    }

    private func requestVisiblePage() {
        guard scrolledKeyword == session.resultKeyword, session.selectedSegment == .songs,
              let id = session.pager.items.suffix(3).first(where: { visibleNearEndIDs.contains($0.id) })?.id else { return }
        let keyword = session.resultKeyword
        Task {
            guard session.resultKeyword == keyword else { return }
            await session.loadMore(near: id)
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !session.hasResults && !session.history.isEmpty {
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "搜索历史")
                        VStack(spacing: 0) {
                            ForEach(Array(session.history.enumerated()), id: \.element) { index, keyword in
                                HStack(spacing: SetuSpacing.md) {
                                    Button {
                                        session.query = keyword
                                        Task { await session.submit() }
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
                                        session.removeHistory(keyword)
                                    }

                                    if index < session.history.count - 1 {
                                        EmptyView()
                                    }
                                }
                                .frame(minHeight: 44)

                                if index < session.history.count - 1 {
                                    Divider().overlay(SetuColor.separator)
                                }
                            }
                        }

                        Button(role: .destructive) {
                            session.clearHistory()
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
        if session.hasResults {
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "搜索结果", subtitle: "\(session.pager.items.count)/\(session.pager.total)")
                        Picker("搜索分类", selection: Binding(get: { session.selectedSegment }, set: { session.selectedSegment = $0 })) {
                            ForEach(MusicSearchSegment.allCases) { segment in Text(segment.title).tag(segment) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("搜索分类")
                        if session.isSearching { ProgressView("正在搜索") }
                        if let error = session.pager.initialError {
                            Text(error.message).foregroundStyle(SetuColor.danger)
                            SetuErrorRecoveryButton(error: error) { Task { await session.submit() } }
                        }
                    }
                }
                .setuListRow()
            }
            // Each ForEach element is a real List row. There is no wrapping VStack/card row.
            Section {
                switch session.selectedSegment {
                case .songs:
                    ForEach(session.pager.items) { row in
                        MusicSongRow(model: row, onPlay: {
                            Task { await play(row.song, queueTracks: session.pager.items.map { MusicPlaybackTrack(song: $0.song) }) }
                        }, onPlayMv: { mvSong = row.song }, onAddToPlaylist: { selectedSong = row.song }, onDownload: {
                            Task { await download(row.song) }
                        }, onArtist: artistCallback(row.song), onAlbum: albumCallback(row.song))
                        .background {
                            if session.pager.items.suffix(3).contains(where: { $0.id == row.id }) {
                                Color.clear
                                    .onGeometryChange(for: Bool.self) { proxy in
                                        proxy.frame(in: .global).intersects(viewport)
                                    } action: { visible in
                                        if visible { visibleNearEndIDs.insert(row.id) }
                                        else { visibleNearEndIDs.remove(row.id) }
                                        requestVisiblePage()
                                    }
                                    .onDisappear { visibleNearEndIDs.remove(row.id) }
                            }
                        }
                        .accessibilityIdentifier("music.search.song.\(row.id)")
                        .listRowBackground(SetuColor.surface)
                    }
                case .artists:
                    aggregateRows(session.artistItems, systemImage: "music.mic", emptyTitle: "当前结果暂无歌手信息")
                case .albums:
                    aggregateRows(session.albumItems, systemImage: "rectangle.stack", emptyTitle: "当前结果暂无专辑信息")
                }
            }
            Section {
                if session.canLoadMore, session.pager.phase == .idle {
                    Button("加载更多歌曲") { Task { await session.loadMore() } }
                        .frame(minHeight: 44)
                        .setuListRow()
                }
                SetuLoadMoreFooter(state: loadMoreState) { Task { await session.loadMore() } }
                    .setuListRow()
            }
        } else if session.showsSkeleton {
            MusicStateSection(title: "搜索结果", stateTitle: "正在搜索", systemImage: "magnifyingglass", isLoading: true)
        } else if let error = session.pager.initialError {
            MusicStateSection(title: "搜索结果", stateTitle: "搜索失败", message: error, systemImage: "exclamationmark.triangle")
        } else if session.pager.hasLoadedFirstPage {
            MusicStateSection(title: "搜索结果", stateTitle: "没有找到音乐", systemImage: "magnifyingglass")
        } else {
            MusicStateSection(title: "搜索结果", stateTitle: "搜索音乐", message: "输入歌曲、歌手或专辑开始搜索。", systemImage: "magnifyingglass")
        }
    }

    @ViewBuilder
    private func aggregateRows(_ items: [MusicSearchAggregateItem], systemImage: String, emptyTitle: String) -> some View {
        if items.isEmpty { SetuEmptyState(title: emptyTitle, systemImage: systemImage).setuListRow() }
        ForEach(items) { item in
            Button {
                session.query = item.title
                Task { await session.submit() }
            } label: {
                HStack(spacing: SetuSpacing.md) {
                    Image(systemName: systemImage).foregroundStyle(SetuColor.brandPink).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                        Text(item.title).font(SetuTypography.headline).foregroundStyle(SetuColor.textPrimary)
                        Text("\(item.count) 首相关歌曲").font(SetuTypography.caption).foregroundStyle(SetuColor.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "magnifyingglass").foregroundStyle(SetuColor.textTertiary)
                }
                .frame(minHeight: 56)
            }
            .setuButtonFeedback()
            .listRowBackground(SetuColor.surface)
        }
    }

    private var loadMoreState: SetuLoadMoreFooterState {
        if session.isSearching || session.pager.phase == .loadingMore { return .loading }
        if let error = session.pager.loadMoreError { return .failed(error) }
        if !session.pager.hasMore { return .complete("已加载全部 \(session.pager.total) 首歌曲") }
        return .idle
    }

    private func play(_ song: MusicSong, queueTracks: [MusicPlaybackTrack]) async {
        feedback = .info("正在准备播放")
        let track = MusicPlaybackTrack(song: song)
        _ = await player.play(
            track: track,
            in: queueTracks,
            context: .search(query: session.resultKeyword, scope: .tracks, label: "搜索结果")
        )
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

private struct MusicSearchInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.textInputAutocapitalization(.never).submitLabel(.search)
        #else
        content
        #endif
    }
}
