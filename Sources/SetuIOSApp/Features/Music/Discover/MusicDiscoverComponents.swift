import SetuIOSCore
import SwiftUI

struct MusicDiscoverSourceLabel: View {
    let source: MusicV2DiscoverySource
    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
            if let label = source.label { Text(label) }
            if !source.personalized { Text("非个人定制") }
        }.font(SetuTypography.caption).foregroundStyle(SetuColor.textSecondary)
    }
}

struct MusicDiscoverPlaylistRow: View {
    @Environment(RouterPath.self) private var router
    let flags: MusicFeatureFlags
    private let route: AppRoute?
    private let local: MusicV2LocalPlaylist?
    private let title: String
    private let artwork: String?
    private let description: String?
    private let playCount: Int?
    init(playlist: MusicV2Playlist, flags: MusicFeatureFlags) {
        self.flags = flags
        let id: MusicV2PlaylistID
        switch playlist {
        case .provider(let value):
            local = nil
            id = .provider(value.id); title = value.title; artwork = value.artwork?.url
            description = value.description; playCount = value.playCount
        case .local(let value):
            local = value
            id = .local(value.id); title = value.title; artwork = value.artwork?.url
            description = value.description; playCount = value.playCount
        }
        route = MusicDiscoverRoutes.route(.resource(ref: .playlist(id), label: nil), flags: flags)
    }
    var body: some View {
        Button { if let route { router.navigate(to: route) } } label: {
            if let local { MusicPlaylistCompactRow(playlist: local) }
            else { RecommendedPlaylistRow(title: title, artwork: artwork, description: description, playCount: playCount) }
        }.setuButtonFeedback().disabled(route == nil)
    }
}

struct MusicDiscoverAlbumRow: View {
    @Environment(RouterPath.self) private var router
    let album: MusicV2Album
    private let route: AppRoute?
    private let artists: String
    init(album: MusicV2Album, flags: MusicFeatureFlags) {
        self.album = album; route = MusicDetailRoutes.album(album.id, flags: flags)
        artists = album.artists.map(\.name).joined(separator: " / ")
    }
    var body: some View {
        Button { if let route { router.navigate(to: route) } } label: {
            RecommendedPlaylistRow(title: album.title, artwork: album.artwork?.url, description: artists, playCount: nil)
        }.setuButtonFeedback().disabled(route == nil)
    }
}

struct MusicDiscoverMore: View {
    let nextOffset: Int?
    let loading: Bool
    let error: UserFacingError?
    let load: () async -> Void
    var body: some View {
        if let error { Text(error.message).foregroundStyle(SetuColor.textSecondary) }
        if nextOffset != nil {
            if loading { ProgressView("正在加载更多") }
            else { Button(error == nil ? "加载更多" : "重试加载更多") { Task { await load() } }.frame(minHeight: 44) }
        }
    }
}

struct MusicDiscoverPlaylistCard: View {
    @Environment(RouterPath.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let width: CGFloat
    private let title: String
    private let artwork: String?
    private let route: AppRoute?

    init(playlist: MusicV2Playlist, flags: MusicFeatureFlags, width: CGFloat = 144) {
        self.width = width
        let id: MusicV2PlaylistID
        switch playlist {
        case .provider(let value):
            id = .provider(value.id); title = value.title; artwork = value.artwork?.url
        case .local(let value):
            id = .local(value.id); title = value.title; artwork = value.artwork?.url
        }
        route = MusicDiscoverRoutes.route(.resource(ref: .playlist(id), label: nil), flags: flags)
    }

    var body: some View {
        Button { if let route { router.navigate(to: route) } } label: {
            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                MusicArtworkView(urlString: artwork, width: width, height: width, cornerRadius: 16, artworkSize: .lockScreen)
                Text(title).font(.subheadline.weight(.medium))
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(width: width, alignment: .topLeading).contentShape(Rectangle())
        }.setuButtonFeedback(cornerRadius: 16).disabled(route == nil)
    }
}
