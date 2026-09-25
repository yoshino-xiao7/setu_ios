import SetuIOSCore
import SwiftUI

enum PlaylistTrackSource: String, CaseIterable, Identifiable {
    case cloud = "云端自建"
    case netease = "网易云歌单"

    var id: String { rawValue }
}

struct MusicPlaylistsView: View {
    @Environment(RouterPath.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    @Bindable var player: MusicPlaybackController
    @Environment(MusicStore.self) private var store
    private var state: LoadState<[UserMusicPlaylist]> { store.playlists.state }

    @State private var selectedTab: PlaylistTrackSource = .cloud
    @State private var showingCreateCloud = false
    @State private var showingCreateNetease = false
    @State private var feedback: SetuFeedback?
    @State private var playlistPendingDeletion: UserMusicPlaylist?
    @State private var showingDeleteConfirmation = false
    @State private var showingLoginSheet = false

    var body: some View {
        List {
            // NetEase Account Integration Card
            Section {
                NeteaseAccountCard(environment: environment)
            }
            .listRowInsets(EdgeInsets(top: SetuSpacing.xs, leading: SetuSpacing.md, bottom: SetuSpacing.xs, trailing: SetuSpacing.md))
            .listRowBackground(Color.clear)

            // Segment Picker
            Section {
                Picker("歌单类别", selection: $selectedTab) {
                    ForEach(PlaylistTrackSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowInsets(EdgeInsets(top: SetuSpacing.xs, leading: SetuSpacing.md, bottom: SetuSpacing.sm, trailing: SetuSpacing.md))
            .listRowBackground(Color.clear)

            if let feedback {
                Section {
                    SetuFeedbackBanner(feedback: feedback)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
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
        .setuFeedbackPresentation($feedback)
        .navigationTitle("我的歌单")
        .toolbar {
            Button {
                if selectedTab == .cloud {
                    showingCreateCloud = true
                } else {
                    if environment.neteaseMusicSession.isLoggedIn {
                        showingCreateNetease = true
                    } else {
                        showingLoginSheet = true
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(selectedTab == .cloud ? "新建云端歌单" : "新建网易云歌单")
        }
        .sheet(isPresented: $showingCreateCloud) {
            CreatePlaylistSheet(environment: environment)
        }
        .sheet(isPresented: $showingCreateNetease) {
            CreateNeteasePlaylistSheet(environment: environment)
        }
        .sheet(isPresented: $showingLoginSheet) {
            NeteaseLoginSheet(environment: environment)
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
        .task {
            await load()
            if environment.neteaseMusicSession.isLoggedIn && environment.neteaseMusicSession.playlists.isEmpty {
                await environment.neteaseMusicSession.loadPlaylists()
            }
        }
        .refreshable {
            await load(force: true)
            if environment.neteaseMusicSession.isLoggedIn {
                await environment.neteaseMusicSession.refreshProfileAndPlaylists()
            }
        }
    }

    // MARK: - Cloud Playlists Section

    @ViewBuilder
    private var cloudPlaylistsSection: some View {
        switch state {
        case .idle, .loading:
            Section {
                SetuCard {
                    SetuEmptyState(title: "正在加载", systemImage: "music.note.list", isLoading: true)
                }
            }
            .listRowInsets(EdgeInsets(top: SetuSpacing.xs, leading: SetuSpacing.md, bottom: SetuSpacing.xs, trailing: SetuSpacing.md))
            .listRowBackground(Color.clear)
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
            .listRowInsets(EdgeInsets(top: SetuSpacing.xs, leading: SetuSpacing.md, bottom: SetuSpacing.xs, trailing: SetuSpacing.md))
            .listRowBackground(Color.clear)
        case .loaded(let playlists):
            if playlists.isEmpty {
                Section {
                    SetuCard {
                        SetuEmptyState(
                            title: "暂无云端自建歌单",
                            message: "创建第一个歌单，把喜欢的歌曲整理到一起。",
                            systemImage: "music.note.list",
                            actionTitle: "创建歌单",
                            action: { showingCreateCloud = true }
                        )
                    }
                }
                .listRowInsets(EdgeInsets(top: SetuSpacing.xs, leading: SetuSpacing.md, bottom: SetuSpacing.xs, trailing: SetuSpacing.md))
                .listRowBackground(Color.clear)
            } else {
                cloudStatsSection(playlists)
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
                        .accessibilityIdentifier("music.playlists.row.\(playlist.id)")
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
                .listRowInsets(EdgeInsets(top: SetuSpacing.xs, leading: SetuSpacing.md, bottom: SetuSpacing.xs, trailing: SetuSpacing.md))
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - NetEase Playlists Section

    @ViewBuilder
    private var neteasePlaylistsSection: some View {
        if !environment.neteaseMusicSession.isLoggedIn {
            Section {
                SetuCard {
                    SetuEmptyState(
                        title: "未绑定网易云账号",
                        message: "登录网易云音乐账号后，将自动同步您的自建歌单和收藏歌单。",
                        systemImage: "music.note.house",
                        actionTitle: "立即绑定",
                        action: { showingLoginSheet = true }
                    )
                }
            }
            .listRowInsets(EdgeInsets(top: SetuSpacing.xs, leading: SetuSpacing.md, bottom: SetuSpacing.xs, trailing: SetuSpacing.md))
            .listRowBackground(Color.clear)
        } else if environment.neteaseMusicSession.isLoadingPlaylists {
            Section {
                SetuCard {
                    SetuEmptyState(title: "正在同步网易云歌单...", systemImage: "arrow.triangle.2.circlepath", isLoading: true)
                }
            }
            .listRowInsets(EdgeInsets(top: SetuSpacing.xs, leading: SetuSpacing.md, bottom: SetuSpacing.xs, trailing: SetuSpacing.md))
            .listRowBackground(Color.clear)
        } else if environment.neteaseMusicSession.playlists.isEmpty {
            Section {
                SetuCard {
                    SetuEmptyState(
                        title: "暂无网易云歌单",
                        message: "未在当前账号检测到歌单，点击刷新尝试重新同步。",
                        systemImage: "music.note.list",
                        actionTitle: "刷新歌单",
                        action: { Task { await environment.neteaseMusicSession.loadPlaylists() } }
                    )
                }
            }
            .listRowInsets(EdgeInsets(top: SetuSpacing.xs, leading: SetuSpacing.md, bottom: SetuSpacing.xs, trailing: SetuSpacing.md))
            .listRowBackground(Color.clear)
        } else {
            let playlists = environment.neteaseMusicSession.playlists
            neteaseStatsSection(playlists)

            Section {
                ForEach(playlists) { playlist in
                    Button {
                        router.navigate(to: .playlistDetailV2("netease:playlist:\(playlist.id)"))
                    } label: {
                        SetuCard {
                            NeteasePlaylistRow(playlist: playlist)
                        }
                    }
                    .setuButtonFeedback()
                    .accessibilityIdentifier("music.netease.playlist.\(playlist.id)")
                }
            }
            .listRowInsets(EdgeInsets(top: SetuSpacing.xs, leading: SetuSpacing.md, bottom: SetuSpacing.xs, trailing: SetuSpacing.md))
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Stats Sections

    private func cloudStatsSection(_ playlists: [UserMusicPlaylist]) -> some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "云端歌单概览", subtitle: "共 \(playlists.count) 个歌单")
                    LazyVGrid(columns: statColumns, spacing: SetuSpacing.sm) {
                        SetuStatTile(title: "歌单数量", value: "\(playlists.count)", systemImage: "music.note.list", color: SetuColor.brandPink)
                        SetuStatTile(title: "歌曲总数", value: "\(playlists.reduce(0) { $0 + ($1.songCount ?? 0) })", systemImage: "music.note", color: SetuColor.info)
                        SetuStatTile(title: "播放总量", value: "\(playlists.reduce(0) { $0 + ($1.playCount ?? 0) })", systemImage: "play.circle", color: SetuColor.success)
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: SetuSpacing.xs, leading: SetuSpacing.md, bottom: SetuSpacing.xs, trailing: SetuSpacing.md))
        .listRowBackground(Color.clear)
    }

    private func neteaseStatsSection(_ playlists: [NeteaseUserPlaylist]) -> some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "网易云歌单概览", subtitle: "已同步 \(playlists.count) 个歌单")
                    LazyVGrid(columns: statColumns, spacing: SetuSpacing.sm) {
                        SetuStatTile(title: "歌单数量", value: "\(playlists.count)", systemImage: "music.note.house", color: SetuColor.brandPink)
                        SetuStatTile(title: "歌曲总数", value: "\(playlists.reduce(0) { $0 + ($1.trackCount ?? 0) })", systemImage: "music.note", color: SetuColor.info)
                        SetuStatTile(title: "播放总量", value: "\(playlists.reduce(0) { $0 + ($1.playCount ?? 0) })", systemImage: "play.circle", color: SetuColor.success)
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: SetuSpacing.xs, leading: SetuSpacing.md, bottom: SetuSpacing.xs, trailing: SetuSpacing.md))
        .listRowBackground(Color.clear)
    }

    private var statColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: SetuSpacing.sm), count: count)
    }

    private func load(force: Bool = false) async {
        await store.loadPlaylists(force: force)
    }

    private func delete(_ playlist: UserMusicPlaylist) async {
        do {
            try await store.deletePlaylist(id: playlist.id)
            playlistPendingDeletion = nil
            feedback = .success("已删除《\(playlist.name)》")
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }
}

// MARK: - Rows & Sheets

private struct NeteasePlaylistRow: View {
    let playlist: NeteaseUserPlaylist

    var body: some View {
        HStack(spacing: 12) {
            MusicArtworkView(urlString: playlist.coverImgUrl)
            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.name)
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Label("\(playlist.trackCount ?? 0) 首", systemImage: "music.note")
                    if let playCount = playlist.playCount, playCount > 0 {
                        Label("\(playCount)", systemImage: "play.circle")
                    }
                    if playlist.subscribed == true {
                        Text("收藏")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(SetuColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 4))
                    } else {
                        Text("自建")
                            .font(.caption2)
                            .foregroundStyle(SetuColor.brandPink)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(SetuColor.brandSoft.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .font(.caption)
                .foregroundStyle(SetuColor.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(SetuColor.textTertiary)
        }
        .padding(.vertical, SetuSpacing.xs)
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
    @Environment(MusicStore.self) private var store
    @State private var name = ""
    @State private var description = ""
    @State private var isPublic = false
    @State private var feedback: SetuFeedback?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "歌单信息", subtitle: "创建后可继续添加歌曲")
                                .fixedSize(horizontal: false, vertical: true)
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

                if let feedback {
                    Section {
                        SetuFeedbackBanner(feedback: feedback)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .setuBackground()
            .navigationTitle("新建云端歌单")
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
            try await store.createPlaylist(
                name: trimmedName,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                isPublic: isPublic ? 1 : 0
            )
            dismiss()
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }
}

private struct CreateNeteasePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    @State private var name = ""
    @State private var isSubmitting = false
    @State private var feedback: SetuFeedback?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "网易云歌单信息", subtitle: "创建后将直接同步至网易云音乐账号")
                                .fixedSize(horizontal: false, vertical: true)
                            TextField("歌单名称", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                if let feedback {
                    Section {
                        SetuFeedbackBanner(feedback: feedback)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .setuBackground()
            .navigationTitle("新建网易云歌单")
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
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
        }
    }

    private func create() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let cookie = environment.neteaseMusicSession.cookie else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            if let _ = try await environment.neteaseMusicApiClient.createPlaylist(name: trimmed, cookie: cookie) {
                await environment.neteaseMusicSession.loadPlaylists()
                dismiss()
            } else {
                feedback = .error(UserFacingError(message: "创建网易云歌单失败"))
            }
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }
}
