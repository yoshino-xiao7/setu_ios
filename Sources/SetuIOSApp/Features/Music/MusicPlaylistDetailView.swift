import SetuIOSCore
import SwiftUI

struct MusicPlaylistDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let playlistID: Int
    @State private var state: LoadState<UserMusicPlaylistDetail> = .idle
    @State private var message: String?
    @State private var selectedMode = "sequence"

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
                ContentUnavailableView("歌单加载失败", systemImage: "music.note.list", description: Text(message))
            case .loaded(let playlist):
                Section {
                    HStack(spacing: 12) {
                        MusicArtworkView(urlString: playlist.coverUrl)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(playlist.name)
                                .font(.headline)
                            if let description = playlist.description, !description.isEmpty {
                                Text(description)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 10) {
                                Label("\(playlist.songCount ?? playlist.songs?.count ?? 0) 首", systemImage: "music.note")
                                Label("\(playlist.playCount ?? 0)", systemImage: "play.circle")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("播放模式") {
                    Picker("播放模式", selection: $selectedMode) {
                        Text("顺序").tag("sequence")
                        Text("随机").tag("random")
                        Text("循环").tag("loop")
                        Text("单曲").tag("single")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedMode) {
                        Task { await setMode(selectedMode) }
                    }
                }

                Section("歌曲") {
                    let songs = playlist.songs ?? []
                    if songs.isEmpty {
                        ContentUnavailableView("暂无歌曲", systemImage: "music.note")
                    } else {
                        ForEach(songs) { song in
                            PlaylistSongRow(song: song) {
                                Task { await remove(song) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("歌单详情")
        .toolbar {
            Button("删除", role: .destructive) {
                Task { await deletePlaylist() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        state = .loading
        message = nil
        do {
            let playlist = try await environment.musicClient.playlist(id: playlistID)
            selectedMode = playlist.playMode ?? "sequence"
            state = .loaded(playlist)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func setMode(_ mode: String) async {
        do {
            try await environment.musicClient.setPlayMode(playlistID: playlistID, playMode: mode)
            message = "播放模式已更新"
        } catch {
            message = error.localizedDescription
        }
    }

    private func remove(_ song: PlaylistSong) async {
        do {
            try await environment.musicClient.removeSong(playlistID: playlistID, songID: song.songId)
            message = "已移除 \(song.songName)"
            await load()
        } catch {
            message = error.localizedDescription
        }
    }

    private func deletePlaylist() async {
        do {
            try await environment.musicClient.deletePlaylist(id: playlistID)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct PlaylistSongRow: View {
    let song: PlaylistSong
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MusicArtworkView(urlString: song.coverUrl)
            VStack(alignment: .leading, spacing: 5) {
                Text(song.songName)
                    .font(.headline)
                    .lineLimit(2)
                Text(song.artistName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let albumName = song.albumName, !albumName.isEmpty {
                    Text(albumName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
