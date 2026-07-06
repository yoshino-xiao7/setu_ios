import SetuIOSCore
import SwiftUI

struct MusicHomeView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var query = ""
    @State private var hotState: LoadState<[MusicHotSearchItem]> = .idle
    @State private var searchState: LoadState<MusicSearchResult> = .idle
    @State private var selectedSong: MusicSong?

    var body: some View {
        List {
            Section {
                Button {
                    router.navigate(to: .playlists)
                } label: {
                    Label("我的歌单", systemImage: "music.note.list")
                }
                Button {
                    router.navigate(to: .musicHistory)
                } label: {
                    Label("播放历史", systemImage: "clock.arrow.circlepath")
                }
            }

            Section("搜索") {
                TextField("歌曲、歌手或专辑", text: $query)
                    .modifier(MusicSearchInputModifier())
                    .onSubmit {
                        Task { await search() }
                    }
                Button("搜索音乐") {
                    Task { await search() }
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            searchContent
            hotSearchContent
        }
        .navigationTitle("音乐")
        .sheet(item: $selectedSong) { song in
            AddSongToPlaylistSheet(environment: environment, song: song)
        }
        .task { await loadHotSearch() }
        .refreshable { await loadHotSearch() }
    }

    @ViewBuilder
    private var searchContent: some View {
        switch searchState {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView("正在搜索")
        case .failed(let message):
            Section {
                Text(message)
                    .foregroundStyle(.red)
            }
        case .loaded(let result):
            Section("搜索结果 \(result.result.songCount)") {
                if result.result.songs.isEmpty {
                    ContentUnavailableView("没有找到音乐", systemImage: "magnifyingglass")
                } else {
                    ForEach(result.result.songs) { song in
                        MusicSongRow(song: song) {
                            selectedSong = song
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var hotSearchContent: some View {
        switch hotState {
        case .idle, .loading:
            ProgressView("正在加载热门搜索")
        case .failed(let message):
            Section("热门搜索") {
                Text(message)
                    .foregroundStyle(.red)
            }
        case .loaded(let hots):
            if !hots.isEmpty {
                Section("热门搜索") {
                    ForEach(hots.prefix(10)) { item in
                        Button {
                            query = item.first
                            Task { await search() }
                        } label: {
                            HStack {
                                Text(item.first)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if let score = item.second {
                                    Text("\(score)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func loadHotSearch() async {
        hotState = .loading
        do {
            hotState = .loaded(try await environment.musicClient.hotSearch().result.hots)
        } catch {
            hotState = .failed(error.localizedDescription)
        }
    }

    private func search() async {
        let keywords = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keywords.isEmpty else { return }
        searchState = .loading
        do {
            searchState = .loaded(try await environment.musicClient.search(keywords: keywords))
        } catch {
            searchState = .failed(error.localizedDescription)
        }
    }
}

private struct MusicSearchInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.textInputAutocapitalization(.never)
        #else
        content
        #endif
    }
}

struct MusicSongRow: View {
    let song: MusicSong
    var onAddToPlaylist: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            MusicArtworkView(urlString: song.coverURLString)
            VStack(alignment: .leading, spacing: 5) {
                Text(song.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(song.artistNames.isEmpty ? "未知歌手" : song.artistNames)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(song.albumName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 10) {
                if song.mv ?? 0 > 0 {
                    Image(systemName: "play.rectangle")
                        .foregroundStyle(.pink)
                }
                if let onAddToPlaylist {
                    Button(action: onAddToPlaylist) {
                        Image(systemName: "text.badge.plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct MusicArtworkView: View {
    let urlString: String?

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.pink.opacity(0.12))
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(.pink)
            }
    }
}

private struct AddSongToPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    let song: MusicSong
    @State private var state: LoadState<[UserMusicPlaylist]> = .idle
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section("歌曲") {
                    MusicSongRow(song: song)
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                switch state {
                case .idle, .loading:
                    ProgressView("正在加载歌单")
                case .failed(let message):
                    ContentUnavailableView("歌单加载失败", systemImage: "music.note.list", description: Text(message))
                case .loaded(let playlists):
                    if playlists.isEmpty {
                        ContentUnavailableView("暂无歌单", systemImage: "music.note.list")
                    } else {
                        Section("选择歌单") {
                            ForEach(playlists) { playlist in
                                Button {
                                    Task { await add(to: playlist) }
                                } label: {
                                    Text(playlist.name)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("加入歌单")
            .toolbar {
                Button("关闭") {
                    dismiss()
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.musicClient.playlists())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func add(to playlist: UserMusicPlaylist) async {
        do {
            try await environment.musicClient.add(song: song, toPlaylist: playlist.id)
            message = "已加入 \(playlist.name)"
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}
