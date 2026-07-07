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
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            nowPlayingSection

            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                ContentUnavailableView("历史加载失败", systemImage: "clock.arrow.circlepath", description: Text(message))
            case .loaded(let records):
                if records.isEmpty {
                    ContentUnavailableView("暂无播放历史", systemImage: "clock.arrow.circlepath")
                } else {
                    Section(count.map { "共 \($0) 条" } ?? "播放历史") {
                        ForEach(records) { record in
                            MusicHistoryRow(record: record) {
                                Task { await play(record) }
                            } onAddToPlaylist: {
                                selectedSong = record.song
                            }
                        }
                    }
                    if let count, count > pageSize {
                        pagerSection(total: count)
                    }
                }
            }
        }
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
                        if let message = player.message {
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
        }
    }

    private func pagerSection(total: Int) -> some View {
        Section {
            HStack {
                Button("上一页") {
                    Task {
                        page = max(1, page - 1)
                        await load()
                    }
                }
                .disabled(page <= 1)

                Spacer()
                Text("第 \(page) / \(max(1, Int(ceil(Double(total) / Double(pageSize))))) 页")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()

                Button("下一页") {
                    Task {
                        page += 1
                        await load()
                    }
                }
                .disabled(page * pageSize >= total)
            }
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

    private func play(_ record: MusicHistoryRecord) async {
        message = "正在获取播放地址"
        do {
            let response = try await environment.musicClient.url(songID: record.songId)
            guard let item = response.data?.first, let urlString = item.playableURLString, let url = URL(string: urlString) else {
                message = response.data?.first?.unavailableMessage ?? response.playabilityReason ?? response.message ?? "暂无可播放地址"
                return
            }
            player.play(url: url, track: MusicPlaybackTrack(record: record), queueName: "播放历史")
            try? await environment.musicClient.addHistory(song: record.song)
            message = "已开始播放"
        } catch {
            message = error.localizedDescription
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

private struct MusicHistoryRow: View {
    let record: MusicHistoryRecord
    let onPlay: () -> Void
    let onAddToPlaylist: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MusicArtworkView(urlString: record.coverUrl)
            VStack(alignment: .leading, spacing: 5) {
                Text(record.songName)
                    .font(.headline)
                    .lineLimit(2)
                Text(record.artistName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    if let albumName = record.albumName, !albumName.isEmpty {
                        Label(albumName, systemImage: "opticaldisc")
                    }
                    Label(record.playTime, systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 10) {
                Button(action: onPlay) {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)

                Button(action: onAddToPlaylist) {
                    Image(systemName: "text.badge.plus")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}
