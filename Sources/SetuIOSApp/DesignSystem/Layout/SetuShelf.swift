import SwiftUI

enum SetuShelfWidth {
    case compact, regular, feature
    var points: CGFloat {
        switch self { case .compact: 132; case .regular: 168; case .feature: 240 }
    }
}

struct SetuShelf<Item: Identifiable, Card: View>: View {
    @Environment(\.setuBoardInset) private var boardInset
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let title: String
    private let subtitle: String?
    private let actionTitle: String?
    private let action: (() -> Void)?
    private let width: SetuShelfWidth
    private let items: [Item]
    private let card: (Item) -> Card

    init(title: String, subtitle: String? = nil,
         actionTitle: String? = nil, action: (() -> Void)? = nil,
         width: SetuShelfWidth = .regular, items: [Item],
         @ViewBuilder card: @escaping (Item) -> Card) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
        self.width = width
        self.items = items
        self.card = card
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.md) {
            SetuSectionHeader(title: title, subtitle: subtitle, actionTitle: actionTitle, action: action)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: SetuSpacing.md) {
                    ForEach(items) { item in
                        card(item).frame(width: width.points * (dynamicTypeSize.isAccessibilitySize ? 1.35 : 1))
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, SetuSpacing.xs)
            }
            .contentMargins(.horizontal, boardInset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .padding(.horizontal, -boardInset)
        }
    }
}

struct SetuShelfCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    var footnote: String?
    var footnoteImage: String?
    var imageURLString: String?
    var aspectRatio: CGFloat = 1
    var status: SetuRecordStatus?
    var accessibilityImageLabel: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                SetuRemoteImage(urlString: imageURLString, accessibilityLabel: accessibilityImageLabel ?? title,
                                width: nil, height: nil, contentMode: .fit, allowsTapToRetry: false)
                    .aspectRatio(SetuMosaicLayout.validAspectRatio(aspectRatio), contentMode: .fit)
                Text(title).font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if let footnote {
                    Label {
                        Text(footnote)
                    } icon: {
                        if let footnoteImage { Image(systemName: footnoteImage) }
                    }
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                }
                if let status { SetuPill(text: status.text, tone: status.tone) }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
