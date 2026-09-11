import Foundation
import CoreGraphics

public enum JmReaderMode: String, CaseIterable, Identifiable, Sendable {
    case paged
    case continuous

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .paged: "翻页阅读"
        case .continuous: "连续滑动"
        }
    }

    public var systemImage: String {
        switch self {
        case .paged: "book"
        case .continuous: "scroll"
        }
    }
}

public enum JmReaderSettings {
    public static let storageKey = "icu.yukiryou.setu.jmReaderMode.v1"

    public static func mode(defaults: UserDefaults = .standard) -> JmReaderMode {
        JmReaderMode(rawValue: defaults.string(forKey: storageKey) ?? "") ?? .paged
    }

    public static func save(_ mode: JmReaderMode, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: storageKey)
    }
}

public enum JmVisiblePageResolver {
    public static func index(viewport: CGRect, frames: [Int: CGRect]) -> Int? {
        guard viewport.width > 1, viewport.height > 1 else { return nil }
        var bestIndex: Int?
        var bestArea: CGFloat = 0
        for (index, frame) in frames {
            let visible = viewport.intersection(frame)
            guard !visible.isNull, !visible.isEmpty else { continue }
            let area = visible.width * visible.height
            if area > bestArea + 0.5 || (abs(area - bestArea) <= 0.5 && index < (bestIndex ?? .max)) {
                bestIndex = index
                bestArea = area
            }
        }
        return bestIndex
    }
}
