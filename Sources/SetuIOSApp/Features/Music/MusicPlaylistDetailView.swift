import SetuIOSCore
import SwiftUI

struct MusicPlaylistDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    let playlistID: Int
    @Environment(MusicStore.self) private var store
    private var state: LoadState<UserMusicPlaylistDetail> { store.playlistDetails[playlistID]?.state ?? .idle }
    @State private var feedback: SetuFeedback?
    private var selectedMode: String { store.playlistDetails[playlistID]?.value?.playMode ?? "sequence" }
    @State private var editingPlaylist: UserMusicPlaylistDetail?
    @State private var showingDeleteConfirmation = false
    @State private var songPendingRemoval: PlaylistSong?
    @State private var showingRemoveConfirmation = false
    @State private var isSelectionMode = false
    @State private var selectedSongIDs: Set<Int> = []
    @State private var showingBulkRemoveConfirmation = false
    @State private var showingBulkAddSheet = false

    var body: some View {
        SetuBoard {
            if let feedback {
                Section {
                    SetuFeedbackBanner(feedback: feedback)
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
                        SetuEmptyState(
                            title: "歌单加载失败",
                            message: message,
                            systemImage: "music.note.list",
                            actionTitle: "重试",
                            action: { Task { await load() } }
                        )
                    }
                }
            case .loaded(let playlist):
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                            MusicArtworkView(
                                urlString: playlist.coverUrl, width: nil, height: 220,
                                cornerRadius: SetuRadius.xl, artworkSize: .custom(width: 640, height: 640))
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
                            adaptivePlaybackModePicker
                                .tint(SetuColor.brandPink)
                        }
                    }
                }

                Section {
                    let songs = playlist.songs ?? []
                    if songs.isEmpty {
                        SetuCard {
                            SetuEmptyState(
                                title: "暂无歌曲",
                                message: "可在歌曲搜索结果中选择“加入歌单”，将歌曲添加到这里。",
                                systemImage: "music.note"
                            )
                        }
                    } else {
                        SetuCard {
                            HStack(spacing: SetuSpacing.md) {
                                SetuSectionHeader(
                                    title: "歌曲",
                                    subtitle: isSelectionMode ? "已选 \(selectedSongIDs.count) 首" : "共 \(songs.count) 首"
                                )
                                Spacer()
                                Button(isSelectionMode ? "完成" : "多选") {
                                    withAnimation(reduceMotion ? nil : .default) {
                                        isSelectionMode.toggle()
                                        if !isSelectionMode {
                                            selectedSongIDs.removeAll()
                                        }
                                    }
                                }
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(SetuColor.brandInk)
                                .frame(minHeight: 44)
                            }
                        }
                        SetuRecordBoard(items: songs) { song in
                            PlaylistSongRow(
                                song: song,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedSongIDs.contains(song.songId)
                            ) {
                                toggleSelection(song)
                            } onPlay: {
                                Task {
                                    await play(
                                        song,
                                        context: .playlist(id: .local(.legacy(playlist.id)), label: playlist.name),
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

        .setuBackground()
        .setuFeedbackPresentation($feedback)
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
            .accessibilityLabel("更多歌单操作")
        }
        .sheet(item: $editingPlaylist) { playlist in
            EditMusicPlaylistSheet(environment: environment, playlist: playlist) {
                feedback = .success("歌单已更新")
            }
        }
        .sheet(isPresented: $showingBulkAddSheet) {
            BulkAddPlaylistSongsSheet(
                environment: environment,
                sourcePlaylistID: playlistID,
                songs: selectedSongsForBulkAction
            ) {
                finishSelectionMode(feedback: .success("已加入其它歌单"))
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
        .confirmationDialog("批量移除歌曲？", isPresented: $showingBulkRemoveConfirmation, titleVisibility: .visible) {
            Button("移除 \(selectedSongIDs.count) 首歌曲", role: .destructive) {
                Task { await bulkRemoveSelectedSongs() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这些歌曲会从当前歌单移除，稍后可从其它入口重新加入。")
        }
        .task { await load() }
        .refreshable { await load(force: true) }
        .setuActionDock(isPresented: isSelectionMode) { playlistBatchActionBar }
    }

    private var selectedSongsForBulkAction: [PlaylistSong] {
        guard case .loaded(let playlist) = state else { return [] }
        return (playlist.songs ?? []).filter { selectedSongIDs.contains($0.songId) }
    }

    private var playlistBatchActionBar: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            Text("已选 \(selectedSongIDs.count) 首").font(SetuTypography.label)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: SetuSpacing.md) { batchActions }
                VStack(alignment: .leading, spacing: SetuSpacing.sm) { batchActions }
            }
        }
    }

    @ViewBuilder
    private var batchActions: some View {
        Button {
            showingBulkAddSheet = true
        } label: {
            Label("加入歌单", systemImage: "text.badge.plus").frame(minHeight: 44)
        }
        .disabled(selectedSongIDs.isEmpty)
        Button(role: .destructive) {
            showingBulkRemoveConfirmation = true
        } label: {
            Label("移除", systemImage: "trash").frame(minHeight: 44)
        }
        .disabled(selectedSongIDs.isEmpty)
    }

    @ViewBuilder
    private var adaptivePlaybackModePicker: some View {
        SetuFilterBar(
            options: [
                .init(value: "sequence", title: "顺序"), .init(value: "random", title: "随机"),
                .init(value: "loop", title: "循环"), .init(value: "single", title: "单曲"),
            ],
            selection: Binding(
                get: { store.playlistDetails[playlistID]?.value?.playMode ?? "sequence" },
                set: { mode in Task { await setMode(mode) } }), accessibilityTitle: "播放模式")
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

    private func load(force: Bool = false) async {
        await store.loadDetail(playlistID, force: force)
    }

    private func setMode(_ mode: String) async {
        do {
            try await store.setPlayMode(playlistID: playlistID, playMode: mode)
            feedback = .success("播放模式已更新")
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }

    private func remove(_ song: PlaylistSong) async {
        do {
            try await store.removeSong(playlistID: playlistID, song: song)
            feedback = .success("已移除 \(song.songName)")
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }

    private func toggleSelection(_ song: PlaylistSong) {
        guard isSelectionMode else { return }
        if selectedSongIDs.contains(song.songId) {
            selectedSongIDs.remove(song.songId)
        } else {
            selectedSongIDs.insert(song.songId)
        }
    }

    private func bulkRemoveSelectedSongs() async {
        let songs = selectedSongsForBulkAction
        guard !songs.isEmpty else { return }
        do {
            for song in songs {
                try await store.removeSong(playlistID: playlistID, song: song)
                selectedSongIDs.remove(song.songId)
            }
            finishSelectionMode(feedback: .success("已移除 \(songs.count) 首歌曲"))
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }

    private func finishSelectionMode(feedback: SetuFeedback) {
        selectedSongIDs.removeAll()
        isSelectionMode = false
        self.feedback = feedback
    }

    private func playAll(_ playlist: UserMusicPlaylistDetail) async {
        let songs = playlist.songs ?? []
        guard !songs.isEmpty else {
            feedback = .warning("歌单为空")
            return
        }
        let firstSong = selectedMode == "random" ? songs.randomElement() ?? songs[0] : songs[0]
        let owner = store.sessionToken
        Task {
            guard owner == store.sessionToken else { return }
            try? await store.recordPlaylistPlay(id: playlistID)
        }
        await play(
            firstSong,
            context: .playlist(id: .local(.legacy(playlist.id)), label: playlist.name),
            queueTracks: songs.map { MusicPlaybackTrack(song: $0) },
            playMode: MusicPlayMode(playlistMode: selectedMode)
        )
        if feedback == .success("已开始播放") {
            feedback = .success("开始播放《\(playlist.name)》")
        }
    }

    private func play(_ song: PlaylistSong, context: PlaybackContext? = nil, queueTracks: [MusicPlaybackTrack] = [], playMode: MusicPlayMode? = nil) async {
        feedback = .info("正在准备播放")
        let track = MusicPlaybackTrack(song: song)
        _ = await player.play(track: track, in: queueTracks, context: context, playMode: playMode)
        feedback = player.feedback
    }

    private func deletePlaylist() async {
        do {
            try await store.deletePlaylist(id: playlistID)
            dismiss()
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }
}

private struct EditMusicPlaylistSheet: View {
    @Environment(MusicStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let playlist: UserMusicPlaylistDetail
    let onSaved: () -> Void
    @State private var name: String
    @State private var description: String
    @State private var coverUrl: String
    @State private var isPublic: Bool
    @State private var feedback: SetuFeedback?

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
            SetuBoard {
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
                                #if os(iOS)
                                    .textInputAutocapitalization(.never)
                                #endif
                                .textFieldStyle(.roundedBorder)
                            Toggle(isOn: $isPublic) {
                                Label("公开歌单", systemImage: "eye")
                                    .foregroundStyle(SetuColor.textPrimary)
                            }
                            .tint(SetuColor.brandPink)
                        }
                    }
                }
                if let feedback {
                    Section {
                        SetuFeedbackBanner(feedback: feedback)
                    }
                }
            }

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
            try await store.updatePlaylist(
                id: playlist.id,
                name: trimmedName,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                coverUrl: coverUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                isPublic: isPublic ? 1 : 0
            )
            onSaved()
            dismiss()
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }
}

private struct BulkAddPlaylistSongsSheet: View {
    @Bindable var environment: AppEnvironment
    let sourcePlaylistID: Int
    let songs: [PlaylistSong]
    let onDone: () -> Void

    var body: some View {
        PlaylistSelectionSheet(presentation: .bulk, requests: songs.map { AddSongToPlaylistRequest(song: $0) },
                               excludingPlaylistID: sourcePlaylistID) { _ in
            onDone()
        } summary: {
            SetuSectionHeader(title: "批量加入歌单", subtitle: "已选 \(songs.count) 首歌曲")
        }
    }
}

private struct PlaylistSongRow: View {
    let song: PlaylistSong
    let isSelectionMode: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onPlay: () -> Void
    let onRemove: () -> Void

    var body: some View {
        SetuRecordCard(
            headline: song.songName, supporting: song.artistName,
            status: isSelectionMode ? .init(isSelected ? "已选中" : "未选中", tone: isSelected ? .brand : .muted) : nil,
            thumbnailURLString: song.coverUrl,
            fields: [.init("专辑", song.albumName ?? "暂无专辑", isNumeric: false)],
            onTap: isSelectionMode ? onToggleSelection : onPlay
        ) {
            if isSelectionMode {
                Button(action: onToggleSelection) {
                    Label(isSelected ? "取消选择" : "选择歌曲", systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityLabel("选择 \(song.songName)")
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: SetuSpacing.md) { songActions }
                    VStack(alignment: .leading, spacing: SetuSpacing.sm) { songActions }
                }
            }
        }
    }
}

private extension PlaylistSongRow {
    @ViewBuilder var songActions: some View {
        Button(action: onPlay) { Label("播放", systemImage: "play.circle").frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel("播放 \(song.songName)")
        Button(role: .destructive, action: onRemove) { Label("移除", systemImage: "minus.circle").frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel("移除 \(song.songName)")
    }
}
