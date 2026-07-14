import SwiftUI

struct SetuImageTile<Badge: View>: View {
    let urlString: String?
    let accessibilityLabel: String
    var aspectRatio: CGFloat = 1
    @ViewBuilder var badge: () -> Badge

    init(
        urlString: String?,
        accessibilityLabel: String,
        aspectRatio: CGFloat = 1,
        @ViewBuilder badge: @escaping () -> Badge = { EmptyView() }
    ) {
        self.urlString = urlString
        self.accessibilityLabel = accessibilityLabel
        self.aspectRatio = aspectRatio
        self.badge = badge
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { proxy in
                SetuRemoteImage(
                    urlString: urlString,
                    accessibilityLabel: accessibilityLabel,
                    width: proxy.size.width,
                    height: proxy.size.height,
                    cornerRadius: SetuRadius.md,
                    allowsTapToRetry: false
                )
            }
            .aspectRatio(aspectRatio, contentMode: .fit)

            badge()
                .padding(SetuSpacing.sm)
        }
    }
}
