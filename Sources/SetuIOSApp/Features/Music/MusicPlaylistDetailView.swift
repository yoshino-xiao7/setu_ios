import SetuIOSCore
import SwiftUI

struct MusicPlaylistDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    let playlistID: Int
    @State private var state: LoadState<UserMusicPlaylistDetail> = .idle
    @State private var message: String?
    @State private var selectedMode = "sequence"
    @State private var editingPlaylist: UserMusicPlaylistDetail?
    @State private var showingDeleteConfirmation = false
    @State private var songPendingRemoval: PlaylistSong?
    @State private var showingRemoveConfirmation = false

    var body: some View {
        List {
            if let message {
                Section {
                    SetuPill(text: message, systemImage: "info.circle", tone: .info)
                }
            }
            nowPlayingSection

            switch state {
            case .idle, .loading:
                Section {
                    SetuCard {
                        SetuEmptyState(title: "正在加载", systemImage: "music.note.list", isLoading: true)
                    }
                }
            case .failed(let message):
                Section {
                    SetuCard {
                        SetuEmptyState(title: "歌单加载失败", message: message, systemImage: "music.note.list")
                    }
                }
            case .loaded(let playlist):
                Section {
                    SetuCard {
                        HStack(spacing: SetuSpacing.md) {
                            MusicArtworkView(urlString: playlist.coverUrl)
                            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                                Text(playlist.name)
                                    .font(SetuTypography.title)
                                    .foregroundStyle(SetuColor.textPrimary)
                                if let description = playlist.description, !description.isEmpty {
                                    Text(description)
                                        .font(SetuTypography.caption)
                                        .foregroundStyle(SetuColor.textSecondary)
                                        .lineLimit(3)
                                }
                                HStack(spacing: SetuSpacing.md) {
                                    Label("\(playlist.songCount ?? playlist.songs?.count ?? 0) 首", systemImage: "music.note")
                                    Label("\(playlist.playCount ?? 0)", systemImage: "play.circle")
                                }
                                .font(.caption)
                                .foregroundStyle(SetuColor.textSecondary)

                                Button {
                                    Task { await playAll(playlist) }
                                } label: {
                                    Label("播放全部", systemImage: "play.circle.fill")
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                                .tint(SetuColor.brandPink)
                                .disabled(playlist.songs?.isEmpty != false)
                            }
                        }
                    }
                }

                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "播放模式")
                            Picker("播放模式", selection: $selectedMode) {
                                Text("顺序").tag("sequence")
                                Text("随机").tag("random")
                                Text("循环").tag("loop")
                                Text("单曲").tag("single")
                            }
                            .pickerStyle(.segmented)
                            .tint(SetuColor.brandPink)
                            .onChange(of: selectedMode) {
                                Task { await setMode(selectedMode) }
                            }
                        }
                    }
                }

                Section {
                    let songs = playlist.songs ?? []
                    if songs.isEmpty {
                        SetuCard {
                            SetuEmptyState(title: "暂无歌曲", systemImage: "music.note")
                        }
                    } else {
                        SetuCard {
                            SetuSectionHeader(title: "歌曲", subtitle: "共 \(songs.count) 首")
                        }
                        ForEach(songs) { song in
                            SetuCard {
                                PlaylistSongRow(song: song) {
                                    Task {
                                        await play(
                                            song,
                                            queueName: playlist.name,
                                            queueTracks: songs.map { MusicPlaybackTrack(song: $0) }
                                        )
                                    }
                                } onRemove: {
                                    songPendingRemoval = song
                                    showingRemoveConfirmation = true
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .setuBackground()
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
                    showingDeleteConfirmation = true
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
        .confirmationDialog("删除这个歌单？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("删除歌单", role: .destructive) {
                Task { await deletePlaylist() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后歌单中的歌曲关系会被移除，此操作不可恢复。")
        }
        .confirmationDialog("移除这首歌？", isPresented: $showingRemoveConfirmation, titleVisibility: .visible) {
            Button("移除歌曲", role: .destructive) {
                if let song = songPendingRemoval {
                    Task { await remove(song) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定从歌单中移除《\(songPendingRemoval?.songName ?? "这首歌")》吗？")
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
                                Text(track.artist)
                                    .font(SetuTypography.caption)
                                    .foregroundStyle(SetuColor.textSecondary)
                            }
                            Spacer()
                            Button {
                                player.toggle()
                            } label: {
                                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(SetuColor.brandPink)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.borderless)
                            Button(role: .destructive) {
                                player.stop()
                            } label: {
                                Image(systemName: "stop.circle")
                                    .font(.title2)
                                    .foregroundStyle(SetuColor.danger)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
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

    private func playAll(_ playlist: UserMusicPlaylistDetail) async {
        let songs = playlist.songs ?? []
        guard !songs.isEmpty else {
            message = "歌单为空"
            return
        }
        let firstSong = selectedMode == "random" ? songs.randomElement() ?? songs[0] : songs[0]
        try? await environment.musicClient.recordPlaylistPlay(id: playlistID)
        await play(
            firstSong,
            queueName: playlist.name,
            queueTracks: songs.map { MusicPlaybackTrack(song: $0) },
            playMode: MusicPlayMode(playlistMode: selectedMode)
        )
        if message == "已开始播放" {
            message = "开始播放《\(playlist.name)》"
        }
    }

    private func play(_ song: PlaylistSong, queueName: String? = nil, queueTracks: [MusicPlaybackTrack] = [], playMode: MusicPlayMode? = nil) async {
        message = "正在准备播放"
        do {
            let response = try await environment.musicClient.url(songID: song.songId)
            guard let item = response.data?.first, let urlString = item.playableURLString, let url = URL(string: urlString) else {
                message = response.data?.first?.unavailableMessage ?? response.playabilityReason ?? response.message ?? "这首歌暂时无法播放"
                return
            }
            player.play(url: url, track: MusicPlaybackTrack(song: song), queueName: queueName, queueTracks: queueTracks, playMode: playMode)
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
            List {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "歌单信息", subtitle: "编辑名称、描述和公开状态")
                            TextField("名称", text: $name)
                                .textFieldStyle(.roundedBorder)
                            TextField("描述", text: $description, axis: .vertical)
                                .lineLimit(3...5)
                                .textFieldStyle(.roundedBorder)
                            TextField("封面图片地址", text: $coverUrl)
                                .textInputAutocapitalization(.never)
                                .textFieldStyle(.roundedBorder)
                            Toggle(isOn: $isPublic) {
                                Label("公开歌单", systemImage: "eye")
                                    .foregroundStyle(SetuColor.textPrimary)
                            }
                            .tint(SetuColor.brandPink)
                        }
                    }
                }
                if let message {
                    Section {
                        SetuPill(text: message, systemImage: "exclamationmark.triangle", tone: .danger)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .setuBackground()
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
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(2)
                Text(song.artistName)
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                if let albumName = song.albumName, !albumName.isEmpty {
                    Text(albumName)
                        .font(.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                }
            }
            Spacer()
            Button(action: onPlay) {
                Image(systemName: "play.circle")
                    .font(.title3)
                    .foregroundStyle(SetuColor.brandPink)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle")
                    .font(.title3)
                    .foregroundStyle(SetuColor.danger)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, SetuSpacing.xs)
    }
}
