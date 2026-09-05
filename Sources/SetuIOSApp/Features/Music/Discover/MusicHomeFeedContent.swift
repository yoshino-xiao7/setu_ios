import SetuIOSCore
import SwiftUI

struct MusicHomeFeedContent: View {
    let resource: MusicResource<MusicV2HomeFeed>
    let flags: MusicFeatureFlags
    let userID: Int?
    let retry: () async -> Void
    var body: some View {
        MusicDetailState(resource: resource, retry: retry) { feed in
            if feed.sections.isEmpty {
                ContentUnavailableView("暂无音乐内容", systemImage: "music.note")
            }
            ForEach(feed.sections, id: \.id) { section in
                MusicHomeSectionView(model: .init(section, userID: userID), flags: flags, retry: retry)
            }
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
                    SetuSectionHeader(title: model.section.title, subtitle: model.section.subtitle)
                    if let source = model.section.source { MusicDiscoverSourceLabel(source: source) }
                    if model.section.degraded {
                        Text(model.section.items.isEmpty ? "内容暂时不可用" : "刷新暂不可用，正在显示已有内容")
                            .font(SetuTypography.caption).foregroundStyle(SetuColor.textSecondary)
                        Button("重试") { Task { await retry() } }.frame(minHeight: 44)
                    } else if model.section.items.isEmpty {
                        Text("暂无内容").foregroundStyle(SetuColor.textSecondary)
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
                    case .hotSearch, .quickEntries:
                        LazyVGrid(columns: columns, alignment: .leading, spacing: SetuSpacing.sm) {
                            items
                        }
                    default: items
                    }
                    if let route = MusicDiscoverRoutes.route(model.section.action, flags: flags) {
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

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 96), spacing: SetuSpacing.sm)]
    }
    @ViewBuilder private var items: some View {
        ForEach(model.section.items.indices, id: \.self) { index in
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
                Button(title) { if let route { router.navigate(to: route) } }
                    .font(.caption.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(route == nil)
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
