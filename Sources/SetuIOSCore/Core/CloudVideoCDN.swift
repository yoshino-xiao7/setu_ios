import Foundation

public enum CloudVideoCDN {
    public static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    public static func isImageCDN(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "b-cdn.net"
            || host.hasSuffix(".b-cdn.net")
            || host == "mediadelivery.net"
            || host.hasSuffix(".mediadelivery.net")
            || host == "bunnycdn.com"
            || host.hasSuffix(".bunnycdn.com")
    }

    /// Signed query tokens change on every catalog fetch; identity is the object path.
    public static func cacheIdentity(for url: URL) -> String {
        guard isImageCDN(url) else { return url.absoluteString }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        let host = (components?.host ?? url.host)?.lowercased() ?? ""
        var path = components?.path ?? url.path
        if let tokenRange = path.range(of: "/bcdn_token=") {
            let afterToken = path[tokenRange.lowerBound...]
            if let fileStart = afterToken.dropFirst().firstIndex(of: "/") {
                path = String(afterToken[fileStart...])
            }
        }
        return "bunny://\(host)\(path)"
    }

    public static func imageRequest(
        url: URL,
        cachePolicy: URLRequest.CachePolicy = .returnCacheDataElseLoad,
        siteBaseURL: URL = AppConfig.production.siteBaseURL
    ) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        request.setValue("image/avif,image/webp,image/apng,image/jpeg,image/png,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let headers = CloudVideoHLSPlaylist.playbackHeaders(siteBaseURL: siteBaseURL)
        request.setValue(headers["Origin"], forHTTPHeaderField: "Origin")
        request.setValue(headers["Referer"], forHTTPHeaderField: "Referer")
        return request
    }
}
