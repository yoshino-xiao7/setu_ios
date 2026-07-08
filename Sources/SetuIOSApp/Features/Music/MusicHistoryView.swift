import SetuIOSCore
import SwiftUI

struct MusicHistoryView: View {
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    @State private var state: LoadState<[MusicHistoryRecord]> = .idle
    @State private var count: Int?
    @State private var message: String?
    @State private var page = 1
    @State private var pageSize = 20
    @State private var selectedSong: MusicSong?
    @State private var showingClearConfirmation = false

    private let pageSizes = [10, 20, 50]

    var body: some View {
        List {
            if let message {
                Section {
                    SetuCard {
                        SetuPill(text: message, systemImage: "waveform", tone: .info)
                    }
                    .setuListRow()
                }
            }

            nowPlayingSection

            switch state {
            case .idle, .loading:
                MusicHistoryStateSection(title: "播放历史", stateTitle: "正在加载播放历史", systemImage: "clock.arrow.circlepath", isLoading: true)
            case .failed(let message):
                MusicHistoryStateSection(title: "播放历史", stateTitle: "历史加载失败", message: message, systemImage: "exclamationmark.triangle")
            case .loaded(let records):
                if records.isEmpty {
                    MusicHistoryStateSection(title: "播放历史", stateTitle: "暂无播放历史", systemImage: "clock.arrow.circlepath")
                } else {
                    Section {
                        SetuCard {
                            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                                SetuSectionHeader(title: "播放历史", subtitle: count.map { "共 \($0) 条" })
                                VStack(spacing: 0) {
                                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
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

                                        if index < records.count - 1 {
                                            Divider().overlay(SetuColor.separator)
                                        }
                                    }
                                }
                            }
                        }
                        .setuListRow()
                    }
                    if let count, count > pageSize {
                        pagerSection(total: count)
                    }
                }
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("播放历史")
        .sheet(item: $selectedSong) { song in
            AddSongToPlaylistSheet(environment: environment, song: song)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu("每页 \(pageSize)") {
                    ForEach(pageSizes, id: \.self) { size in
                        Button("\(size) 条") {
                            pageSize = size
                            page = 1
                            Task { await load() }
                        }
                    }
                }

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
        .task { await load() }
        .refreshable { await load() }
        .safeAreaInset(edge: .bottom) {
            MusicMiniPlayerBar(environment: environment, player: player)
                .padding(.horizontal)
                .padding(.top, 6)
        }
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
                                if let message = player.message {
                                    SetuPill(text: message, systemImage: "waveform", tone: .info)
                                }
                            }
                            Spacer()
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
                    }
                }
                .setuListRow()
            }
        }
    }

    private func pagerSection(total: Int) -> some View {
        Section {
            SetuCard {
                HStack(spacing: SetuSpacing.md) {
                    Button {
                        Task {
                            page = max(1, page - 1)
                            await load()
                        }
                    } label: {
                        Label("上一页", systemImage: "chevron.left")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(page <= 1 ? SetuColor.textTertiary : SetuColor.brandInk)
                    .frame(minHeight: 44)
                    .disabled(page <= 1)

                    Spacer()
                    Text("第 \(page) / \(max(1, Int(ceil(Double(total) / Double(pageSize))))) 页")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                    Spacer()

                    Button {
                        Task {
                            page += 1
                            await load()
                        }
                    } label: {
                        Label("下一页", systemImage: "chevron.right")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(page * pageSize >= total ? SetuColor.textTertiary : SetuColor.brandInk)
                    .frame(minHeight: 44)
                    .disabled(page * pageSize >= total)
                }
            }
            .setuListRow()
        }
    }

    private func load() async {
        state = .loading
        message = nil
        do {
            async let records = environment.musicClient.history(limit: pageSize, offset: (page - 1) * pageSize)
            async let total = environment.musicClient.historyCount()
            state = .loaded(try await records)
            count = try await total
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func play(_ record: MusicHistoryRecord, queueTracks: [MusicPlaybackTrack] = []) async {
        message = "正在准备播放"
        let track = MusicPlaybackTrack(record: record)
        guard let resolution = await player.resolveTrackURL?(track) else {
            message = "播放器尚未准备好"
            return
        }
        switch resolution {
        case .success(let url, let notice):
            player.play(url: url, track: track, queueName: "播放历史", queueTracks: queueTracks, notice: notice)
            try? await environment.musicClient.addHistory(song: record.song)
            message = notice ?? "已开始播放"
        case .unavailable(let reason):
            message = reason
        }
    }

    private func clear() async {
        do {
            try await environment.musicClient.clearHistory()
            page = 1
            count = 0
            await load()
            message = "播放历史已清空"
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct MusicHistoryStateSection: View {
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
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct MusicHistoryRow: View {
    let record: MusicHistoryRecord
    let onPlay: () -> Void
    let onAddToPlaylist: () -> Void

    var body: some View {
        HStack(spacing: SetuSpacing.md) {
            MusicArtworkView(urlString: record.coverUrl)
            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                Text(record.songName)
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(2)
                Text(record.artistName)
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                HStack(spacing: 10) {
                    if let albumName = record.albumName, !albumName.isEmpty {
                        Label(albumName, systemImage: "opticaldisc")
                    }
                    Label(record.playTime, systemImage: "clock")
                }
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textTertiary)
                .lineLimit(1)
            }
            Spacer()
            VStack(spacing: SetuSpacing.xs) {
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
        .padding(.vertical, SetuSpacing.sm)
        .contentShape(Rectangle())
    }
}
