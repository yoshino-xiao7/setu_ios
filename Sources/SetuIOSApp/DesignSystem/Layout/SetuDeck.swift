import SwiftUI

/// A focused visual surface. Paging and actions stay owned by the feature.
struct SetuDeck<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .background(SetuColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: SetuRadius.lg))
            .overlay { RoundedRectangle(cornerRadius: SetuRadius.lg).stroke(SetuColor.separator, lineWidth: 1) }
            .setuElevation(.hero)
    }
}

struct SetuSkeletonTile: View {
    var aspectRatio: CGFloat = 1.5
    var title = "正在加载内容"

    var body: some View {
        SetuSkeleton(cornerRadius: SetuRadius.md)
            .aspectRatio(SetuMosaicLayout.validAspectRatio(aspectRatio), contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
    }
}
