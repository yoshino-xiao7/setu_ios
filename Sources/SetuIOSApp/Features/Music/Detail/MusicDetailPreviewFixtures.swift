#if DEBUG
import Foundation

/// In-process fixtures only; never changes AppConfig.resolved or persisted feature flags.
enum MusicDetailPreviewFixtures {
    static func response(path: String, query: String?) -> (Int, Data) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-ui-testing-detail-error") {
            return (503, Data(#"{"code":"UPSTREAM_UNAVAILABLE","message":"详情服务暂时不可用","retryable":true,"traceId":null}"#.utf8))
        }
        if path.hasSuffix("/playback") {
            let id = path.split(separator: "/").dropLast().last.map(String.init) ?? "netease:track:detail"
            return (200, Data("{\"kind\":\"denied\",\"trackId\":\"\(id)\",\"availability\":{\"status\":\"unavailable\",\"reason\":\"测试音源不可播放\",\"maxQuality\":null}}".utf8))
        }
        let empty = args.contains("-ui-testing-detail-empty")
        let artist = #"{"name":"详情测试歌手","id":"netease:artist:detail","artwork":null}"#
        let album = #"{"title":"详情测试专辑","id":"netease:album:detail","artwork":null}"#
        let track = "{\"id\":\"netease:track:opaque%2Fdetail\",\"source\":\"netease\",\"title\":\"详情测试歌曲\",\"artists\":[\(artist)],\"availability\":{\"status\":\"unknown\",\"reason\":null,\"maxQuality\":null},\"album\":\(album),\"durationMs\":null,\"artwork\":null,\"mvId\":null,\"aliases\":[],\"translatedTitle\":null}"
        let body: String
        if path.contains("/artists/") {
            let metadata = #"{"id":"netease:artist:detail","source":"netease","name":"详情测试歌手","aliases":[],"artwork":null,"description":"歌手简介","trackCount":1,"albumCount":1,"mvCount":0}"#
            body = "{\"artist\":\(metadata),\"topTracks\":[\(empty ? "" : track)],\"albums\":[\(album)],\"mvs\":[],\"similar\":[]}"
        } else if path.contains("/albums/") {
            let metadata = "{\"id\":\"netease:album:detail\",\"source\":\"netease\",\"title\":\"详情测试专辑\",\"artists\":[\(artist)],\"artwork\":null,\"releaseDate\":null,\"trackCount\":1,\"company\":null,\"description\":\"专辑简介\",\"editionLabel\":null}"
            body = "{\"album\":\(metadata),\"tracks\":[\(empty ? "" : track)]}"
        } else {
            let more = path.hasSuffix("/tracks")
            let id = "netease:playlist:detail"
            let member = "{\"playlistId\":\"\(id)\",\"trackId\":\"netease:track:opaque%2Fdetail\",\"position\":\(more ? 50 : 0),\"track\":\(more ? "null" : track),\"relationId\":null,\"addedAt\":null}"
            let page = "{\"items\":[\(empty ? "" : member)],\"offset\":\(more ? 50 : 0),\"limit\":50,\"hasMore\":\(!more && !empty),\"total\":null,\"nextOffset\":\(!more && !empty ? "50" : "null")}"
            let playlist = "{\"id\":\"\(id)\",\"origin\":\"provider\",\"title\":\"详情测试歌单\",\"tags\":[],\"isRanking\":false,\"artwork\":null,\"description\":\"歌单简介\",\"trackCount\":null,\"playCount\":null,\"creator\":null,\"updatedAt\":null,\"updateFrequency\":null}"
            body = more ? page : "{\"playlist\":\(playlist),\"memberships\":\(page)}"
        }
        return (200, Data(body.utf8))
    }
}
#endif
