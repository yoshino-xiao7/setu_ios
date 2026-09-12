import SwiftUI

struct SetuBottomCTA<Content: View>: View {
    @Environment(\.setuCanvas) private var canvas
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, canvas.pageGutter)
            .padding(.vertical, SetuSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Divider()
                    .overlay(SetuColor.separator)
            }
    }
}
