import SetuIOSCore
import SwiftUI

struct MusicDetailState<Value: Sendable, Content: View>: View {
    let resource: MusicResource<Value>
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch resource.state {
        case .idle, .loading:
            Section { ProgressView("正在加载").frame(maxWidth: .infinity, minHeight: 88) }
        case .failed(let error):
            Section {
                ContentUnavailableView {
                    Label(error.action == .signIn ? "请先登录" : error.title,
                          systemImage: error.action == .signIn ? "person.crop.circle" : "exclamationmark.triangle")
                } description: { Text(error.message) } actions: {
                    if error.action == .signIn { NavigationLink("重新登录", value: AppRoute.account) }
                    else { Button("重试") { Task { await retry() } }.frame(minHeight: 44) }
                }
            }
        case .loaded(let value):
            if let error = resource.error {
                Section {
                    Text(error.message).foregroundStyle(SetuColor.textSecondary)
                    if error.action == .signIn { NavigationLink("重新登录", value: AppRoute.account) }
                    else { Button("重新加载") { Task { await retry() } }.frame(minHeight: 44) }
                }
            }
            content(value)
        }
    }
}

struct MusicDetailHeader: View {
    let title: String
    let description: String?
    let artwork: String?
    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.md) {
            MusicArtworkView(urlString: artwork, width: 144, height: 144)
            Text(title).font(SetuTypography.title).foregroundStyle(SetuColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let description, !description.isEmpty {
                Text(description).font(SetuTypography.body).foregroundStyle(SetuColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, SetuSpacing.sm)
    }
}

enum MusicDetailRoutes {
    static func artist(_ id: MusicV2ArtistID?, flags: MusicFeatureFlags) -> AppRoute? {
        guard flags.artistDetailEnabled, let id, id.rawValue.hasPrefix("netease:artist:") else { return nil }
        return .artistDetail(id.rawValue)
    }
    static func album(_ id: MusicV2AlbumID?, flags: MusicFeatureFlags) -> AppRoute? {
        guard flags.albumDetailEnabled, let id, id.rawValue.hasPrefix("netease:album:") else { return nil }
        return .albumDetail(id.rawValue)
    }
    static func playlistID(_ raw: String) -> MusicV2PlaylistID {
        (try? JSONDecoder().decode(MusicV2PlaylistID.self, from: JSONEncoder().encode(raw))) ?? .unknown(raw)
    }
}

struct MusicDetailTrackRow: View {
    @Environment(\.musicPlaybackIntent) private var intent
    @Environment(RouterPath.self) private var router
    let track: MusicV2Track
    let tracks: [MusicV2Track]
    let context: PlaybackContext
    let flags: MusicFeatureFlags

    var body: some View {
        MusicSongRow(track: track, onPlay: { Task { await intent?.play(track, in: tracks, context: context) } },
                     onArtist: callback(MusicDetailRoutes.artist(track.artists.first?.id, flags: flags)),
                     onAlbum: callback(MusicDetailRoutes.album(track.album?.id, flags: flags)),
                     isLiked: intent?.store.likedState(track.id) == true, onToggleLike: likeCallback)
            .task(id: intent?.store.userID) {
                if flags.likedTracksEnabled, let client = intent?.libraryClient {
                    await intent?.store.prepareLikedState(client: client)
                }
            }
            .contextMenu {
                Button("下一首播放") { intent?.playNext(track) }
                ForEach(track.artists.indices, id: \.self) { index in
                    if let route = MusicDetailRoutes.artist(track.artists[index].id, flags: flags) {
                        Button(track.artists[index].name) { router.navigate(to: route) }
                    }
                }
            }
    }
    private var likeCallback: (() -> Void)? {
        guard flags.likedTracksEnabled, let intent, let client = intent.libraryClient,
              intent.store.likedState(track.id) != nil else { return nil }
        return {
            guard !intent.store.libraryWriting else { return }
            Task { await intent.toggleLike(track, client: client, enabled: flags.likedTracksEnabled) }
        }
    }
    private func callback(_ route: AppRoute?) -> (() -> Void)? {
        guard let route else { return nil }
        return { router.navigate(to: route) }
    }
}

struct MusicDetailTracks: View {
    @Environment(\.musicPlaybackIntent) private var intent
    let tracks: [MusicV2Track]
    let context: PlaybackContext
    let flags: MusicFeatureFlags
    var body: some View {
        if let first = tracks.first {
            Button { Task { await intent?.play(first, in: tracks, context: context) } } label: {
                Label("播放全部", systemImage: "play.fill").frame(minHeight: 44)
            }
            ForEach(tracks, id: \.id) { track in
                MusicDetailTrackRow(track: track, tracks: tracks, context: context, flags: flags)
            }
        } else {
            ContentUnavailableView("暂无歌曲", systemImage: "music.note", description: Text("当前列表为空"))
        }
    }
}
