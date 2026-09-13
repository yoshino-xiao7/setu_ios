import SwiftUI

struct SetuImageTile<Badge: View>: View {
    let urlString: String?
    let accessibilityLabel: String
    var aspectRatio: CGFloat = 1
    var allowsTapToRetry = false
    @ViewBuilder var badge: () -> Badge

    init(
        urlString: String?,
        accessibilityLabel: String,
        aspectRatio: CGFloat = 1,
        allowsTapToRetry: Bool = false,
        @ViewBuilder badge: @escaping () -> Badge = { EmptyView() }
    ) {
        self.urlString = urlString
        self.accessibilityLabel = accessibilityLabel
        self.aspectRatio = aspectRatio
        self.allowsTapToRetry = allowsTapToRetry
        self.badge = badge
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        SetuRemoteImage(
                            urlString: urlString,
                            accessibilityLabel: accessibilityLabel,
                            width: proxy.size.width,
                            height: proxy.size.height,
                            cornerRadius: SetuRadius.md,
                            allowsTapToRetry: allowsTapToRetry
                        )
                    }
                }

            badge()
                .padding(SetuSpacing.sm)
        }
    }
}
