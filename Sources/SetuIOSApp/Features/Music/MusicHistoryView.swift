import SetuIOSCore
import SwiftUI

struct MusicHistoryView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<[MusicHistoryRecord]> = .idle
    @State private var count: Int?
    @State private var message: String?

    var body: some View {
        List {
            if let message {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

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
                            MusicHistoryRow(record: record)
                        }
                    }
                }
            }
        }
        .navigationTitle("播放历史")
        .toolbar {
            Button("清空", role: .destructive) {
                Task { await clear() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        state = .loading
        message = nil
        do {
            async let records = environment.musicClient.history()
            async let total = environment.musicClient.historyCount()
            state = .loaded(try await records)
            count = try await total
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func clear() async {
        do {
            try await environment.musicClient.clearHistory()
            message = "播放历史已清空"
            await load()
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct MusicHistoryRow: View {
    let record: MusicHistoryRecord

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
        }
        .padding(.vertical, 4)
    }
}
