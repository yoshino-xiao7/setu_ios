import SetuIOSCore
import SwiftUI

struct MusicHistoryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    @State private var records: [MusicHistoryRecord] = []
    @State private var count: Int?
    @State private var feedback: SetuFeedback?
    @State private var nextOffset = 0
    @State private var isInitialLoading = true
    @State private var isLoadingMore = false
    @State private var loadError: String?
    @State private var loadGeneration = 0
    @State private var selectedSong: MusicSong?
    @State private var showingClearConfirmation = false

    private let pageSize = 20

    var body: some View {
        List {
            if let feedback {
                Section {
                    SetuFeedbackBanner(feedback: feedback)
                    .setuListRow()
                }
            }

            nowPlayingSection

            if isInitialLoading {
                MusicHistoryStateSection(title: "播放历史", stateTitle: "正在加载播放历史", systemImage: "clock.arrow.circlepath", isLoading: true)
            } else if records.isEmpty {
                if let loadError {
                    Section {
                        SetuCard {
                            VStack(spacing: SetuSpacing.md) {
                                SetuEmptyState(
                                    title: "历史加载失败",
                                    message: loadError,
                                    systemImage: "exclamationmark.triangle"
                                )
                                Button("重试") {
                                    Task { await loadFirstPage() }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .setuListRow()
                    }
                } else {
                    MusicHistoryStateSection(title: "播放历史", stateTitle: "暂无播放历史", systemImage: "clock.arrow.circlepath")
                }
            } else {
                Section {
                    ForEach(records) { record in
                        MusicHistoryRow(record: record) {
                            Task {
                                await play(
                                    record,
                                    queueTracks: records.map { MusicPlaybackTrack(record: $0) }
                                )
                            }
                        } onAddToPlaylist: {
                            selectedSong = record.song
                        }

                        .onAppear {
                            if record.id == records.last?.id {
                                Task { await loadMore() }
                            }
                        }
                    }

                    SetuLoadMoreFooter(state: loadMoreFooterState) {
                        Task { await loadMore() }
                    }
                } header: {
                    Text(count.map { "播放历史 · 共 \($0) 条" } ?? "播放历史")
                }
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .setuFeedbackPresentation($feedback)
        .navigationTitle("播放历史")
        .sheet(item: $selectedSong) { song in
            AddSongToPlaylistSheet(environment: environment, song: song) { result in
                feedback = result
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("清空", role: .destructive) {
                    showingClearConfirmation = true
                }
                .disabled((count ?? 0) == 0)
            }
        }
        .confirmationDialog("清空播放历史？", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("清空历史", role: .destructive) {
                Task { await clear() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要清空所有播放历史吗？此操作不可恢复。")
        }
        .task { await loadFirstPage() }
        .refreshable { await loadFirstPage() }
    }

    @ViewBuilder
    private var nowPlayingSection: some View {
        if let track = player.currentTrack {
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "正在播放")
                        Group {
                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                                    HStack(spacing: SetuSpacing.md) {
                                        MusicArtworkView(urlString: track.coverURLString)
                                        nowPlayingSummary(track)
                                    }
                                    HStack(spacing: SetuSpacing.sm) {
                                        Spacer(minLength: 0)
                                        nowPlayingControls
                                    }
                                }
                            } else {
                                HStack(spacing: SetuSpacing.md) {
                                    MusicArtworkView(urlString: track.coverURLString)
                                    nowPlayingSummary(track)
                                    Spacer()
                                    nowPlayingControls
                                }
                            }
                        }
                        if let feedback = player.feedback {
                            SetuFeedbackBanner(feedback: feedback)
                        }
                    }
                }
                .setuListRow()
            }
        }
    }

    private func nowPlayingSummary(_ track: MusicPlaybackTrack) -> some View {
        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
            Text(track.title)
                .font(SetuTypography.headline)
                .foregroundStyle(SetuColor.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
            Text(track.artist)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var nowPlayingControls: some View {
        MusicHistoryIconButton(
            systemImage: player.isPlaying ? "pause.fill" : "play.fill",
            accessibilityLabel: player.isPlaying ? "暂停播放" : "继续播放",
            tint: SetuColor.brandPink
        ) {
            player.toggle()
        }
        MusicHistoryIconButton(
            systemImage: "stop.fill",
            accessibilityLabel: "停止播放",
            tint: SetuColor.danger
        ) {
            player.stop()
        }
    }

    private var loadMoreFooterState: SetuLoadMoreFooterState {
        if isLoadingMore { return .loading }
        if let loadError { return .failed(loadError) }
        if !hasMore { return .complete("已加载全部 \(count ?? records.count) 条记录") }
        return .idle
    }

    private var hasMore: Bool {
        guard let count else { return false }
        return records.count < count
    }

    private func loadFirstPage() async {
        loadGeneration += 1
        let requestedGeneration = loadGeneration
        isInitialLoading = records.isEmpty
        isLoadingMore = false
        loadError = nil
        feedback = nil

        do {
            async let records = environment.musicClient.history(limit: pageSize, offset: 0)
            async let total = environment.musicClient.historyCount()
            let (freshRecords, freshCount) = try await (records, total)
            guard requestedGeneration == loadGeneration else { return }
            self.records = freshRecords
            count = freshCount
            nextOffset = freshRecords.count
        } catch {
            guard requestedGeneration == loadGeneration else { return }
            loadError = "暂时无法加载播放历史，请检查网络后重试。"
        }
        guard requestedGeneration == loadGeneration else { return }
        isInitialLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, !isInitialLoading else { return }
        let requestedGeneration = loadGeneration
        let requestedOffset = nextOffset
        isLoadingMore = true
        loadError = nil
        defer {
            if requestedGeneration == loadGeneration {
                isLoadingMore = false
            }
        }

        do {
            let result = try await environment.musicClient.history(limit: pageSize, offset: requestedOffset)
            guard requestedGeneration == loadGeneration, requestedOffset == nextOffset else { return }
            let existingIDs = Set(records.map(\.id))
            records.append(contentsOf: result.filter { !existingIDs.contains($0.id) })
            nextOffset = requestedOffset + result.count
            if result.count < pageSize {
                count = records.count
            }
        } catch {
            guard requestedGeneration == loadGeneration else { return }
            loadError = "更多播放记录加载失败"
        }
    }

    private func play(_ record: MusicHistoryRecord, queueTracks: [MusicPlaybackTrack] = []) async {
        feedback = .info("正在准备播放")
        let track = MusicPlaybackTrack(record: record)
        guard let resolution = await player.resolveTrackURL?(track) else {
            feedback = .error("播放器尚未准备好")
            return
        }
        switch resolution {
        case .success(let url, let notice):
            player.play(url: url, track: track, queueName: "播放历史", queueTracks: queueTracks, notice: notice)
            try? await environment.musicClient.addHistory(song: record.song)
            feedback = notice.map(SetuFeedback.warning) ?? .success("已开始播放")
        case .unavailable(let reason):
            feedback = .error(reason)
        }
    }

    private func clear() async {
        do {
            try await environment.musicClient.clearHistory()
            records = []
            nextOffset = 0
            count = 0
            await loadFirstPage()
            feedback = .success("播放历史已清空")
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }
}

private typealias MusicHistoryStateSection = SetuStateSection

private struct MusicHistoryIconButton: View {
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
        .setuButtonFeedback(cornerRadius: 22)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct MusicHistoryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let record: MusicHistoryRecord
    let onPlay: () -> Void
    let onAddToPlaylist: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                    HStack(alignment: .top, spacing: SetuSpacing.md) {
                        MusicArtworkView(urlString: record.coverUrl, onTap: onPlay)
                        recordSummary
                    }
                    HStack(spacing: SetuSpacing.sm) {
                        Spacer(minLength: 0)
                        rowActions
                    }
                }
            } else {
                HStack(spacing: SetuSpacing.md) {
                    MusicArtworkView(urlString: record.coverUrl, onTap: onPlay)
                    recordSummary
                    Spacer()
                    VStack(spacing: SetuSpacing.xs) {
                        rowActions
                    }
                }
            }
        }
        .padding(.vertical, SetuSpacing.sm)
        .contentShape(Rectangle())
    }

    private var recordSummary: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
            Text(record.songName)
                .font(SetuTypography.headline)
                .foregroundStyle(SetuColor.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
            Text(record.artistName)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                if let albumName = record.albumName, !albumName.isEmpty {
                    Label(albumName, systemImage: "opticaldisc")
                }
                Label(record.playTime, systemImage: "clock")
            }
            .font(SetuTypography.caption)
            .foregroundStyle(SetuColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var rowActions: some View {
        MusicHistoryIconButton(
            systemImage: "play.fill",
            accessibilityLabel: "播放 \(record.songName)",
            tint: SetuColor.brandPink
        ) {
            onPlay()
        }
        MusicHistoryIconButton(
            systemImage: "text.badge.plus",
            accessibilityLabel: "加入歌单",
            tint: SetuColor.brandInk
        ) {
            onAddToPlaylist()
        }
    }
}
