import SwiftUI

struct SetuCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let padding: CGFloat
    private let hasShadow: Bool
    private let content: Content

    init(padding: CGFloat = SetuSpacing.lg, hasShadow: Bool = true, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.hasShadow = hasShadow
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(SetuColor.surface, in: RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous)
                    .stroke(SetuColor.separator, lineWidth: 1)
            }
            .shadow(
                color: !hasShadow || colorScheme == .dark ? .clear : SetuColor.brandPink.opacity(0.10),
                radius: hasShadow ? 12 : 0,
                y: 6
            )
    }
}
