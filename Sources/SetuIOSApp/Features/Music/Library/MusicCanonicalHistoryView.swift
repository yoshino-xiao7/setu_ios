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
                    Button {
                        Task {
                            let owner = store.sessionToken
                            do {
                                let track = try await environment.musicV2Client.track(item.id)
                                guard owner == store.sessionToken, track.id == item.id else { return }
                                await intent?.play(track, in: [track], context: .unknown(reason: .missingProvenance, label: "播放历史"))
                            } catch { if owner == store.sessionToken { feedback = UserFacingErrorMapper.map(error).message } }
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(item.entry.track?.title ?? "歌曲信息暂不可用")
                            Text(item.entry.lastPlayedAt).font(.caption).foregroundStyle(.secondary)
                        }.frame(minHeight: 44)
                    }
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
