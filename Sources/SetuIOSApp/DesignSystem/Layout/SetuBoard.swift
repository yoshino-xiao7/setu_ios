import SwiftUI

private struct SetuBoardInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var setuBoardInset: CGFloat {
        get { self[SetuBoardInsetKey.self] }
        set { self[SetuBoardInsetKey.self] = newValue }
    }
}

struct SetuBoard<Content: View>: View {
    private let spacing: CGFloat
    private let inset: CGFloat
    private let content: Content

    init(spacing: CGFloat = SetuSpacing.xl, inset: CGFloat = SetuSpacing.lg,
         @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.inset = inset
        self.content = content()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: spacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, inset)
            .padding(.vertical, SetuSpacing.lg)
        }
        .background(SetuColor.pageGradient.ignoresSafeArea())
        .environment(\.setuBoardInset, inset)
    }
}

struct SetuActionDock<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(SetuSpacing.md)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SetuRadius.xl))
            .overlay {
                RoundedRectangle(cornerRadius: SetuRadius.xl)
                    .stroke(SetuColor.separator, lineWidth: 1)
            }
            .setuElevation(.hero)
            .padding(.horizontal, SetuSpacing.lg)
            .padding(.vertical, SetuSpacing.sm)
    }
}

extension View {
    func setuActionDock<Dock: View>(@ViewBuilder content: () -> Dock) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            SetuActionDock(content: content)
        }
    }
}

struct SetuSurfaceButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(SetuMotion.resolved(SetuMotion.gentle, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
