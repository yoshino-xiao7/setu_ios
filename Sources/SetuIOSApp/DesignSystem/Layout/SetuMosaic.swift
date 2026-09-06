import SwiftUI

enum SetuMosaicLayout {
    static func distribute(aspectRatios: [CGFloat], columns: Int) -> [[Int]] {
        guard columns > 0 else { return [] }
        var result = Array(repeating: [Int](), count: columns)
        var heights = Array(repeating: CGFloat.zero, count: columns)
        for (index, ratio) in aspectRatios.enumerated() {
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            result[column].append(index)
            heights[column] += 1 / validAspectRatio(ratio)
        }
        return result
    }

    static func validAspectRatio(_ ratio: CGFloat) -> CGFloat {
        guard ratio.isFinite, ratio > 0, (1 / ratio).isFinite else { return 1 }
        return ratio
    }
}

struct SetuMosaic<Item: Identifiable, Tile: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    private let items: [Item]
    private let columns: Int
    private let spacing: CGFloat
    private let aspectRatio: (Item) -> CGFloat
    private let tile: (Item) -> Tile

    init(items: [Item], columns: Int = 2, spacing: CGFloat = SetuSpacing.md,
         aspectRatio: @escaping (Item) -> CGFloat,
         @ViewBuilder tile: @escaping (Item) -> Tile) {
        self.items = items
        self.columns = columns
        self.spacing = spacing
        self.aspectRatio = aspectRatio
        self.tile = tile
    }

    var body: some View {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : (sizeClass == .regular && columns == 2 ? 3 : columns)
        let distribution = SetuMosaicLayout.distribute(aspectRatios: items.map(aspectRatio), columns: count)
        HStack(alignment: .top, spacing: spacing) {
            ForEach(distribution.indices, id: \.self) { column in
                LazyVStack(spacing: spacing) {
                    ForEach(distribution[column].map { SetuMosaicEntry(item: items[$0], index: $0) }) { entry in
                        tile(entry.item)
                            .frame(maxWidth: .infinity)
                            .accessibilitySortPriority(-Double(entry.index))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
}

private struct SetuMosaicEntry<Item: Identifiable>: Identifiable {
    let item: Item
    let index: Int
    var id: Item.ID { item.id }
}
