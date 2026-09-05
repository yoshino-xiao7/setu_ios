#if DEBUG
import Foundation

/// Mock-only P12 responses. No persisted flags, external service or real user data.
enum MusicDiscoverPreviewFixtures {
    static let track: [String: Any] = [
        "id": "netease:track:opaque%2Fp12", "source": "netease", "title": "发现测试歌曲",
        "artists": [["id": "netease:artist:detail", "name": "发现测试歌手", "artwork": NSNull()]],
        "album": ["id": "netease:album:detail", "title": "发现测试专辑", "artwork": NSNull()],
        "availability": ["status": "unknown", "reason": NSNull(), "maxQuality": NSNull()],
        "durationMs": NSNull(), "artwork": NSNull(), "mvId": NSNull(), "aliases": [], "translatedTitle": NSNull()
    ]
    static let album: [String: Any] = [
        "id": "netease:album:detail", "source": "netease", "title": "发现测试专辑", "artists": track["artists"]!,
        "artwork": NSNull(), "releaseDate": NSNull(), "trackCount": NSNull(), "company": NSNull(),
        "description": NSNull(), "editionLabel": NSNull()
    ]
    static let playlist: [String: Any] = [
        "id": "netease:playlist:detail", "origin": "provider", "title": "发现测试榜单", "tags": [], "isRanking": true,
        "artwork": NSNull(), "description": "榜单简介", "trackCount": NSNull(), "playCount": NSNull(),
        "creator": NSNull(), "updatedAt": NSNull(), "updateFrequency": NSNull()
    ]
    static func source(_ kind: String) -> [String: Any] {
        ["kind": kind, "audience": "shared", "personalized": false, "catalogSource": "netease", "label": NSNull(), "ownerId": NSNull()]
    }
    static func action(_ selection: String, label: String) -> [String: Any] {
        ["kind": "discovery", "selection": selection, "label": label]
    }
    static func home(empty: Bool = false) -> [String: Any] {
        var sections: [[String: Any]] = []
        func add(_ kind: String, _ title: String, _ items: [[String: Any]], source: Any, action: Any = NSNull(), degraded: Bool = false) {
            sections.append(["id": kind, "kind": kind, "title": title, "subtitle": NSNull(), "items": items,
                "source": source, "action": action, "degraded": degraded])
        }
        let entries = [("dailyTracks", "每日推荐"), ("rankings", "排行榜"), ("radio", "电台"), ("liked", "我喜欢")].map { key, title -> [String: Any] in
            let route: [String: Any] = key == "liked" ? ["kind": "library", "collection": "liked", "label": title] : action(key, label: title)
            return ["kind": "entry", "key": key, "title": title, "action": route, "count": NSNull()]
        }
        add("quickEntries", "发现音乐", entries, source: NSNull())
        add("dailyTracks", "每日歌曲", [["kind": "track", "track": track]], source: source("sharedAlgorithmic"), action: action("dailyTracks", label: "全部推荐"), degraded: true)
        add("newTracks", "新歌速递", [["kind": "track", "track": track]], source: source("newRelease"), action: action("newTracks", label: "全部新歌"))
        add("newAlbums", "新专辑", [["kind": "album", "album": album]], source: source("newRelease"), action: action("newAlbums", label: "全部新专辑"))
        add("rankings", "榜单精选", [["kind": "playlist", "playlist": playlist]], source: source("ranking"))
        add("recommendedPlaylists", "推荐歌单", [], source: source("sharedAlgorithmic"), degraded: true)
        add("hotSearch", "热门搜索", [["kind": "keyword", "query": "发现关键词", "rank": 1]], source: source("ranking"))
        add("continueListening", "继续听", [["kind": "track", "track": track]], source: NSNull())
        add("favoritePlaylists", "收藏歌单", [], source: NSNull())
        sections.insert(["id": "future", "kind": "futureKind", "unrecognized": true], at: 1)
        return ["sections": empty ? [] : sections, "generatedAt": "2026-09-05T00:00:00Z"]
    }
    static func response(path: String, query: String?) -> (Int, Data) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-ui-testing-discover-error") || args.contains("-ui-testing-discover-unauthorized") {
            let unauthorized = args.contains("-ui-testing-discover-unauthorized")
            return (unauthorized ? 401 : 503, data(["code": unauthorized ? "UNAUTHORIZED" : "UPSTREAM_UNAVAILABLE",
                "message": unauthorized ? "请先登录" : "发现服务暂时不可用", "retryable": !unauthorized, "traceId": NSNull()]))
        }
        let empty = args.contains("-ui-testing-discover-empty")
        let body: [String: Any]
        switch path {
        case "/user/music/v2/home": body = home(empty: empty)
        case "/user/music/v2/rankings": body = ["items": empty ? [] : [playlist], "source": source("ranking")]
        case "/user/music/v2/recommend/tracks": body = ["tracks": empty ? [] : [track], "source": source("sharedAlgorithmic")]
        case "/user/music/v2/new-releases/tracks", "/user/music/v2/new-releases/albums":
            let params = URLComponents(string: "https://fixture.invalid/?" + (query ?? ""))?.queryItems ?? []
            let offset = Int(params.first { $0.name == "offset" }?.value ?? "0") ?? 0
            let area = params.first { $0.name == "area" }?.value ?? "all"
            var item = path.hasSuffix("/albums") ? album : track
            item["id"] = path.hasSuffix("/albums") ? "netease:album:detail" : "netease:track:p12-\(area)-\(offset)"
            if offset > 0 { item["title"] = "分页发现歌曲"; if path.hasSuffix("/albums") { item["id"] = "netease:album:detail-\(offset)" } }
            let page: [String: Any] = ["items": empty ? [] : [item], "offset": offset, "limit": 30,
                "hasMore": !empty && offset == 0, "nextOffset": !empty && offset == 0 ? 37 : NSNull(), "total": NSNull()]
            body = ["area": area, "items": page, "source": source("newRelease")]
        default: return MusicDetailPreviewFixtures.response(path: path, query: query)
        }
        return (200, data(body))
    }
    static func data(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
}
#endif
