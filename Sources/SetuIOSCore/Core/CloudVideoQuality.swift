import CoreGraphics
import Foundation

public enum CloudVideoQuality {
    public static let defaultMaxHeight = 720
    public static let storageKey = "icu.yukiryou.setu.cloudVideoMaxHeight.v1"

    public static func maxHeight(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.object(forKey: storageKey) as? Int
        if let stored, stored > 0 {
            return stored
        }
        return defaultMaxHeight
    }

    public static func saveMaxHeight(_ height: Int, defaults: UserDefaults = .standard) {
        guard height > 0 else { return }
        defaults.set(height, forKey: storageKey)
    }

    public static func uniqueSortedHeights(_ heights: [Int]) -> [Int] {
        Array(Set(heights.filter { $0 > 0 })).sorted()
    }

    /// Highest ladder rung that does not exceed the user's cap. If every rung is higher, keep the lowest.
    public static func capHeight(requested: Int, available: [Int]) -> Int {
        let heights = uniqueSortedHeights(available)
        let want = requested > 0 ? requested : defaultMaxHeight
        guard !heights.isEmpty else { return want }
        if let eligible = heights.last(where: { $0 <= want }) {
            return eligible
        }
        return heights[0]
    }

    public static func optionHeights(available: [Int]) -> [Int] {
        uniqueSortedHeights(available)
    }

    public static func label(for height: Int) -> String {
        height == defaultMaxHeight ? "\(height)p（默认）" : "\(height)p"
    }

    public static func maximumResolution(forMaxHeight height: Int) -> CGSize {
        let capped = CGFloat(max(height, 1))
        return CGSize(width: capped * 16 / 9, height: capped)
    }

    public static func peakBitRate(forMaxHeight height: Int) -> Double {
        switch max(height, 1) {
        case ...360:
            return 900_000
        case ...480:
            return 1_600_000
        case ...720:
            return 3_200_000
        case ...1080:
            return 5_800_000
        case ...1440:
            return 9_000_000
        default:
            return 18_000_000
        }
    }

    public struct PlaybackConstraints: Equatable, Sendable {
        public let height: Int
        public let maximumResolution: CGSize
        public let peakBitRate: Double
    }

    public static func playbackConstraints(requested: Int, available: [Int]) -> PlaybackConstraints {
        let height = capHeight(requested: requested, available: available)
        return PlaybackConstraints(
            height: height,
            maximumResolution: maximumResolution(forMaxHeight: height),
            peakBitRate: peakBitRate(forMaxHeight: height)
        )
    }
}
