import Foundation

public enum HanimeSite {
    public static let origin = "https://hanime1.me"
    public static let referer = "https://hanime1.me/"
    public static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    public static let assetHeaderFieldsKey = "AVURLAssetHTTPHeaderFieldsKey"

    public static let pageHeaders: [String: String] = [
        "User-Agent": userAgent,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "zh-TW,zh-CN;q=0.9,zh;q=0.8,en;q=0.7",
        "Origin": origin,
        "Referer": referer,
    ]

    public static let mediaHeaders: [String: String] = [
        "User-Agent": userAgent,
        "Accept": "*/*",
        "Referer": referer,
    ]

    public static func isImageCDN(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "hanime1.me"
            || host.hasSuffix(".hanime1.me")
            || host == "hembed.com"
            || host.hasSuffix(".hembed.com")
    }

    public static func applyPageHeaders(to request: inout URLRequest) {
        for (key, value) in pageHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    public static func imageRequest(
        url: URL,
        cachePolicy: URLRequest.CachePolicy = .returnCacheDataElseLoad
    ) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        return request
    }

    public static var playbackAssetOptions: [String: Any] {
        [assetHeaderFieldsKey: mediaHeaders]
    }
}

public struct HanimeCatalogClient: Sendable {
    public static let defaultBaseURLs = [
        URL(string: "https://hanime1.me")!,
    ]

    private let session: URLSession
    private let baseURLs: [URL]
    private let now: @Sendable () -> Date

    public init(
        session: URLSession = .shared,
        baseURLs: [URL] = HanimeCatalogClient.defaultBaseURLs,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.session = session
        self.baseURLs = baseURLs
        self.now = now
    }

    public func works(page: Int = 1, keyword: String? = nil, genre: HanimeGenre = .latest) async throws -> HanimeWorkPage {
        let safePage = max(page, 1)
        let trimmed = keyword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let html: String
        let allowsPagination: Bool
        if genre.kind == .previews, trimmed.isEmpty {
            if safePage > 1 {
                return HanimeWorkPage(page: safePage, total: 0, hasMore: false, works: [])
            }
            html = try await previewHTML()
            allowsPagination = false
        } else {
            html = try await getHTML("/search", query: searchQuery(page: safePage, keyword: trimmed, genre: genre))
            allowsPagination = true
        }
        let parsed = HanimeHTML.works(from: html, page: safePage, allowsPagination: allowsPagination)
        if parsed.works.isEmpty, HanimeHTML.looksBlocked(html) {
            throw APIError.invalidResponse
        }
        return parsed
    }

    public func work(id: String) async throws -> HanimeWatchPage {
        let encoded = try encodedID(id)
        do {
            let page = try await fetchWatch(encoded)
            if !page.streams.isEmpty { return page }
            return try await fetchWatch(encoded)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fetchWatch(encoded)
        }
    }

    private func fetchWatch(_ encoded: String) async throws -> HanimeWatchPage {
        let watchHTML = try await getHTML("/watch", query: [URLQueryItem(name: "v", value: encoded)])
        var parsed = HanimeHTML.watch(from: watchHTML, id: encoded)
        do {
            let downloadHTML = try await getHTML("/download", query: [URLQueryItem(name: "v", value: encoded)])
            parsed = HanimeHTML.combining(parsed, downloadHTML: downloadHTML)
        } catch {
            if parsed.streams.isEmpty { throw error }
        }
        if parsed.work.title.isEmpty, parsed.streams.isEmpty, HanimeHTML.looksBlocked(watchHTML) {
            throw APIError.invalidResponse
        }
        return parsed
    }

