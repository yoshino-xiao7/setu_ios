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
            case "rankings": return flags.rankingsEnabled ? .rankings : nil
            case "newTracks": return flags.newReleasesEnabled ? .newReleases(albums: false) : nil
            case "newAlbums": return flags.newReleasesEnabled ? .newReleases(albums: true) : nil
            default: return nil // Radio and later-phase capabilities remain unavailable.
            }
        case .library(let collection, _): return collection == "history" ? .musicHistory : nil
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
