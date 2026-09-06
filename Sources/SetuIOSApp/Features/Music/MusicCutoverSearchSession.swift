import Foundation
import Observation
import SetuIOSCore

/// P9 repository owns caching; this session only owns the current search and source cursor.
@MainActor @Observable
final class MusicCutoverSearchSession {
    var query = ""
    var scope: MusicV2SearchScope = .tracks
    private(set) var pages: [MusicV2SearchResult] = []
    private(set) var loading = false
    private(set) var error: UserFacingError?
    private(set) var nextOffset: Int?
    @ObservationIgnored private var repository: MusicRepository
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var submittedQuery = ""
    @ObservationIgnored private var submittedScope: MusicV2SearchScope = .tracks

    init(repository: MusicRepository) { self.repository = repository }
    func reset(repository: MusicRepository) {
        revision = UUID(); self.repository = repository
        query = ""; pages = []; error = nil; loading = false; nextOffset = nil
    }
    func submit(client: MusicV2Client, more: Bool = false) async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        if more { guard !loading, nextOffset != nil, submittedQuery == normalized, submittedScope == scope else { return } }
        else { revision = UUID(); pages = []; nextOffset = nil; submittedQuery = normalized; submittedScope = scope }
        let ticket = revision, offset = more ? nextOffset! : 0, selected = scope
        let started = ProcessInfo.processInfo.systemUptime
        loading = true; error = nil
        defer { if revision == ticket { loading = false } }
        do {
            let result = try await repository.value(for: .searchV2(client: client, keywords: normalized, scope: selected, offset: offset), force: !more)
            guard revision == ticket, !Task.isCancelled else { return }
            let cursor = selected == .all ? nil : result.value.sections.first.flatMap(Self.cursor)
            guard cursor == nil || cursor! > offset else { throw UserFacingError(message: "分页未前进，请重新搜索") }
            // A failed section retains its cursor so a page can be retried, never silently skips data.
            if more, result.value.sections.contains(where: { if case .failed = $0 { true } else { false } }) {
                throw UserFacingError(message: "搜索暂时不可用，请重试")
            }
            pages.append(result.value); nextOffset = cursor
            MusicClientObservation.emit("search.ready", start: started, v2: true)
        } catch {
            guard revision == ticket, !Task.isCancelled else { return }
            self.error = UserFacingErrorMapper.map(error)
        }
    }
    private static func cursor(_ section: MusicV2SearchSection) -> Int? {
        switch section {
        case .tracks(let p): p.nextOffset
        case .artists(let p): p.nextOffset
        case .albums(let p): p.nextOffset
        case .playlists(let p): p.nextOffset
        case .mvs(let p): p.nextOffset
        default: nil
        }
    }
}
