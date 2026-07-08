import SwiftUI

struct SetuImageTile<Badge: View>: View {
    let urlString: String?
    var aspectRatio: CGFloat = 1
    @ViewBuilder var badge: () -> Badge

    init(urlString: String?, aspectRatio: CGFloat = 1, @ViewBuilder badge: @escaping () -> Badge = { EmptyView() }) {
        self.urlString = urlString
        self.aspectRatio = aspectRatio
        self.badge = badge
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { proxy in
                ImageThumbnailView(
                    urlString: urlString,
                    width: proxy.size.width,
                    height: proxy.size.height
                )
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous)
                    .stroke(SetuColor.separator, lineWidth: 1)
            }

            badge()
                .padding(SetuSpacing.sm)
        }
    }
}
