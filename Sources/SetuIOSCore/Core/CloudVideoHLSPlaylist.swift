import Foundation

public enum CloudVideoHLSPlaylist {
    public static func streamHeights(fromMaster playlist: String) -> [Int] {
        var heights: [Int] = []
        for line in playlist.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#EXT-X-STREAM-INF:"), !trimmed.hasPrefix("#EXT-X-I-FRAME-STREAM-INF:") else {
                continue
            }
            guard let height = resolutionHeight(in: trimmed) else { continue }
            heights.append(height)
        }
        return CloudVideoQuality.uniqueSortedHeights(heights)
    }

    public static let assetHeaderFieldsKey = "AVURLAssetHTTPHeaderFieldsKey"

    public static func playbackHeaders(siteBaseURL: URL) -> [String: String] {
        let origin = siteBaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return [
            "Accept": "application/vnd.apple.mpegurl,application/x-mpegURL,*/*",
            "Origin": origin,
            "Referer": origin + "/",
        ]
    }

    public static func assetOptions(siteBaseURL: URL) -> [String: Any] {
        [assetHeaderFieldsKey: playbackHeaders(siteBaseURL: siteBaseURL)]
    }

    private static func resolutionHeight(in streamInf: String) -> Int? {
        guard let marker = streamInf.range(of: "RESOLUTION=", options: .caseInsensitive) else {
            return nil
        }
        let rest = streamInf[marker.upperBound...]
        let token = rest.prefix { $0.isNumber || $0 == "x" || $0 == "X" }
        let parts = token.split(whereSeparator: { $0 == "x" || $0 == "X" })
        guard parts.count == 2, let height = Int(parts[1]), height > 0 else {
            return nil
        }
        return height
    }
}
