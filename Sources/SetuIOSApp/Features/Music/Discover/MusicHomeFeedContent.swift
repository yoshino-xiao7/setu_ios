import SetuIOSCore
import SwiftUI

struct MusicHomeFeedContent: View {
    let resource: MusicResource<MusicV2HomeFeed>
    let flags: MusicFeatureFlags
    let userID: Int?
    let retry: () async -> Void
    var recommendations: MusicResource<MusicV2RecommendedPlaylists>? = nil

    var body: some View {
        Group {
            MusicDetailState(resource: resource, retry: retry) { feed in
                let presentation = MusicHomeFeedPresentation(feed: feed, flags: flags)
                let unavailable = presentation.unavailableTitles.filter { title in
                    recommendations == nil || !feed.sections.contains {
                        $0.title == title && $0.kind == .recommendedPlaylists
                    }
                }
                if !unavailable.isEmpty {
                    Section {
                        SetuCard {
                            HStack(alignment: .top, spacing: SetuSpacing.md) {
                                Image(systemName: "arrow.clockwise.circle").foregroundStyle(SetuColor.textSecondary)
                                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                                    Text("未能加载：" + unavailable.joined(separator: "、")).font(.subheadline.weight(.semibold))
                                    Text("请稍后重试。")
                                        .font(SetuTypography.caption).foregroundStyle(SetuColor.textSecondary)
                                }
                                Spacer(minLength: 0)
                                Button("重试") { Task { await retry() } }.frame(minHeight: 44)
                            }
                        }.setuListRow()
                    }.accessibilityIdentifier("music.home.discovery.retry")
                }
                ForEach(presentation.sections, id: \.id) { section in
                    MusicHomeSectionView(model: .init(section, userID: userID), flags: flags, retry: retry)
                }
            }
            if let recommendations, flags.usesV2PlaylistDetail,
               resource.error?.action != .signIn,
               !(resource.value?.sections.contains { $0.kind == .recommendedPlaylists && !$0.items.isEmpty } ?? false) {
                MusicRecommendedPlaylistsShelf(resource: recommendations, flags: flags, retry: retry)
            }
        }
    }
}

struct MusicRecommendedPlaylistsShelf: View {
    @Environment(RouterPath.self) private var router
    let resource: MusicResource<MusicV2RecommendedPlaylists>
    let flags: MusicFeatureFlags
    let retry: () async -> Void
    var body: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "推荐歌单", actionTitle: "全部",
                                      action: { router.navigate(to: .recommendedPlaylists) })
                    if let value = resource.value {
                        if value.items.isEmpty {
                            Text("暂无推荐歌单").font(SetuTypography.caption).foregroundStyle(SetuColor.textSecondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: SetuSpacing.md) {
                                    ForEach(Array(value.items.prefix(8)), id: \.id) { playlist in
                                        MusicDiscoverPlaylistCard(playlist: .provider(playlist), flags: flags)
                                    }
                                }
                            }
                        }
                    }
                    if let error = resource.error {
                        Text(error.message).font(SetuTypography.caption).foregroundStyle(SetuColor.textSecondary)
                        if error.action == .signIn {
                            NavigationLink("重新登录", value: AppRoute.account).frame(minHeight: 44)
                        } else {
                            Button("重新加载歌单") { Task { await retry() } }.frame(minHeight: 44)
                        }
                    } else if resource.value == nil {
                        ProgressView("正在加载歌单").frame(maxWidth: .infinity, minHeight: 88)
                    }
                }
            }.setuListRow()
        }
    }
}

struct MusicHomeSectionView: View {
    @Environment(RouterPath.self) private var router
    @Environment(\.musicPlaybackIntent) private var intent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let model: MusicHomeSectionPresentation
    let flags: MusicFeatureFlags
    let retry: () async -> Void