    private func searchQuery(page: Int, keyword: String, genre: HanimeGenre) -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        if !keyword.isEmpty {
            items.append(URLQueryItem(name: "query", value: keyword))
        }
        if genre.kind == .search, let value = genre.query, !value.isEmpty {
            items.append(URLQueryItem(name: "genre", value: value))
        }
        items.append(URLQueryItem(name: "page", value: String(page)))
        return items
    }

    private func previewHTML() async throws -> String {
        for path in previewCandidatePaths() {
            guard let html = try? await getHTML(path) else { continue }
            if !HanimeHTML.works(from: html, page: 1, allowsPagination: false).works.isEmpty {
                return html
            }
        }
        if let home = try? await getHTML("/"), let month = HanimeHTML.previewMonth(in: home) {
            return try await getHTML("/previews/\(month)")
        }
        throw APIError.invalidResponse
    }

    private func previewCandidatePaths() -> [String] {
        let calendar = Calendar(identifier: .gregorian)
        let date = now()
        return (0..<6).compactMap { offset in
            guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: date) else { return nil }
            let year = calendar.component(.year, from: monthDate)
            let month = calendar.component(.month, from: monthDate)
            return String(format: "/previews/%04d%02d", year, month)
        }
    }

    private func encodedID(_ value: String) throws -> String {
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id != ".", id != "..", !id.contains("/"), !id.contains("\\") else {
            throw APIError.invalidURL("作品标识无效")
        }
        return id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
    }

    private func getHTML(_ path: String, query: [URLQueryItem] = []) async throws -> String {
        var lastError: Error = APIError.invalidResponse
        for base in baseURLs {
            do {
                return try await getHTML(path, query: query, base: base)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func getHTML(_ path: String, query: [URLQueryItem], base: URL) async throws -> String {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL(path)
        }
        components.path = path.hasPrefix("/") ? path : "/" + path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL(path) }
        var request = URLRequest(url: url)
        HanimeSite.applyPageHeaders(to: &request)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }
}

