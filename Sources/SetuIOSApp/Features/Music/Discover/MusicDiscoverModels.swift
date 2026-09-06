import Foundation
import SetuIOSCore

struct MusicDiscoverPage<Item: Sendable>: Sendable {
    var items: [Item]
    let source: MusicV2DiscoverySource
    var nextOffset: Int?
    var loadedOffsets: [Int]
}

enum MusicDiscoverRoutes {
    static func route(_ action: MusicV2HomeAction?, flags: MusicFeatureFlags) -> AppRoute? {
        guard let action else { return nil }
        switch action {
        case .search(let query, _): return .musicSearch(query)
        case .discovery(let selection, _):
            switch selection {
            case "dailyTracks": return flags.usesV2Home ? .dailyRecommend : nil
            case "recommendedPlaylists": return flags.usesV2Home ? .recommendedPlaylists : nil
            case "rankings": return flags.rankingsEnabled ? .rankings : nil
            case "newTracks": return flags.newReleasesEnabled ? .newReleases(albums: false) : nil
            case "newAlbums": return flags.newReleasesEnabled ? .newReleases(albums: true) : nil
            case "radio": return flags.radioFMEnabled ? .radioFM : nil
            default: return nil // Later-phase capabilities remain unavailable.
            }
        case .library(let collection, _):
            switch collection {
            case "history": return .musicHistory
            case "liked": return flags.likedTracksEnabled ? .likedTracks : nil
            case "savedPlaylists": return flags.favoritePlaylistsEnabled ? .favoritePlaylists : nil
            default: return nil
            }
        case .resource(let ref, _):
            switch ref {
            case .artist(let id): return MusicDetailRoutes.artist(id, flags: flags)
            case .album(let id): return MusicDetailRoutes.album(id, flags: flags)
            case .playlist(let id):
                guard flags.usesV2PlaylistDetail else { return nil }
                if case .unknown = id { return nil }
                return .playlistDetailV2(id.rawValue)
            default: return nil
            }
        case .disabled: return nil
        }
    }

    static func context(source: MusicV2DiscoverySource?, selection: String, title: String) -> PlaybackContext {
        guard let source, let audience = PlaybackContext.DiscoveryAudience(rawValue: source.audience) else {
            return .unknown(reason: .missingProvenance, label: title)
        }
        let kind: PlaybackContext.DiscoveryKind
        switch source.kind {
        case .editorial: kind = .editorial
        case .curated: kind = .curated
        case .sharedAlgorithmic: kind = .sharedAlgorithmic
        case .ranking: kind = .ranking
        case .newRelease: kind = .newRelease
        case .historyDerived: kind = .historyDerived
        case .personalized: kind = .personalized
        case .unknown: return .unknown(reason: .missingProvenance, label: title)
        }
        return .discovery(source: .init(kind: kind, audience: audience, personalized: source.personalized,
            catalogSource: source.catalogSource, ownerID: source.ownerId?.rawValue, label: source.label),
            selectionKey: selection, label: title)
    }
}

/// Presentation-only projection. Server ordering and exact typed IDs remain untouched.
struct MusicHomeSectionPresentation: Identifiable {
    let section: MusicV2HomeSection
    let tracks: [MusicV2Track]
    let context: PlaybackContext
    let actionTitle: String
    var id: String { section.id }
    init(_ section: MusicV2HomeSection, userID: Int?) {
        self.section = section
        switch section.action {
        case .resource(_, let label), .discovery(_, let label), .library(_, let label), .search(_, let label): actionTitle = label ?? "查看全部"
        default: actionTitle = "查看全部"
        }
        tracks = section.items.compactMap { if case .track(let track) = $0 { return track }; return nil }
        if section.kind == .continueListening, let userID {
            context = .history(ownerID: "setu:user:\(userID)", label: section.title)
        } else {
            context = MusicDiscoverRoutes.context(source: section.source, selection: section.kind.rawValue, title: section.title)
        }
    }
}

/// Local navigation stays reachable even when the Home feed is empty or unavailable.
struct MusicHomeShortcut: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let route: AppRoute

    static func entries(flags: MusicFeatureFlags) -> [Self] {
        var entries: [Self] = [
            .init(id: "history", title: "播放历史", symbol: "clock.arrow.circlepath", route: .musicHistory),
            .init(id: "playlists", title: "我的歌单", symbol: "music.note.list", route: .playlists),
        ]
        if flags.likedTracksEnabled { entries.append(.init(id: "liked", title: "我喜欢", symbol: "heart.fill", route: .likedTracks)) }
        if flags.favoritePlaylistsEnabled { entries.append(.init(id: "saved", title: "收藏歌单", symbol: "bookmark.fill", route: .favoritePlaylists)) }
        if flags.radioFMEnabled { entries.append(.init(id: "fm", title: "私人 FM", symbol: "dot.radiowaves.left.and.right", route: .radioFM)) }
        if flags.usesV2Home {
            entries.append(.init(id: "daily", title: "每日推荐", symbol: "sparkles", route: .dailyRecommend))
            entries.append(.init(id: "recommended", title: "推荐歌单", symbol: "square.stack", route: .recommendedPlaylists))
        }
        return entries
    }
}

struct MusicHomeFeedPresentation {
    let sections: [MusicV2HomeSection]
    let unavailableTitles: [String]

    init(feed: MusicV2HomeFeed, flags: MusicFeatureFlags) {
        let supported = feed.sections.filter { section in
            switch section.kind {
            // These have dedicated local navigation or retained data sources on the dashboard.
            case .quickEntries, .continueListening, .dailyTracks, .hotSearch: return false
            case .rankings: return flags.rankingsEnabled && flags.usesV2PlaylistDetail
            case .newAlbums: return flags.albumDetailEnabled
            case .favoritePlaylists: return flags.favoritePlaylistsEnabled && flags.usesV2PlaylistDetail
            case .recommendedPlaylists: return flags.usesV2PlaylistDetail
            case .newTracks: return true
            }
        }
        sections = supported.filter { !$0.items.isEmpty }
        unavailableTitles = supported.filter { $0.degraded && $0.items.isEmpty }.map(\.title)
    }
}
