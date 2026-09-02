import Foundation

/// Expiry only refreshes free previews. A replacement token needs fresh user consent.
public enum ImageFeedExpiryPolicy {
    public static func expirationDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    public static func prefetchDelay(for expiry: Date?, now: Date = Date()) -> TimeInterval? {
        expiry.map { max(0, $0.timeIntervalSince(now) - 60) }
    }

    public static func isExpired(_ expiry: Date?, now: Date = Date()) -> Bool {
        guard let expiry else { return false }
        return now >= expiry
    }

    public static func shouldReloadPreview(after error: Error) -> Bool {
        guard case APIError.httpStatus(404, _, _, _, "IMAGE_FEED_TOKEN_EXPIRED") = error else {
            return false
        }
        return true
    }
}
