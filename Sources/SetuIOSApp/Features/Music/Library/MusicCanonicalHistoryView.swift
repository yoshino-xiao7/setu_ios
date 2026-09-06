import SetuIOSCore
import SwiftUI

struct MusicHistoryItem: Identifiable, Sendable {
    let entry: MusicV2PlaybackHistoryEntry
    var id: MusicV2TrackID { entry.trackId }
    init(_ entry: MusicV2PlaybackHistoryEntry) { self.entry = entry }
}

struct MusicCanonicalHistoryView: View {
    @Environment(MusicStore.self) private var store
    @Environment(\.musicPlaybackIntent) private var intent
    let environment: AppEnvironment
    @State private var confirming = false
    @State private var feedback: String?
    var body: some View {
        List {
            if let feedback { Text(feedback) }
            MusicDetailState(resource: store.canonicalHistory, retry: { await load(force: true) }) { page in
                if page.items.isEmpty { ContentUnavailableView("暂无播放历史", systemImage: "clock") }
                ForEach(page.items) { item in
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                            if let track = item.entry.track {
                                MusicSongRow(track: track, onPlay: {
                                    Task {
                                        await intent?.play(track, in: page.items.compactMap { $0.entry.track },
                                            context: .unknown(reason: .missingProvenance, label: "播放历史"))
                                    }
                                })
                            } else {
                                HStack(spacing: SetuSpacing.md) {
                                    MusicArtworkView(urlString: nil)
                                    Text("歌曲信息暂不可用").foregroundStyle(.secondary)
                                }
                            }
                            Label(MusicHistoryDateLabel.text(item.entry.lastPlayedAt), systemImage: "clock")
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textTertiary)
                        }
                    }.setuListRow()
                }
                if let error = store.libraryMoreErrors["history"] { Text(error.message) }
                if page.nextOffset != nil { Button("加载更多") { Task { await load(more: true) } }.disabled(store.libraryMoreLoading.contains("history")) }
            }
        }.listStyle(.plain).setuBackground().navigationTitle("播放历史")
        .toolbar { Button("清空", role: .destructive) { confirming = true }.disabled(store.libraryWriting || (store.canonicalHistory.value?.total ?? 0) == 0) }
        .confirmationDialog("清空播放历史？", isPresented: $confirming) {
            Button("清空历史", role: .destructive) {
                Task { do { try await store.clearCanonicalHistory(client: environment.musicV2Client) }
                    catch { feedback = UserFacingErrorMapper.map(error).message } }
            }
        }
        .task(id: store.userID) { await load() }
        .refreshable { await load(force: true) }
    }
    private func load(force: Bool = false, more: Bool = false) async { await store.loadCanonicalHistory(client: environment.musicV2Client, force: force, more: more) }
}

enum MusicHistoryDateLabel {
    static func text(_ value: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = parser.date(from: value)
        parser.formatOptions = [.withInternetDateTime]
        guard let date = fractional ?? parser.date(from: value) else { return "时间未知" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = calendar.timeZone
        if calendar.isDate(date, inSameDayAs: now) { formatter.dateFormat = "今天 HH:mm" }
        else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { formatter.dateFormat = "昨天 HH:mm" }
        else if calendar.component(.year, from: date) == calendar.component(.year, from: now) { formatter.dateFormat = "M月d日 HH:mm" }
        else { formatter.dateFormat = "yyyy年M月d日 HH:mm" }
        return formatter.string(from: date)
    }
}