    var body: some View {
        Section {
            SetuCard {
                LazyVStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: model.section.title, subtitle: model.section.subtitle,
                        actionTitle: showsRecommendationsEntry ? "查看全部" : nil,
                        action: showsRecommendationsEntry ? { router.navigate(to: .recommendedPlaylists) } : nil)
                    if let label = model.section.source?.label {
                        Text(label).font(SetuTypography.caption).foregroundStyle(SetuColor.textSecondary)
                    }
                    if model.section.degraded {
                        Text("部分内容暂未更新，保留已加载内容")
                            .font(SetuTypography.caption).foregroundStyle(SetuColor.textSecondary)
                        Button("重试") { Task { await retry() } }.frame(minHeight: 44)

                    }
                    switch model.section.kind {
                    case .continueListening:
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: SetuSpacing.md) {
                                ForEach(model.tracks, id: \.id) { track in
                                    MusicRecentHistoryCard(track: track) {
                                        Task { await intent?.play(track, in: model.tracks, context: model.context) }
                                    }
                                }
                            }
                        }
                    case .recommendedPlaylists, .favoritePlaylists, .rankings:
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: SetuSpacing.md) {
                                ForEach(Array(model.section.items.prefix(8).enumerated()), id: \.offset) { _, item in
                                    if case .playlist(let playlist) = item {
                                        MusicDiscoverPlaylistCard(playlist: playlist, flags: flags)
                                    }
                                }
                            }
                        }
                    case .hotSearch, .quickEntries:
                        LazyVGrid(columns: columns, alignment: .leading, spacing: SetuSpacing.sm) {
                            items
                        }
                    default: items
                    }
                    if !showsRecommendationsEntry, let route = MusicDiscoverRoutes.route(model.section.action, flags: flags) {
                        Button { router.navigate(to: route) } label: {
                            HStack { Text(model.actionTitle); Spacer(); Image(systemName: "chevron.right") }
                                .font(.footnote.weight(.semibold)).foregroundStyle(SetuColor.brandInk)
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }.setuButtonFeedback()
                    }
                }
            }.setuListRow()
        }.accessibilityIdentifier("music.home.v2.section.\(model.id)")
    }

    private var showsRecommendationsEntry: Bool { model.section.kind == .recommendedPlaylists && flags.usesV2Home }

    private func isHiddenRadio(_ action: MusicV2HomeAction) -> Bool {
        if case .discovery("radio", _) = action { return !flags.radioFMEnabled }
        if case .library("liked", _) = action { return !flags.likedTracksEnabled }
        if case .library("savedPlaylists", _) = action { return !flags.favoritePlaylistsEnabled }
        return false
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 96), spacing: SetuSpacing.sm)]
    }
    @ViewBuilder private var items: some View {
        ForEach(Array(model.section.items.indices.prefix(5)), id: \.self) { index in
            switch model.section.items[index] {
            case .track(let track):
                MusicDetailTrackRow(track: track, tracks: model.tracks, context: model.context, flags: flags)
            case .playlist(let playlist): MusicDiscoverPlaylistRow(playlist: playlist, flags: flags)
            case .album(let album): MusicDiscoverAlbumRow(album: album, flags: flags)
            case .keyword(let query, _):
                Button { router.navigate(to: .musicSearch(query)) } label: {
                    MusicHomeKeywordLabel(query: query, index: index)
                }.setuButtonFeedback(cornerRadius: 22)
            case .entry(_, let title, let action, _):
                let route = MusicDiscoverRoutes.route(action, flags: flags)
                if !isHiddenRadio(action) {
                    Button(title) { if let route { router.navigate(to: route) } }
                        .font(.caption.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(route == nil)
                }
            case .unknown: EmptyView()
            }
        }
    }
}

struct MusicHomeKeywordLabel: View {
    let query: String
    let index: Int
    var body: some View {
        HStack(spacing: SetuSpacing.xs) {
            Image(systemName: index < 3 ? "flame.fill" : "magnifyingglass").accessibilityHidden(true)
            Text(query).fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(index < 3 ? SetuColor.brandInk : SetuColor.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.vertical, SetuSpacing.xs).padding(.horizontal, SetuSpacing.sm)
        .background(SetuColor.surfaceMuted, in: Capsule())
    }
}
