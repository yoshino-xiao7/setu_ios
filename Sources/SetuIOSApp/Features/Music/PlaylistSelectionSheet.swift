import SetuIOSCore
import SwiftUI

/// Shared selection, SWR state and write path; callers supply only their summary and payload.
struct PlaylistSelectionSheet<Summary: View>: View {
    enum Presentation { case song, playback, bulk }

    @Environment(\.dismiss) private var dismiss
    @Environment(MusicStore.self) private var store
    var environment: AppEnvironment? = nil
    let presentation: Presentation
    let requests: [AddSongToPlaylistRequest]
    var excludingPlaylistID: Int? = nil
    let onAdded: (UserMusicPlaylist) -> Void
    var onNeteaseAdded: ((NeteaseUserPlaylist) -> Void)? = nil
    @ViewBuilder let summary: () -> Summary
    @State private var feedback: SetuFeedback?
    @State private var isAdding = false
    @State private var selectedTab: PlaylistTrackSource = .cloud
    @State private var showingLoginSheet = false

    private var title: String {
        switch presentation {
        case .song: "加入歌单"
        case .playback: "收藏到歌单"
        case .bulk: "加入其它歌单"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SetuCard { summary() }.setuListRow()
                }

                if environment != nil {
                    Section {
                        Picker("歌单类别", selection: $selectedTab) {
                            ForEach(PlaylistTrackSource.allCases) { source in
                                Text(source.rawValue).tag(source)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .setuListRow()
                }

                if let feedback {
                    Section { SetuFeedbackBanner(feedback: feedback).setuListRow() }
                }

                switch selectedTab {
                case .cloud:
                    cloudPlaylistsSection
                case .netease:
                    neteasePlaylistsSection
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .setuBackground()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(presentation == .song ? "关闭" : "取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showingLoginSheet) {
                if let environment {
                    NeteaseLoginSheet(environment: environment)
                }
            }
        }
        .task {
            await store.loadPlaylists()
            if let env = environment, env.neteaseMusicSession.isLoggedIn, env.neteaseMusicSession.playlists.isEmpty {
                await env.neteaseMusicSession.loadPlaylists()
            }
        }
    }

    // MARK: - Cloud Section

    @ViewBuilder
    private var cloudPlaylistsSection: some View {
        switch store.playlists.state {
        case .idle, .loading:
            MusicStateSection(title: "选择歌单", stateTitle: "正在加载歌单", systemImage: "music.note.list", isLoading: true)
        case .failed(let error):
            Section {
                SetuEmptyState(title: "歌单加载失败", message: error, systemImage: "exclamationmark.triangle",
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
            } else if presentation == .song {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "选择歌单")
                            VStack(spacing: 0) {
                                ForEach(Array(targets.enumerated()), id: \.element.id) { index, playlist in
                                    selectionButton(playlist)
                                    if index < targets.count - 1 { Divider().overlay(SetuColor.separator) }
                                }
                            }
                        }
                    }.setuListRow()
                }
            } else {
                Section(presentation == .bulk ? "选择目标歌单" : "选择歌单") {
                    ForEach(targets) { selectionButton($0) }
                }
            }
        }
    }

    // MARK: - NetEase Section

