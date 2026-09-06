import SetuIOSCore
import SwiftUI

struct MusicLikeButton: View {
    @Environment(MusicStore.self) private var store
    let id: MusicV2TrackID
    let environment: AppEnvironment
    var iconOnly = false
    @State private var feedback: SetuFeedback?
    var body: some View {
        VStack {
            if let feedback, !iconOnly { SetuFeedbackBanner(feedback: feedback) }
            Button {
                if store.likedState(id) == nil {
                    Task { await store.prepareLikedState(client: environment.musicV2Client) }
                    return
                }
                let owner = store.sessionToken
                Task {
                    do { try await store.toggleLike(id, client: environment.musicV2Client,
                        enabled: environment.config.musicFeatureFlags.likedTracksEnabled) }
                    catch { if owner == store.sessionToken { feedback = .error(UserFacingErrorMapper.map(error)) } }
                }
            } label: {
                if iconOnly {
                    Image(systemName: store.likedState(id) == true ? "heart.fill" : "heart")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                } else {
                    Label(store.likedState(id) == true ? "取消喜欢" : "喜欢", systemImage: store.likedState(id) == true ? "heart.fill" : "heart")
                        .frame(minHeight: 44)
                }
            }
            .accessibilityLabel(store.likedState(id) == nil ? "重新加载喜欢状态" : (store.likedState(id) == true ? "取消喜欢" : "喜欢"))
            .disabled(store.libraryWriting || (store.likedState(id) == nil && (!iconOnly || store.likedTracks.isRefreshing)))
            .setuButtonFeedback()
            if !iconOnly, store.likedState(id) == nil, !store.likedTracks.isRefreshing {
                Button("重新加载喜欢状态") { Task { await store.prepareLikedState(client: environment.musicV2Client) } }
                    .frame(minHeight: 44)
            }
        }
        .alert("喜欢操作未完成", isPresented: Binding(
            get: { iconOnly && feedback != nil },
            set: { if !$0 { feedback = nil } }
        )) { Button("好") { feedback = nil } } message: { Text(feedback?.message ?? "") }
        .task(id: store.userID) {
            feedback = nil
            guard environment.config.musicFeatureFlags.likedTracksEnabled else { return }
            await store.prepareLikedState(client: environment.musicV2Client)
        }
    }
}

struct MusicSavePlaylistButton: View {
    @Environment(MusicStore.self) private var store
    let playlist: MusicV2ProviderPlaylist
    let environment: AppEnvironment
    @State private var feedback: SetuFeedback?
    var body: some View {
        VStack(alignment: .leading) {
            if let feedback { SetuFeedbackBanner(feedback: feedback) }
            Button {
                let owner = store.sessionToken
                Task {
                    do { try await store.toggleFavoritePlaylist(playlist.id, playlist: playlist, client: environment.musicV2Client,
                        enabled: environment.config.musicFeatureFlags.favoritePlaylistsEnabled) }
                    catch { if owner == store.sessionToken { feedback = .error(UserFacingErrorMapper.map(error)) } }
                }
            } label: {
                Label(store.savedState(playlist.id) == true ? "取消收藏" : "收藏歌单",
                      systemImage: store.savedState(playlist.id) == true ? "star.fill" : "star").frame(minHeight: 44)
            }.disabled(store.libraryWriting || store.savedState(playlist.id) == nil).setuButtonFeedback()
            if store.savedState(playlist.id) == nil, !store.favoritePlaylists.isRefreshing {
                Button("重新加载收藏状态") { Task { await store.prepareSavedState(client: environment.musicV2Client) } }.frame(minHeight: 44)
            }
            NavigationLink("查看收藏歌单", value: AppRoute.favoritePlaylists).frame(minHeight: 44)
        }.task(id: store.userID) {
            feedback = nil
            guard environment.config.musicFeatureFlags.favoritePlaylistsEnabled else { return }
            await store.prepareSavedState(client: environment.musicV2Client)
        }
    }
}