enum HanimeHTML {
    static func works(from html: String, page: Int, allowsPagination: Bool = true) -> HanimeWorkPage {
        var seen = Set<String>()
        var works: [HanimeWork] = []

        let anchors = matches(
            #"<a\b[^>]*href=["'](?:https?://hanime1\.me)?/watch\?v=(\d+)[^"']*["'][^>]*>([\s\S]*?)</a>"#,
            in: html
        )
        for match in anchors {
            let id = match[1]
            if seen.contains(id) { continue }
            let work = workCard(id: id, inner: match[2], tag: match[0])
            guard hasCatalogSignal(work) else { continue }
            seen.insert(id)
            works.append(work)
        }

        let idMatches = matches(#"watch\?v=(\d+)"#, in: html)
        for match in idMatches {
            let id = match[1]
            if seen.contains(id) { continue }
            guard let start = Range(match.range, in: html)?.lowerBound else { continue }
            let windowEnd = html.index(start, offsetBy: 1200, limitedBy: html.endIndex) ?? html.endIndex
            let window = String(html[start..<windowEnd])
            let work = workCard(id: id, inner: window, tag: match[0])
            guard hasCatalogSignal(work) else { continue }
            seen.insert(id)
            works.append(work)
        }

        let parsedTotal = catalogTotal(in: html)
        let lastPage = maxPage(in: html)
        let pageSize = max(works.count, 1)
        let counted = (page - 1) * pageSize + works.count
        let hasMore: Bool
        if works.isEmpty || !allowsPagination {
            hasMore = false
        } else if let lastPage, page >= lastPage {
            hasMore = false
        } else if let parsedTotal {
            hasMore = counted < parsedTotal
        } else if let lastPage {
            hasMore = page < lastPage
        } else {
            hasMore = works.count >= 20
        }
        let total: Int
        if let parsedTotal {
            total = parsedTotal
        } else if hasMore, let lastPage {
            total = max(lastPage * pageSize, page * pageSize + 1)
        } else if hasMore {
            total = page * pageSize + 1
        } else {
            total = counted
        }
        return HanimeWorkPage(page: page, total: total, hasMore: hasMore, works: works)
    }

    static func previewMonth(in html: String) -> String? {
        matches(#"/previews/(\d{6})"#, in: html).first?[1]
    }

    static func watch(from html: String, id: String) -> HanimeWatchPage {
        let title = firstNonEmpty([
            meta(html, property: "og:title"),
            tagText(html, name: "h4"),
            tagText(html, name: "title"),
        ]).map(decode) ?? "未命名作品"
        let cover = firstNonEmpty([
            meta(html, property: "og:image"),
            firstImage(in: html),
        ])
        let summary = meta(html, property: "og:description").map(decode)
        let work = HanimeWork(
            id: id,
            title: title,
            coverURL: cover,
            subtitle: summary ?? "",
            summary: summary
        )
        let related = relatedWorks(in: html).filter { $0.id != id }
        return HanimeWatchPage(work: work, streams: streams(in: html), related: related)
    }

    static func downloadStreams(from html: String) -> [HanimeStream] {
        var found: [HanimeStream] = []
        for match in matches(#"data-url=["'](https?://[^"']+)["']"#, in: html) {
            if let stream = stream(fromURL: match[1], type: nil, size: nearbyQuality(around: match.range, in: html)) {
                found.append(stream)
            }
        }
        for match in matches(#"<a\b[^>]*href=["'](https?://[^"']+)["'][^>]*>"#, in: html) {
            if let stream = stream(fromURL: match[1], type: nil, size: nearbyQuality(around: match.range, in: html)) {
                found.append(stream)
            }
        }
        return uniqueStreams(found)
    }

    static func combining(_ page: HanimeWatchPage, downloadHTML: String) -> HanimeWatchPage {
        let downloaded = downloadStreams(from: downloadHTML)
        guard !downloaded.isEmpty else { return page }
        return HanimeWatchPage(
            work: page.work,
            streams: uniqueStreams(page.streams + downloaded),
            related: page.related
        )
    }

    static func looksBlocked(_ html: String) -> Bool {
        let lowered = html.lowercased()
        return lowered.contains("just a moment")
            || lowered.contains("cf-browser-verification")
            || lowered.contains("attention required")
    }

    private static func relatedWorks(in html: String) -> [HanimeWork] {
        guard let playlist = slice(html, startingAt: "id=\"video-playlist-wrapper\"", until: "id=\"footer")
                ?? slice(html, startingAt: "id='video-playlist-wrapper'", until: "id='footer") else {
            return []
        }
        return works(from: playlist, page: 1, allowsPagination: false).works
    }

    private static func streams(in html: String) -> [HanimeStream] {
        var found: [HanimeStream] = []
        for tag in matches(#"<source\b[^>]*>"#, in: html).map({ $0[0] }) {
            let src = firstNonEmpty([attribute("src", in: tag), attribute("data-src", in: tag)])
            if let stream = stream(fromURL: src, type: attribute("type", in: tag), size: attribute("size", in: tag)) {
                found.append(stream)
            }
        }
        if let contentURL = jsonString("contentUrl", in: html) {
            if let stream = stream(fromURL: contentURL, type: nil, size: nil) {
                found.append(stream)
            }
        }
        found.append(contentsOf: javascriptSourceStreams(in: html))
        found.append(contentsOf: looseMediaURLStreams(in: html))
        return uniqueStreams(found)
    }

    private static func javascriptSourceStreams(in html: String) -> [HanimeStream] {
        let patterns = [
            #"(?:const|let|var)\s+source\s*=\s*['"]([^'"]+)['"]"#,
            #"\bsource\s*:\s*['"]([^'"]+)['"]"#,
        ]
        var found: [HanimeStream] = []
        for pattern in patterns {
            for match in matches(pattern, in: html) {
                if let stream = stream(fromURL: match[1], type: nil, size: nil) {
                    found.append(stream)
                }
            }
        }
        return found
    }

    private static func looseMediaURLStreams(in html: String) -> [HanimeStream] {
        let m3u8Matches = matches(#"https?://[^\s"'<>]+\.m3u8(?:\?[^\s"'<>]*)?"#, in: html)
        let m3u8URLs = m3u8Matches.map { $0[0] }
        var found = m3u8Matches.compactMap { stream(fromURL: $0[0], type: nil, size: nil) }
        for match in matches(#"https?://[^\s"'<>]+\.mp4(?:\?[^\s"'<>]*)?"#, in: html) {
            let raw = match[0]
            if m3u8URLs.contains(where: { $0.hasPrefix(raw) }) { continue }
            if let stream = stream(fromURL: raw, type: nil, size: nil) {
                found.append(stream)
            }
        }
        return found
    }

    private static func stream(fromURL raw: String?, type: String?, size: String?) -> HanimeStream? {
        guard let raw, let url = mediaURL(from: raw), isPlayableMediaURL(url) else {
            return nil
        }
        let loweredType = (type ?? "").lowercased()
        let isHLS = loweredType.contains("mpegurl") || url.pathExtension.lowercased() == "m3u8" || url.absoluteString.lowercased().contains(".m3u8")
        let quality: String
        if let size, let value = Int(size.filter(\.isNumber)), value > 0 {
            quality = "\(value)p"
        } else if let match = matches(#"(\d{3,4})p"#, in: url.absoluteString).first {
            quality = "\(match[1])p"
        } else if !isHLS, let match = matches(#"-(360|480|720|1080)-"#, in: url.absoluteString).first {
            quality = "\(match[1])p"
        } else {
            quality = isHLS ? "HLS" : "MP4"
        }
        return HanimeStream(quality: quality, url: url, isHLS: isHLS)
    }

    private static func mediaURL(from raw: String) -> URL? {
        let decoded = decode(raw).replacingOccurrences(of: "\\/", with: "/")
        let absolute: String
        if decoded.hasPrefix("//") {
            absolute = "https:" + decoded
        } else if decoded.hasPrefix("/") {
            absolute = HanimeSite.origin + decoded
        } else {
            absolute = decoded
        }
        guard let url = URL(string: absolute), url.scheme == "http" || url.scheme == "https" else {
            return nil
        }
        return url
    }

    private static func isPlayableMediaURL(_ url: URL) -> Bool {
        let absolute = url.absoluteString.lowercased()
        let path = url.path.lowercased()
        if absolute.hasPrefix("blob:") { return false }
        let isM3U8 = path.hasSuffix(".m3u8")
        if isM3U8 { return true }
        if path.contains("/_hls/") { return false }
        return path.hasSuffix(".mp4")
    }

    private static func nearbyQuality(around range: NSRange, in html: String) -> String? {
        guard let swiftRange = Range(range, in: html) else { return nil }
        let end = html.index(swiftRange.upperBound, offsetBy: 400, limitedBy: html.endIndex) ?? html.endIndex
        let window = String(html[swiftRange.upperBound..<end])
        if let match = matches(#"\((\d{3,4})p\)"#, in: window).first {
            return match[1]
        }
        if let match = matches(#">\s*(\d{3,4})p\s*<"#, in: window).first {
            return match[1]
        }
        return nil
    }

    private static func uniqueStreams(_ streams: [HanimeStream]) -> [HanimeStream] {
        let playable = streams.filter { isPlayableMediaURL($0.url) }
        var seen = Set<String>()
        return playable.filter { seen.insert($0.id).inserted }.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
            if lhs.isHLS != rhs.isHLS { return !lhs.isHLS && rhs.isHLS }
            return lhs.id < rhs.id
        }
    }

    private static func workCard(id: String, inner: String, tag: String) -> HanimeWork {
        let title = firstNonEmpty([
            classText(inner, containing: "title"),
            classText(inner, containing: "name"),
            attribute("alt", in: inner),
            attribute("title", in: tag),
            attribute("title", in: inner),
        ]).map(decode) ?? "未命名作品"
        return HanimeWork(id: id, title: title, coverURL: firstImage(in: inner), subtitle: "")
    }

    private static func hasCatalogSignal(_ work: HanimeWork) -> Bool {
        work.coverURL != nil || work.title != "未命名作品"
    }

    private static func firstImage(in html: String) -> String? {
        let images = matches(#"<img\b[^>]*>"#, in: html)
        for tag in images.map({ $0[0] }) {
            let candidate = firstNonEmpty([
                attribute("data-src", in: tag),
                attribute("data-original", in: tag),
                attribute("src", in: tag),
            ])
            guard let candidate, let url = URL(string: decode(candidate)) else { continue }
            let lowered = candidate.lowercased()
            if lowered.contains(".gif") || lowered.contains("icon") || lowered.contains("avatar") || lowered.contains("logo") {
                continue
            }
            if url.scheme == "http" || url.scheme == "https" {
                return url.absoluteString
            }
        }
        return nil
    }

    private static func catalogTotal(in html: String) -> Int? {
        let patterns = [
            #"共\s*([\d,，]+)\s*部"#,
            #"([\d,，]+)\s*部作品"#,
        ]
        for pattern in patterns {
            if let raw = matches(pattern, in: html).first?[1] {
                let digits = raw.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "，", with: "")
                if let value = Int(digits), value > 0 { return value }
            }
        }
        return nil
    }

    private static func maxPage(in html: String) -> Int? {
        let nav = slice(html, startingAt: "pagination", until: "</ul>")
            ?? slice(html, startingAt: "class=\"paginate", until: "</div>")
        return pageNumbers(in: nav ?? "") ?? pageNumbers(in: html)
    }

    private static func pageNumbers(in html: String) -> Int? {
        matches(#"[?&]page=(\d+)"#, in: html)
            .compactMap { Int($0[1]) }
            .filter { $0 > 0 && $0 < 10_000 }
            .max()
    }

    private static func meta(_ html: String, property: String) -> String? {
        let quoted = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            #"<meta\b[^>]*property=["']\#(quoted)["'][^>]*content=["']([^"']+)["'][^>]*>"#,
            #"<meta\b[^>]*content=["']([^"']+)["'][^>]*property=["']\#(quoted)["'][^>]*>"#,
            #"<meta\b[^>]*name=["']\#(quoted)["'][^>]*content=["']([^"']+)["'][^>]*>"#,
        ]
        for pattern in patterns {
            if let value = matches(pattern, in: html).first?[1] {
                return value
            }
        }
        return nil
    }

    private static func tagText(_ html: String, name: String) -> String? {
        matches("<\(name)\\b[^>]*>([\\s\\S]*?)</\(name)>", in: html)
            .map { stripTags($0[1]) }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func classText(_ html: String, containing token: String) -> String? {
        matches(#"class=["'][^"']*\#(token)[^"']*["'][^>]*>([^<]+)"#, in: html)
            .map { $0[1].trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let quoted = NSRegularExpression.escapedPattern(for: name)
        return matches(#"\#(quoted)\s*=\s*["']([^"']+)["']"#, in: tag).first?[1]
    }

    private static func jsonString(_ key: String, in html: String) -> String? {
        let quoted = NSRegularExpression.escapedPattern(for: key)
        return matches(#""\#(quoted)"\s*:\s*"([^"]+)""#, in: html).first?[1]
    }

    private static func slice(_ html: String, startingAt marker: String, until endMarker: String) -> String? {
        guard let start = html.range(of: marker, options: .caseInsensitive) else { return nil }
        let rest = html[start.upperBound...]
        if let end = rest.range(of: endMarker, options: .caseInsensitive) {
            return String(html[start.lowerBound..<end.lowerBound])
        }
        return String(html[start.lowerBound...])
    }

    private static func stripTags(_ value: String) -> String {
        decode(value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    static func decode(_ value: String) -> String {
        var text = value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        let entities = matches(#"&#(\d+);"#, in: text)
        for entity in entities.reversed() {
            if let code = Int(entity[1]), let scalar = UnicodeScalar(code) {
                text = text.replacingOccurrences(of: entity[0], with: String(Character(scalar)))
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Match {
        let range: NSRange
        let groups: [String]
        subscript(index: Int) -> String { groups[index] }
    }

    private static func matches(_ pattern: String, in text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let full = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: full).compactMap { result in
            var groups: [String] = []
            for index in 0..<result.numberOfRanges {
                let range = result.range(at: index)
                guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else {
                    groups.append("")
                    continue
                }
                groups.append(String(text[swiftRange]))
            }
            return Match(range: result.range, groups: groups)
        }
    }
}