    @ViewBuilder
    private var neteasePlaylistsSection: some View {
        if let environment {
            if !environment.neteaseMusicSession.isLoggedIn {
                Section {
                    SetuCard {
                        SetuEmptyState(
                            title: "未绑定网易云账号",
                            message: "登录网易云音乐账号后，可直接将歌曲一键收藏至网易云歌单。",
                            systemImage: "music.note.house",
                            actionTitle: "立即登录",
                            action: { showingLoginSheet = true }
                        )
                    }
                }
                .setuListRow()
            } else if environment.neteaseMusicSession.isLoadingPlaylists {
                MusicStateSection(title: "网易云歌单", stateTitle: "正在同步歌单...", systemImage: "arrow.triangle.2.circlepath", isLoading: true)
            } else if environment.neteaseMusicSession.playlists.isEmpty {
                Section {
                    SetuCard {
                        SetuEmptyState(
                            title: "暂无网易云歌单",
                            message: "未在当前账号检测到歌单，点击刷新重新同步。",
                            systemImage: "music.note.list",
                            actionTitle: "刷新歌单",
                            action: { Task { await environment.neteaseMusicSession.loadPlaylists() } }
                        )
                    }
                }
                .setuListRow()
            } else {
                let playlists = environment.neteaseMusicSession.playlists
                if presentation == .song {
                    Section {
                        SetuCard {
                            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                                SetuSectionHeader(title: "选择网易云歌单")
                                VStack(spacing: 0) {
                                    ForEach(Array(playlists.enumerated()), id: \.element.id) { index, playlist in
                                        neteaseSelectionButton(playlist)
                                        if index < playlists.count - 1 { Divider().overlay(SetuColor.separator) }
                                    }
                                }
                            }
                        }.setuListRow()
                    }
                } else {
                    Section("选择网易云歌单") {
                        ForEach(playlists) { playlist in
                            neteaseSelectionButton(playlist)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Buttons & Add Actions

    private func selectionButton(_ playlist: UserMusicPlaylist) -> some View {
        Button {
            Task { await add(to: playlist) }
        } label: {
            HStack(spacing: SetuSpacing.md) {
                if presentation == .song {
                    Image(systemName: "music.note.list")
                        .foregroundStyle(SetuColor.brandPink)
                        .frame(width: 36, height: 36)
                        .background(SetuColor.brandSoft.opacity(0.18), in: RoundedRectangle(cornerRadius: SetuRadius.sm))
                    Text(playlist.name)
                        .font(SetuTypography.body)
                        .foregroundStyle(SetuColor.textPrimary)
                        .lineLimit(2)
                } else {
                    MusicArtworkView(urlString: playlist.coverUrl)
                    VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                        Text(playlist.name)
                            .font(SetuTypography.headline)
                            .foregroundStyle(SetuColor.textPrimary)
                            .lineLimit(1)
                        Text("\(playlist.songCount ?? 0) 首")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(presentation == .song ? SetuColor.brandInk : SetuColor.brandPink)
            }
            .frame(minHeight: presentation == .song ? 44 : 56)
            .contentShape(Rectangle())
        }
        .setuButtonFeedback()
        .disabled(isAdding || requests.isEmpty)
    }

    private func neteaseSelectionButton(_ playlist: NeteaseUserPlaylist) -> some View {
        Button {
            Task { await addToNetease(playlist: playlist) }
        } label: {
            HStack(spacing: SetuSpacing.md) {
                if presentation == .song {
                    MusicArtworkView(urlString: playlist.coverImgUrl)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: SetuRadius.sm))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playlist.name)
                            .font(SetuTypography.body)
                            .foregroundStyle(SetuColor.textPrimary)
                            .lineLimit(1)
                        Text("\(playlist.trackCount ?? 0) 首")
                            .font(.caption2)
                            .foregroundStyle(SetuColor.textSecondary)
                    }
                } else {
                    MusicArtworkView(urlString: playlist.coverImgUrl)
                    VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                        Text(playlist.name)
                            .font(SetuTypography.headline)
                            .foregroundStyle(SetuColor.textPrimary)
                            .lineLimit(1)
                        Text("\(playlist.trackCount ?? 0) 首")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(presentation == .song ? SetuColor.brandInk : SetuColor.brandPink)
            }
            .frame(minHeight: presentation == .song ? 44 : 56)
            .contentShape(Rectangle())
        }
        .setuButtonFeedback()
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

    private func addToNetease(playlist: NeteaseUserPlaylist) async {
        guard !isAdding, !requests.isEmpty, let environment, let cookie = environment.neteaseMusicSession.cookie else { return }
        isAdding = true
        if presentation != .song { feedback = .info("正在加入网易云歌单《\(playlist.name)》") }
        defer { isAdding = false }
        do {
            var addedCount = 0
            for request in requests {
                let trackID: Int?
                if let songId = request.songId, songId > 0 {
                    trackID = songId
                } else if let raw = request.trackId?.rawValue, raw.hasPrefix("netease:track:") {
                    trackID = Int(raw.dropFirst("netease:track:".count))
                } else {
                    trackID = nil
                }

                if let trackID {
                    let success = try await environment.neteaseMusicApiClient.addSongToPlaylist(pid: playlist.id, trackID: trackID, cookie: cookie)
                    if success { addedCount += 1 }
                }
            }
            if addedCount > 0 {
                await environment.neteaseMusicSession.loadPlaylists()
                onNeteaseAdded?(playlist)
                dismiss()
            } else {
                feedback = .error(UserFacingError(message: "该歌曲暂无法关联至网易云歌曲标识"))
            }
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }
}
