import SetuIOSCore
import SwiftUI

/// Shared selection, SWR state and write path; callers supply only their summary and payload.
struct PlaylistSelectionSheet<Summary: View>: View {
    enum Presentation { case song, playback, bulk }

    @Environment(\.dismiss) private var dismiss
    @Environment(MusicStore.self) private var store
    let presentation: Presentation
    let requests: [AddSongToPlaylistRequest]
    var excludingPlaylistID: Int? = nil
    let onAdded: (UserMusicPlaylist) -> Void
    @ViewBuilder let summary: () -> Summary
    @State private var feedback: SetuFeedback?
    @State private var isAdding = false

    private var title: String {
        switch presentation {
        case .song: "加入歌单"
        case .playback: "收藏到歌单"
        case .bulk: "加入其它歌单"
        }
    }

    var body: some View {
        NavigationStack {
            SetuBoard {
                Section {
                    SetuCard { summary() }
                }
                if let feedback {
                    Section { SetuFeedbackBanner(feedback: feedback) }
                }
                switch store.playlists.state {
                case .idle, .loading:
                    MusicStateSection(title: "选择歌单", stateTitle: "正在加载歌单", systemImage: "music.note.list", isLoading: true)
                case .failed(let error):
                    Section {
                        SetuEmptyState(
                            title: "歌单加载失败", message: error, systemImage: "exclamationmark.triangle",
                            actionTitle: "重试", action: { Task { await store.loadPlaylists(force: true) } })
                    }
                case .loaded(let playlists):
                    let targets = playlists.filter { $0.id != excludingPlaylistID }
                    if targets.isEmpty {
                        Section {
                            SetuEmptyState(
                                title: presentation == .bulk ? "暂无其它歌单" : "暂无歌单",
                                message: presentation == .bulk
                                    ? "关闭本页并回到“我的歌单”新建另一个歌单后，再进行批量加入。"
                                    : "先创建歌单再收藏当前歌曲。",
                                systemImage: "music.note.list"
                            )
                        }
                    } else {
                        SetuSectionHeader(title: presentation == .bulk ? "选择目标歌单" : "选择歌单")
                        SetuRecordBoard(items: targets) { selectionButton($0) }
                    }
                }
            }

            .setuBackground()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(presentation == .song ? "关闭" : "取消") { dismiss() }
                }
            }
        }
        .task { await store.loadPlaylists() }
    }

    private func selectionButton(_ playlist: UserMusicPlaylist) -> some View {
        SetuRecordCard(
            headline: playlist.name, supporting: "\(playlist.songCount ?? 0) 首歌曲",
            thumbnailURLString: playlist.coverUrl, onTap: { Task { await add(to: playlist) } }
        )
        .disabled(isAdding || requests.isEmpty)
    }

    private func add(to playlist: UserMusicPlaylist) async {
        guard !isAdding, !requests.isEmpty else { return }
        isAdding = true
        if presentation != .song { feedback = .info("正在加入 \(playlist.name)") }
        defer { isAdding = false }
        do {
            for request in requests { try await store.add(request, toPlaylist: playlist.id) }
            onAdded(playlist)
            dismiss()
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }
}
