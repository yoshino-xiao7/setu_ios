import SetuIOSCore
import SwiftUI

struct MusicPlaylistsView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<[UserMusicPlaylist]> = .idle

    var body: some View {
        List {
            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                ContentUnavailableView("歌单加载失败", systemImage: "music.note.list", description: Text(message))
            case .loaded(let playlists):
                if playlists.isEmpty {
                    ContentUnavailableView("暂无歌单", systemImage: "music.note.list", description: Text("在网页端或后续 iOS 歌单编辑中创建歌单后会显示在这里。"))
                } else {
                    Section("共 \(playlists.count) 个歌单") {
                        ForEach(playlists) { playlist in
                            MusicPlaylistRow(playlist: playlist)
                        }
                    }
                }
            }
        }
        .navigationTitle("我的歌单")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.musicClient.playlists())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct MusicPlaylistRow: View {
    let playlist: UserMusicPlaylist

    var body: some View {
        HStack(spacing: 12) {
            MusicArtworkView(urlString: playlist.coverUrl)
            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.name)
                    .font(.headline)
                if let description = playlist.description, !description.isEmpty {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 10) {
                    Label("\(playlist.songCount ?? 0) 首", systemImage: "music.note")
                    Label("\(playlist.playCount ?? 0)", systemImage: "play.circle")
                    Text(modeTitle(playlist.playMode))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func modeTitle(_ mode: String?) -> String {
        switch mode {
        case "random":
            return "随机"
        case "loop":
            return "循环"
        case "single":
            return "单曲"
        default:
            return "顺序"
        }
    }
}
