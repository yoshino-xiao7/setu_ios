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
        .tint(SetuColor.brandInk)
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
            .tint(SetuColor.brandInk)
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
    func setuActionDock<Dock: View>(isPresented: Bool = true, @ViewBuilder content: () -> Dock) -> some View {
        modifier(SetuActionDockModifier(isPresented: isPresented, dock: content()))
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


private struct SetuBottomAccessoryKey: EnvironmentKey {
    static let defaultValue = AnyView(EmptyView())
}

private extension EnvironmentValues {
    var setuBottomAccessory: AnyView {
        get { self[SetuBottomAccessoryKey.self] }
        set { self[SetuBottomAccessoryKey.self] = newValue }
    }
}

private struct SetuActionDockPresenceKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct SetuActionDockModifier<Dock: View>: ViewModifier {
    @Environment(\.setuBottomAccessory) private var accessory
    let isPresented: Bool
    let dock: Dock

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isPresented {
                    VStack(spacing: 0) {
                        accessory
                        SetuActionDock { dock }
                    }
                }
            }
            .preference(key: SetuActionDockPresenceKey.self, value: isPresented)
    }
}

private struct SetuPageBottomAccessoryModifier<Accessory: View>: ViewModifier {
    @State private var hasDock = false
    let accessory: Accessory

    func body(content: Content) -> some View {
        content
            .environment(\.setuBottomAccessory, AnyView(accessory))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !hasDock { accessory }
            }
            .onPreferenceChange(SetuActionDockPresenceKey.self) { hasDock = $0 }
            // Each navigation page owns its reservation; do not leak to parent pages.
            .transformPreference(SetuActionDockPresenceKey.self) { $0 = false }
    }
}

extension View {
    /// A page with a Dock places this accessory above its action. Other pages
    /// retain the regular bottom reservation, using the same accessory instance.
    func setuPageBottomAccessory<Accessory: View>(@ViewBuilder content: () -> Accessory) -> some View {
        modifier(SetuPageBottomAccessoryModifier(accessory: content()))
    }
}
