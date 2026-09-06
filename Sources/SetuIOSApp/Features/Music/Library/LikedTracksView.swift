import SetuIOSCore
import SwiftUI

struct LikedTracksView: View {
    @Environment(MusicStore.self) private var store
    @Environment(\.musicPlaybackIntent) private var intent
    let environment: AppEnvironment
    @State private var feedback: SetuFeedback?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SetuSpacing.md) {
                HStack(spacing: SetuSpacing.lg) {
                    Image(systemName: "heart.fill").font(.system(size: 40))
                        .foregroundStyle(SetuColor.brandPink)
                        .frame(width: 88, height: 88)
                        .background(SetuColor.brandSoft.opacity(0.3), in: RoundedRectangle(cornerRadius: 24))
                    VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                        Text("把心动留在这里").font(.title2.weight(.bold))
                        Text("\(store.likedTracks.value?.total ?? 0) 首喜欢的歌曲")
                            .font(.subheadline).foregroundStyle(SetuColor.textSecondary)
                    }
                }.padding(.vertical, SetuSpacing.md)
                if let feedback { SetuFeedbackBanner(feedback: feedback) }
                if environment.config.musicFeatureFlags.favoritePlaylistsEnabled {
                    NavigationLink("收藏歌单", value: AppRoute.favoritePlaylists)
                }
                MusicDetailState(resource: store.likedTracks, retry: { await load(force: true) }) { page in
                    if page.items.isEmpty { ContentUnavailableView("暂无喜欢的歌曲", systemImage: "heart") }
                    if let first = page.items.compactMap(\.track).first, let owner = page.items.first?.ownerID {
                        Button {
                            Task { await intent?.play(first, in: page.items.compactMap(\.track), context: .liked(ownerID: owner, label: "我喜欢")) }
                        } label: {
                            Label(page.nextOffset == nil ? "播放全部" : "播放已加载歌曲", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.borderedProminent).tint(SetuColor.brandPink)
                    }
                    ForEach(page.items) { item in
                        if let track = item.track {
                            MusicSongRow(track: track, onPlay: {
                                Task { await intent?.play(track, in: page.items.compactMap(\.track),
                                    context: .liked(ownerID: item.ownerID, label: "我喜欢")) }
                            }, isLiked: store.likedTrackIDs.contains(item.id.rawValue), onToggleLike: {
                                Task { await toggle(item) }
                            }).disabled(store.libraryWriting)
                        } else {
                            HStack {
                                MusicArtworkView(urlString: nil)
                                Text("歌曲信息暂不可用")
                                Spacer()
                                Button("取消喜欢") { Task { await toggle(item) } }
                                    .frame(minHeight: 44).disabled(store.libraryWriting)
                            }
                        }
                    }
                    if let error = store.libraryMoreErrors["liked"] {
                        Text(error.message)
                        if error.action == .signIn { NavigationLink("重新登录", value: AppRoute.account) }
                    }
                    if page.nextOffset != nil {
                        Button("加载更多") { Task { await store.loadLikedTracks(client: environment.musicV2Client, more: true) } }
                            .frame(minHeight: 44).disabled(store.libraryMoreLoading.contains("liked") || store.libraryWriting)
                    }
                }
            }.padding(SetuSpacing.lg)
        }.setuBackground().navigationTitle("我喜欢")
            .task(id: store.userID) { feedback = nil; await load() }
            .refreshable { await load(force: true) }
    }
    private func load(force: Bool = false) async {
        guard environment.config.musicFeatureFlags.likedTracksEnabled else { return }
        await store.loadLikedTracks(client: environment.musicV2Client, force: force)
    }
    private func toggle(_ item: MusicLibraryTrack) async {
        let owner = store.sessionToken
        do { try await store.toggleLike(item.id, track: item.track, client: environment.musicV2Client,
                                       enabled: environment.config.musicFeatureFlags.likedTracksEnabled) }
        catch { if owner == store.sessionToken { feedback = .error(UserFacingErrorMapper.map(error)) } }
    }
}

struct FavoritePlaylistsView: View {
    @Environment(MusicStore.self) private var store
    let environment: AppEnvironment
    @State private var feedback: SetuFeedback?
    var body: some View {
        List {
            if let feedback { SetuFeedbackBanner(feedback: feedback) }
            MusicDetailState(resource: store.favoritePlaylists, retry: { await load(force: true) }) { page in
                if page.items.isEmpty { ContentUnavailableView("暂无收藏歌单", systemImage: "star") }
                ForEach(page.items) { item in
                    VStack(alignment: .leading) {
                        HStack {
                            MusicArtworkView(urlString: item.playlist?.artwork?.url)
                            if environment.config.musicFeatureFlags.usesV2PlaylistDetail {
                                NavigationLink(item.playlist?.title ?? "歌单信息暂不可用", value: AppRoute.playlistDetailV2(item.id.rawValue))
                            } else { Text(item.playlist?.title ?? "歌单信息暂不可用") }
                        }
                        Button("取消收藏") { Task { await toggle(item) } }
                            .buttonStyle(.borderless).frame(minHeight: 44).disabled(store.libraryWriting)
                    }
                }
                if let error = store.libraryMoreErrors["saved"] {
                    Text(error.message)
                    if error.action == .signIn { NavigationLink("重新登录", value: AppRoute.account) }
                }
                if page.nextOffset != nil {
                    Button("加载更多") { Task { await store.loadFavoritePlaylists(client: environment.musicV2Client, more: true) } }
                        .frame(minHeight: 44).disabled(store.libraryMoreLoading.contains("saved") || store.libraryWriting)
                }
            }
        }.listStyle(.plain).setuBackground().navigationTitle("收藏歌单")
            .task(id: store.userID) { feedback = nil; await load() }.refreshable { await load(force: true) }
    }
    private func load(force: Bool = false) async {
        guard environment.config.musicFeatureFlags.favoritePlaylistsEnabled else { return }
        await store.loadFavoritePlaylists(client: environment.musicV2Client, force: force)
    }
    private func toggle(_ item: MusicLibraryPlaylist) async {
        let owner = store.sessionToken
        do { try await store.toggleFavoritePlaylist(item.id, playlist: item.playlist, client: environment.musicV2Client,
                                                    enabled: environment.config.musicFeatureFlags.favoritePlaylistsEnabled) }
        catch { if owner == store.sessionToken { feedback = .error(UserFacingErrorMapper.map(error)) } }
    }
}
