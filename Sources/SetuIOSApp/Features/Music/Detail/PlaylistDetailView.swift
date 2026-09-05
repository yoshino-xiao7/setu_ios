import SetuIOSCore
import SwiftUI

struct PlaylistDetailView: View {
    @Environment(MusicStore.self) private var store
    @Environment(\.musicPlaybackIntent) private var intent
    let environment: AppEnvironment
    let playlistID: MusicV2PlaylistID
    @State private var feedback: SetuFeedback?
    @State private var editingName = false
    @State private var name = ""
    @State private var writing = false
    private var flags: MusicFeatureFlags { environment.config.musicFeatureFlags }

    var body: some View {
        List {
            if let feedback { Section { SetuFeedbackBanner(feedback: feedback) } }
            MusicDetailState(resource: store.playlistDetailV2(playlistID.rawValue), retry: { await load(force: true) }) { data in
                Section {
                    MusicDetailHeader(title: data.title, description: data.description, artwork: data.artwork)
                    if let local = data.ownedLocal(by: store.userID) {
                        Button("重命名") { name = local.title; editingName = true }.disabled(writing)
                        Menu("默认播放模式") {
                            ForEach(MusicPlayMode.allCases, id: \.self) { mode in
                                Button(mode.title) { Task { await updateMode(mode, local: local) } }
                            }
                        }.disabled(writing).frame(minHeight: 44)
                    } else if case .provider = data.playlist {
                        Button {} label: { Label("收藏功能尚未启用", systemImage: "star") }
                            .disabled(true).frame(minHeight: 44)
                    }
                }
                Section("歌曲") {
                    if let first = data.tracks.first {
                        Button {
                            Task {
                                let mode: MusicPlayMode?
                                if case .local(let local) = data.playlist { mode = MusicPlayMode(rawValue: local.defaultPlaybackMode.rawValue) }
                                else { mode = nil }
                                await intent?.play(first, in: data.tracks, context: data.context, mode: mode)
                            }
                        } label: { Label(data.nextOffset == nil ? "播放全部" : "播放已加载歌曲", systemImage: "play.fill").frame(minHeight: 44) }
                    }
                    if data.memberships.isEmpty { ContentUnavailableView("暂无歌曲", systemImage: "music.note") }
                    ForEach(data.memberships.indices, id: \.self) { index in
                        let membership = data.memberships[index]
                        if let track = membership.projectedTrack {
                            MusicDetailTrackRow(track: track, tracks: data.tracks, context: data.context, flags: flags)
                        } else {
                            Label("第 \(membership.position + 1) 首歌曲信息暂不可用", systemImage: "music.note")
                                .foregroundStyle(SetuColor.textSecondary).frame(minHeight: 44)
                        }
                        if let local = data.ownedLocal(by: store.userID), case .local(let member) = membership,
                           member.playlistId == local.id {
                            Button("移除此歌曲", role: .destructive) { Task { await remove(member, local: local) } }
                                .disabled(writing).frame(minHeight: 44)
                        }
                    }
                    if let error = store.detailMoreErrors[playlistID.rawValue] {
                        Text(error.message).foregroundStyle(SetuColor.textSecondary)
                        if error.action == .signIn { NavigationLink("重新登录", value: AppRoute.account) }
                    }
                    if data.nextOffset != nil {
                        if store.detailMoreLoading.contains(playlistID.rawValue) { ProgressView("正在加载更多") }
                        else { Button("加载更多") { Task { await store.loadMorePlaylistDetail(playlistID, client: environment.musicV2Client) } }.frame(minHeight: 44) }
                    }
                }
            }
        }.listStyle(.plain).setuBackground().navigationTitle("歌单详情")
            .task(id: store.sessionToken) { await load() }.refreshable { await load(force: true) }
            .alert("重命名歌单", isPresented: $editingName) {
                TextField("名称", text: $name)
                Button("取消", role: .cancel) {}
                Button("保存") {
                    guard let local = store.playlistDetailV2(playlistID.rawValue).value?.ownedLocal(by: store.userID) else { return }
                    Task { await rename(local) }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
    }

    private func load(force: Bool = false) async {
        guard flags.usesV2PlaylistDetail else { return }
        await store.loadPlaylistDetailV2(playlistID, client: environment.musicV2Client, force: force)
    }
    private func write(local: MusicV2LocalPlaylist, operation: () async throws -> Void) async {
        guard !writing, store.playlistDetailV2(playlistID.rawValue).value?.ownedLocal(by: store.userID)?.id == local.id else { return }
        let owner = store.sessionToken
        writing = true
        defer { writing = false }
        do {
            try await operation()
            guard owner == store.sessionToken else { return }
            await store.invalidateLegacyPlaylistReadsAfterDetailWrite()
            guard owner == store.sessionToken else { return }
            await load(force: true)
            if store.playlistDetailV2(playlistID.rawValue).error == nil { feedback = .success("已更新歌单") }
        } catch {
            guard owner == store.sessionToken else { return }
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }
    private func rename(_ local: MusicV2LocalPlaylist) async {
        await write(local: local) {
            let path = try MusicLocalPlaylistBridge.path(local.id)
            let _: String = try await environment.apiClient.put("/user/playlists/\(path)", body:
                CreateMusicPlaylistRequest(name: name, description: local.description, coverUrl: local.artwork?.url,
                                           isPublic: local.visibility == "public" ? 1 : 0))
        }
    }
    private func updateMode(_ mode: MusicPlayMode, local: MusicV2LocalPlaylist) async {
        await write(local: local) {
            let path = try MusicLocalPlaylistBridge.path(local.id)
            let _: String = try await environment.apiClient.put("/user/playlists/\(path)/play-mode", body: UpdateMusicPlayModeRequest(playMode: mode.rawValue))
        }
    }
    private func remove(_ member: MusicV2LocalMembership, local: MusicV2LocalPlaylist) async {
        guard member.playlistId == local.id else { return }
        await write(local: local) {
            let playlistPath = try MusicLocalPlaylistBridge.path(local.id)
            let relationPath = try MusicLocalPlaylistBridge.path(member.relationId)
            let _: String = try await environment.apiClient.requestWithoutBody("/user/playlists/\(playlistPath)/songs/\(relationPath)", method: "DELETE")
        }
    }
}
