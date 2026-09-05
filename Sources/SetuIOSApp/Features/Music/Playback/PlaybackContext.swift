import Foundation

/// Client-owned provenance for the queue. It is persisted locally only and is
/// never treated as a server-side queue or resource identifier.
enum PlaybackContext: Sendable, Codable {
    struct OpaqueID: RawRepresentable, Sendable, Codable, Equatable {
        let rawValue: String
        init(rawValue: String) { self.rawValue = rawValue }
    }

    enum ProviderPlaylistID: Sendable, Codable, Equatable {
        case canonical(OpaqueID)
        case legacy(Int)
    }

    enum LocalPlaylistID: Sendable, Codable, Equatable {
        case canonical(OpaqueID)
        case legacy(Int)
    }

    enum PlaylistID: Sendable, Codable, Equatable {
        case provider(ProviderPlaylistID)
        case local(LocalPlaylistID)
    }

    enum TrackID: Sendable, Codable, Equatable {
        case canonical(OpaqueID)
        case legacyProvider(Int)
    }

    enum ArtistSelection: String, Sendable, Codable {
        case topTracks
    }

    enum SearchScope: String, Sendable, Codable {
        case tracks
    }

    enum UnknownReason: String, Sendable, Codable {
        case legacySnapshot
        case missingProvenance
    }

    enum DiscoveryKind: String, Sendable, Codable {
        case editorial
        case curated
        case sharedAlgorithmic
        case ranking
        case newRelease
        case historyDerived
        case personalized
    }

    enum DiscoveryAudience: String, Sendable, Codable {
        case shared
        case setuUser
    }

    struct DiscoverySource: Sendable, Codable {
        let kind: DiscoveryKind
        let audience: DiscoveryAudience
        let personalized: Bool
        let catalogSource: String?
        let ownerID: String?
        let label: String?

        static func sharedAlgorithmic(label: String? = nil) -> Self {
            Self(
                kind: .sharedAlgorithmic,
                audience: .shared,
                personalized: false,
                catalogSource: "netease",
                ownerID: nil,
                label: label
            )
        }

        fileprivate var identity: Identity {
            Identity(
                kind: kind,
                audience: audience,
                personalized: personalized,
                catalogSource: catalogSource,
                ownerID: ownerID
            )
        }

        fileprivate struct Identity: Equatable {
            let kind: DiscoveryKind
            let audience: DiscoveryAudience
            let personalized: Bool
            let catalogSource: String?
            let ownerID: String?
        }
    }

    case playlist(id: PlaylistID, label: String?)
    case album(id: String, label: String?)
    case artist(id: String, selection: ArtistSelection, label: String?)
    case search(query: String, scope: SearchScope, label: String?)
    case liked(ownerID: String, label: String?)
    case history(ownerID: String, label: String?)
    case discovery(source: DiscoverySource, selectionKey: String, label: String?)
    case radio(sessionID: String, source: DiscoverySource, label: String?)
    case singleTrack(trackID: TrackID, label: String?)
    case unknown(reason: UnknownReason, label: String?)

    var label: String? {
        switch self {
        case .playlist(_, let label), .album(_, let label), .artist(_, _, let label),
             .search(_, _, let label), .liked(_, let label), .history(_, let label),
             .discovery(_, _, let label), .radio(_, _, let label),
             .singleTrack(_, let label), .unknown(_, let label):
            label
        }
    }

    var isInfinite: Bool {
        if case .radio = self { return true }
        return false
    }

    var allowsPrevious: Bool {
        switch self {
        case .radio, .singleTrack:
            false
        default:
            true
        }
    }

    var allowsQueueEdit: Bool {
        if case .radio = self { return false }
        return true
    }

    /// Domain equality deliberately ignores display labels.
    func hasSameSource(as other: Self) -> Bool {
        switch (self, other) {
        case (.playlist(let lhs, _), .playlist(let rhs, _)): lhs == rhs
        case (.album(let lhs, _), .album(let rhs, _)): lhs == rhs
        case (.artist(let lhsID, let lhsSelection, _), .artist(let rhsID, let rhsSelection, _)):
            lhsID == rhsID && lhsSelection == rhsSelection
        case (.search(let lhsQuery, let lhsScope, _), .search(let rhsQuery, let rhsScope, _)):
            lhsQuery == rhsQuery && lhsScope == rhsScope
        case (.liked(let lhs, _), .liked(let rhs, _)): lhs == rhs
        case (.history(let lhs, _), .history(let rhs, _)): lhs == rhs
        case (.discovery(let lhsSource, let lhsKey, _), .discovery(let rhsSource, let rhsKey, _)):
            lhsSource.identity == rhsSource.identity && lhsKey == rhsKey
        case (.radio(let lhsSession, let lhsSource, _), .radio(let rhsSession, let rhsSource, _)):
            lhsSession == rhsSession && lhsSource.identity == rhsSource.identity
        case (.singleTrack(let lhs, _), .singleTrack(let rhs, _)): lhs == rhs
        case (.unknown(let lhs, _), .unknown(let rhs, _)): lhs == rhs
        default: false
        }
    }
}

extension PlaybackContext: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hasSameSource(as: rhs)
    }
}
