import SetuIOSCore
import SwiftUI

struct MusicPlaylistsView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    @State private var state: LoadState<[UserMusicPlaylist]> = .idle
    @State private var showingCreate = false
    @State private var message: String?
    @State private var playlistPendingDeletion: UserMusicPlaylist?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        List {
            if let message {
                Section {
                    SetuPill(text: message, systemImage: "checkmark.seal", tone: .success)
                }
            }

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
            case .loaded(let playlists):
                if playlists.isEmpty {
                    Section {
                        SetuCard {
                            SetuEmptyState(title: "暂无歌单", message: "创建歌单后会显示在这里。", systemImage: "music.note.list")
                        }
                    }
                } else {
                    statsSection(playlists)
                    Section {
                        ForEach(playlists) { playlist in
                            Button {
                                router.navigate(to: .playlistDetail(playlist.id))
                            } label: {
                                SetuCard {
                                    MusicPlaylistRow(playlist: playlist)
                                }
                            }
                            .setuButtonFeedback()
                            .swipeActions {
                                Button(role: .destructive) {
                                    playlistPendingDeletion = playlist
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("删除", systemImage: "trash")
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
        .navigationTitle("我的歌单")
        .toolbar {
            Button {
                showingCreate = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreatePlaylistSheet(environment: environment) {
                Task { await load() }
            }
        }
        .confirmationDialog("删除这个歌单？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("删除歌单", role: .destructive) {
                if let playlist = playlistPendingDeletion {
                    Task { await delete(playlist) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定删除歌单《\(playlistPendingDeletion?.name ?? "这个歌单")》吗？")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func statsSection(_ playlists: [UserMusicPlaylist]) -> some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "概览", subtitle: "共 \(playlists.count) 个歌单")
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: SetuSpacing.sm),
                        GridItem(.flexible(), spacing: SetuSpacing.sm)
                    ], spacing: SetuSpacing.sm) {
                        SetuStatTile(title: "歌单数量", value: "\(playlists.count)", systemImage: "music.note.list", color: SetuColor.brandPink)
                        SetuStatTile(title: "歌曲总数", value: "\(playlists.reduce(0) { $0 + ($1.songCount ?? 0) })", systemImage: "music.note", color: SetuColor.info)
                        SetuStatTile(title: "播放总量", value: "\(playlists.reduce(0) { $0 + ($1.playCount ?? 0) })", systemImage: "play.circle", color: SetuColor.success)
                    }
                }
            }
        }
    }

    private func load() async {
        state = .loading
        message = nil
        do {
            state = .loaded(try await environment.musicClient.playlists())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func delete(_ playlist: UserMusicPlaylist) async {
        do {
            try await environment.musicClient.deletePlaylist(id: playlist.id)
            playlistPendingDeletion = nil
            await load()
            message = "已删除《\(playlist.name)》"
        } catch {
            message = error.localizedDescription
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
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                if let description = playlist.description, !description.isEmpty {
                    Text(description)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: 10) {
                    Label("\(playlist.songCount ?? 0) 首", systemImage: "music.note")
                    Label("\(playlist.playCount ?? 0)", systemImage: "play.circle")
                    Text(modeTitle(playlist.playMode))
                }
                .font(.caption)
                .foregroundStyle(SetuColor.textSecondary)
            }
        }
        .padding(.vertical, SetuSpacing.xs)
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

private struct CreatePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let onCreated: () -> Void
    @State private var name = ""
    @State private var description = ""
    @State private var isPublic = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "歌单信息", subtitle: "创建后可继续添加歌曲")
                            TextField("名称", text: $name)
                                .textFieldStyle(.roundedBorder)
                            TextField("描述", text: $description, axis: .vertical)
                                .lineLimit(3...5)
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
            .navigationTitle("新建歌单")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        Task { await create() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func create() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        do {
            _ = try await environment.musicClient.createPlaylist(
                name: trimmedName,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                isPublic: isPublic ? 1 : 0
            )
            onCreated()
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}
