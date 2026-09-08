import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct ImagePidDisplay: Equatable, Sendable {
    public let pid: Int
    public let page: Int

    public init(pid: Int, page: Int) {
        self.pid = pid
        self.page = page
    }

    public var text: String {
        page == 0 ? "\(pid)" : "\(pid)_p\(page)"
    }

    public var title: String { "PID \(text)" }

    public var fieldLabel: String { "插画 ID" }

    public var copyText: String { text }

    public var accessibilityLabel: String { "\(fieldLabel) \(text)，轻点复制" }
}

public enum ImageFeedBrowsePolicy {
    public static func imageHeight(
        containerWidth: CGFloat,
        pixelWidth: Int,
        pixelHeight: Int,
        maxHeight: CGFloat
    ) -> CGFloat {
        let width = max(containerWidth, 1)
        let hasSize = pixelWidth > 0 && pixelHeight > 0
        let pw = hasSize ? CGFloat(pixelWidth) : 3
        let ph = hasSize ? CGFloat(pixelHeight) : 4
        let fitted = width * (ph / pw)
        let ceiling = max(maxHeight, 180)
        return min(max(fitted, 180), ceiling)
    }

    public static func nextIndex(after index: Int, expired: [Bool]) -> Int? {
        guard !expired.isEmpty else { return nil }
        let start = min(max(index + 1, 0), expired.count)
        return expired[start...].firstIndex(of: false)
    }
}
