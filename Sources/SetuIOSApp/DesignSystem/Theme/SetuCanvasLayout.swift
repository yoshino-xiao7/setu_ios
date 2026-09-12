import CoreGraphics
import Foundation

/// Window/container canvas for iPhone and iPad, including split view and rotation.
/// Views read this instead of hard-coding 2-column phone layouts.
struct SetuCanvasLayout: Equatable, Sendable {
    var size: CGSize

    var isLandscape: Bool {
        size.width > size.height + 8
    }

    var isRegularWidth: Bool {
        size.width >= 700
    }

    var usesTwoPane: Bool {
        isRegularWidth && isLandscape && size.width >= 1000
    }

    var pageGutter: CGFloat {
        isRegularWidth ? 24 : 16
    }

    var readableMaxWidth: CGFloat {
        guard size.width >= 700 else { return .infinity }
        if usesTwoPane { return .infinity }
        return min(max(size.width - pageGutter * 2, 0), 760)
    }

    var masonryColumnCount: Int {
        switch size.width {
        case ..<500: 2
        case ..<900: 3
        case ..<1200: 4
        default: 5
        }
    }

    var dashboardColumnCount: Int {
        usesTwoPane ? 2 : 1
    }

    var hubColumnCount: Int {
        usesTwoPane ? 2 : 1
    }

    var musicShortcutColumns: Int {
        if usesTwoPane { return 6 }
        return isRegularWidth ? 4 : 4
    }

    var tileMinimum: CGFloat {
        isRegularWidth ? 180 : 148
    }

    var spotlightCardWidth: CGFloat {
        isRegularWidth ? 360 : 280
    }

    var favoriteTileSide: CGFloat {
        isRegularWidth ? 168 : 136
    }

    var miniPlayerMaxWidth: CGFloat {
        guard isRegularWidth else { return .infinity }
        return min(560, max(size.width - 48, 320))
    }

    var artworkMaxSide: CGFloat {
        usesTwoPane ? 420 : 360
    }
}

enum SetuMasonryLayout {
    static func columns<Item>(from items: [Item], count: Int, height: (Item) -> Double) -> [[Item]] {
        let count = max(1, count)
        var columns = Array(repeating: [Item](), count: count)
        var heights = Array(repeating: 0.0, count: count)
        for item in items {
            let index = heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            columns[index].append(item)
            heights[index] += height(item)
        }
        return columns
    }
}
