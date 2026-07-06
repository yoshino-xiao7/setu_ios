import SetuIOSCore
import SwiftUI

struct MusicPlaylistDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let playlistID: Int
    @State private var state: LoadState<UserMusicPlaylistDetail> = .idle
    @State private var message: String?
    @State private var selectedMode = "sequence"
    @State private var player = MusicPlaybackController()
    @State private var editingPlaylist: UserMusicPlaylistDetail?

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
                                Task { await play(song) }
                            } onRemove: {
                                Task { await remove(song) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("歌单详情")
        .toolbar {
            Menu {
                if case .loaded(let playlist) = state {
                    Button {
                        editingPlaylist = playlist
                    } label: {
                        Label("编辑歌单", systemImage: "square.and.pencil")
                    }
                }
                Button(role: .destructive) {
                    Task { await deletePlaylist() }
                } label: {
                    Label("删除歌单", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .sheet(item: $editingPlaylist) { playlist in
            EditMusicPlaylistSheet(environment: environment, playlist: playlist) {
                Task { await load() }
            }
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
                        Text(track.artist)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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

    private func play(_ song: PlaylistSong) async {
        message = "正在获取播放地址"
        do {
            let response = try await environment.musicClient.url(songID: song.songId)
            guard let item = response.data?.first, let urlString = item.playableURLString, let url = URL(string: urlString) else {
                message = response.data?.first?.unavailableMessage ?? response.playabilityReason ?? response.message ?? "暂无可播放地址"
                return
            }
            player.play(url: url, track: MusicPlaybackTrack(song: song))
            message = "已开始播放"
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

private struct EditMusicPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let playlist: UserMusicPlaylistDetail
    let onSaved: () -> Void
    @State private var name: String
    @State private var description: String
    @State private var coverUrl: String
    @State private var isPublic: Bool
    @State private var message: String?

    init(environment: AppEnvironment, playlist: UserMusicPlaylistDetail, onSaved: @escaping () -> Void) {
        self.environment = environment
        self.playlist = playlist
        self.onSaved = onSaved
        _name = State(initialValue: playlist.name)
        _description = State(initialValue: playlist.description ?? "")
        _coverUrl = State(initialValue: playlist.coverUrl ?? "")
        _isPublic = State(initialValue: playlist.isPublic == 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("歌单信息") {
                    TextField("名称", text: $name)
                    TextField("描述", text: $description, axis: .vertical)
                    TextField("封面 URL", text: $coverUrl)
                    Toggle("公开歌单", isOn: $isPublic)
                }
                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("编辑歌单")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await save() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        do {
            _ = try await environment.musicClient.updatePlaylist(
                id: playlist.id,
                name: trimmedName,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                coverUrl: coverUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                isPublic: isPublic ? 1 : 0
            )
            onSaved()
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct PlaylistSongRow: View {
    let song: PlaylistSong
    let onPlay: () -> Void
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
            Button(action: onPlay) {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
