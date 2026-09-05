#if DEBUG
import Foundation

/// Only reachable from the existing isolated preview transport. No real flags or data.
enum MusicLibraryPreviewFixtures {
    private static let lock = NSLock()
    private static var removed: Set<String> = []
    static func response(_ request: URLRequest) -> (Int, Data) {
        lock.lock(); defer { lock.unlock() }
        let args = ProcessInfo.processInfo.arguments
        let error: [String: Any] = ["code": args.contains("-ui-testing-library-unauthorized") ? "UNAUTHORIZED" : "UPSTREAM_UNAVAILABLE",
            "message": "用户库测试错误", "retryable": true, "traceId": NSNull()]
        if args.contains("-ui-testing-library-unauthorized") { return (401, data(error)) }
        if args.contains("-ui-testing-library-error") { return (503, data(error)) }
        let path = request.url?.path ?? ""
        if request.httpMethod != "GET" {
            if args.contains("-ui-testing-library-write-failure") { return (503, data(error)) }
            removed.insert(path.components(separatedBy: "/").last ?? "")
            return (204, Data())
        }
        let saved = path.contains("favorite-playlists")
        let second = request.url?.query?.contains("offset=20") == true
        let empty = args.contains("-ui-testing-library-empty")
        let id = saved ? "netease:playlist:detail" : second ? "netease:track:second" : "netease:track:opaque%2Fp12"
        var track = MusicDiscoverPreviewFixtures.track
        track["id"] = id; if second { track["title"] = "第二页测试歌曲" }
        let row: [String: Any] = saved ? ["ownerId": "setu:user:1", "playlistId": id, "savedAt": "2026-09-06T00:00:00Z", "playlist": MusicDiscoverPreviewFixtures.playlist] :
            ["ownerId": "setu:user:1", "trackId": id, "likedAt": "2026-09-06T00:00:00Z", "track": track]
        let items = empty || removed.contains(id) ? [] : [row]
        let more = !saved && !second && !empty && !args.contains("-ui-testing-library-single")
        return (200, data(["items": items, "offset": second ? 20 : 0, "limit": 20,
            "hasMore": more, "total": empty ? 0 : more ? 2 : items.count,
            "nextOffset": more ? 20 : NSNull()]))
    }
    private static func data(_ value: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
}
#endif
