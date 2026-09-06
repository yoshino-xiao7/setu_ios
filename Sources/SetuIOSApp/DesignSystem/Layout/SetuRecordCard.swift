import SwiftUI

struct SetuRecordStatus: Equatable {
    let text: String
    let tone: SetuPillTone

    init(_ text: String, tone: SetuPillTone = .brand) {
        self.text = text
        self.tone = tone
    }
}

struct SetuRecordField: Equatable {
    let name: String
    let value: String
    let isNumeric: Bool

    init(_ name: String, _ value: String, isNumeric: Bool = true) {
        self.name = name
        self.value = value
        self.isNumeric = isNumeric
    }
}

enum SetuRecordDensity { case regular, compact }

struct SetuRecordCard<Actions: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let headline: String
    var supporting: String?
    var status: SetuRecordStatus?
    var thumbnailURLString: String?
    var fields: [SetuRecordField] = []
    var density: SetuRecordDensity = .regular
    var onTap: (() -> Void)?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(status?.tone.foreground ?? SetuColor.brandPink)
                .frame(width: SetuLayoutMetrics.recordRibbonWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: gap) {
                Group {
                    if let onTap {
                        Button(action: onTap) { summary }
                            .buttonStyle(.plain)
                    } else { summary }
                }
                .accessibilityElement(children: .combine)
                if Actions.self != EmptyView.self {
                    Divider().overlay(SetuColor.separator)
                    actions()
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
            .padding(density == .compact ? SetuSpacing.md : SetuSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(SetuColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: SetuRadius.md))
        .overlay { RoundedRectangle(cornerRadius: SetuRadius.md).stroke(SetuColor.separator, lineWidth: 1) }
        .setuElevation(.card)
        .accessibilityElement(children: Actions.self == EmptyView.self ? .combine : .contain)
    }

    private var gap: CGFloat { density == .compact ? SetuSpacing.sm : SetuSpacing.md }

    private var summary: some View {
        VStack(alignment: .leading, spacing: gap) {
            if let thumbnailURLString {
                SetuRemoteImage(urlString: thumbnailURLString, accessibilityLabel: headline,
                                allowsTapToRetry: onTap == nil)
            }
            Text(headline)
                .font(SetuTypography.headline)
                .foregroundStyle(SetuColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let status { SetuPill(text: status.text, tone: status.tone) }
            if let supporting {
                Text(supporting).font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            fieldGrid
        }
        .frame(maxWidth: .infinity, minHeight: onTap == nil ? 0 : 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var fieldGrid: some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Grid(alignment: .topLeading, horizontalSpacing: SetuSpacing.lg, verticalSpacing: gap) {
            ForEach(Array(stride(from: 0, to: fields.count, by: columns)), id: \.self) { start in
                GridRow(alignment: .top) {
                    ForEach(start..<min(start + columns, fields.count), id: \.self) { index in
                        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                            Text(fields[index].name)
                                .font(SetuTypography.label)
                                .foregroundStyle(SetuColor.textTertiary)
                            Text(fields[index].value)
                                .font(fields[index].isNumeric ? SetuTypography.numeric : SetuTypography.body)
                                .foregroundStyle(SetuColor.textPrimary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

extension SetuRecordCard where Actions == EmptyView {
    init(headline: String, supporting: String? = nil, status: SetuRecordStatus? = nil,
         thumbnailURLString: String? = nil, fields: [SetuRecordField] = [],
         density: SetuRecordDensity = .regular, onTap: (() -> Void)? = nil) {
        self.headline = headline
        self.supporting = supporting
        self.status = status
        self.thumbnailURLString = thumbnailURLString
        self.fields = fields
        self.density = density
        self.onTap = onTap
        self.actions = { EmptyView() }
    }
}

struct SetuRecordBoard<Item: Identifiable, Card: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let items: [Item]
    private let minimumCardWidth: CGFloat
    private let spacing: CGFloat
    private let card: (Item) -> Card

    init(items: [Item], minimumCardWidth: CGFloat = SetuLayoutMetrics.recordCardMinWidth,
         spacing: CGFloat = SetuSpacing.md, @ViewBuilder card: @escaping (Item) -> Card) {
        self.items = items
        self.minimumCardWidth = minimumCardWidth
        self.spacing = spacing
        self.card = card
    }

    var body: some View {
        LazyVGrid(columns: [dynamicTypeSize.isAccessibilitySize
            ? GridItem(.flexible(), alignment: .top)
            : GridItem(.adaptive(minimum: minimumCardWidth), spacing: spacing, alignment: .top)], spacing: spacing) {
            ForEach(items, content: card)
        }
    }
}
