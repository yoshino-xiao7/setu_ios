import SwiftUI

enum SetuBentoSpan {
    case small, wide, tall, hero

    var columnUnits: Int {
        switch self { case .small, .tall: 2; case .wide, .hero: 4 }
    }

    var rowUnits: Int {
        switch self { case .small, .wide: 1; case .tall, .hero: 2 }
    }
}

enum SetuBentoPacker {
    /// Sequential packing preserves the content and VoiceOver reading order.
    static func pack(columnUnits: [Int], columns: Int) -> [[Int]] {
        let capacity = max(1, columns)
        var rows: [[Int]] = []
        var row: [Int] = []
        var used = 0
        for (index, requested) in columnUnits.enumerated() {
            let units = min(capacity, max(1, requested))
            if used + units > capacity {
                rows.append(row)
                row = []
                used = 0
            }
            row.append(index)
            used += units
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }
}

struct SetuBento<Item: Identifiable, Tile: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.setuBoardInset) private var boardInset
    @ScaledMetric(relativeTo: .body) private var rowHeight = SetuLayoutMetrics.bentoRowHeight
    private let items: [Item]
    private let columns: Int
    private let spacing: CGFloat
    private let span: (Item) -> SetuBentoSpan
    private let tile: (Item) -> Tile

    init(items: [Item], columns: Int = SetuLayoutMetrics.bentoColumns,
         spacing: CGFloat = SetuSpacing.md,
         span: @escaping (Item) -> SetuBentoSpan,
         @ViewBuilder tile: @escaping (Item) -> Tile) {
        self.items = items
        self.columns = columns
        self.spacing = spacing
        self.span = span
        self.tile = tile
    }

    var body: some View {
        SetuBentoGridLayout(
            spans: items.map(span), columns: columns, spacing: spacing,
            rowHeight: rowHeight, forceSingleColumn: dynamicTypeSize.isAccessibilitySize,
            boardInset: boardInset
        ) {
            ForEach(items) { item in
                tile(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// Measures actual content, so AX text can grow beyond the nominal row height.
private struct SetuBentoGridLayout: Layout {
    let spans: [SetuBentoSpan]
    let columns: Int
    let spacing: CGFloat
    let rowHeight: CGFloat
    let forceSingleColumn: Bool
    let boardInset: CGFloat

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let capacity = max(1, columns)
        let single = forceSingleColumn || width + boardInset * 2 < 380
        let units = spans.map { single ? capacity : min(capacity, $0.columnUnits) }
        let rows = SetuBentoPacker.pack(columnUnits: units, columns: capacity)
        var result = Array(repeating: CGRect.zero, count: subviews.count)
        var y: CGFloat = 0
        for row in rows {
            let tileWidth = max(0, (width - CGFloat(row.count - 1) * spacing) / CGFloat(row.count))
            let height = row.map { index in
                let minimum = single ? rowHeight : rowHeight * CGFloat(spans[index].rowUnits)
                return max(minimum, subviews[index].sizeThatFits(.init(width: tileWidth, height: nil)).height)
            }.max() ?? 0
            for (position, index) in row.enumerated() {
                result[index] = CGRect(x: CGFloat(position) * (tileWidth + spacing), y: y, width: tileWidth, height: height)
            }
            y += height + spacing
        }
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 320
        let layout = frames(width: width, subviews: subviews)
        return CGSize(width: width, height: layout.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, frame) in frames(width: bounds.width, subviews: subviews).enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                  anchor: .topLeading, proposal: .init(frame.size))
        }
    }
}

enum SetuBentoTone { case surface, muted, brand }

struct SetuBentoTile: View {
    @ScaledMetric(relativeTo: .body) private var rowHeight = SetuLayoutMetrics.bentoRowHeight
    let title: String
    var value: String?
    var subtitle: String?
    var systemImage: String
    var tone: SetuBentoTone = .surface
    var status: SetuRecordStatus?
    var thumbnailURLString: String?
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) { surface }
                    .buttonStyle(SetuSurfaceButtonStyle())
            } else {
                surface
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var surface: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(SetuColor.brandSoft.opacity(0.22), in: RoundedRectangle(cornerRadius: SetuRadius.sm))
                .accessibilityHidden(true)
            Text(title).font(SetuTypography.headline)
            if let value { Text(value).font(SetuTypography.metric) }
            if let subtitle {
                Text(subtitle).font(SetuTypography.caption)
                    .foregroundStyle(tone == .brand ? .white : SetuColor.textSecondary)
            }
            if let status { SetuPill(text: status.text, tone: status.tone) }
            if let thumbnailURLString {
                SetuRemoteImage(urlString: thumbnailURLString, accessibilityLabel: title,
                                allowsTapToRetry: action == nil)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .topLeading)
        .padding(SetuSpacing.lg)
        .foregroundStyle(tone == .brand ? .white : SetuColor.textPrimary)
        .background {
            switch tone {
            case .brand: SetuColor.heroGradient
            case .muted: SetuColor.surfaceMuted
            case .surface: SetuColor.surface
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: SetuRadius.md))
        .overlay { RoundedRectangle(cornerRadius: SetuRadius.md).stroke(SetuColor.separator, lineWidth: 1) }
        .setuElevation(tone == .brand ? .hero : .card)
        .contentShape(RoundedRectangle(cornerRadius: SetuRadius.md))
    }
}
