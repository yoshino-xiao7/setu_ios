import SwiftUI

struct ModuleViewportKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// Native TabView owns only the tab bar. Visited pages stay mounted here, so tab changes
/// neither restart their loading tasks nor cancel a page-local animation task.
struct ModulePageContainer<Content: View>: View {
    let selection: AppTab
    let reduceMotion: Bool
    let content: (AppTab) -> Content
    @State private var visited: Set<AppTab>
    @State private var displayed: AppTab
    @State private var direction: CGFloat = 1

    init(selection: AppTab, reduceMotion: Bool, @ViewBuilder content: @escaping (AppTab) -> Content) {
        self.selection = selection
        self.reduceMotion = reduceMotion
        self.content = content
        _visited = State(initialValue: [selection])
        _displayed = State(initialValue: selection)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(AppTab.allCases.filter { visited.contains($0) }) { tab in
                    content(tab)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .offset(x: offset(for: tab, width: geometry.size.width))
                        .opacity(tab == displayed ? 1 : 0)
                        .allowsHitTesting(tab == displayed)
                        .accessibilityHidden(tab != displayed)
                        .zIndex(tab == displayed ? 1 : 0)
                        .transition(.asymmetric(
                            insertion: .offset(x: reduceMotion ? 0 : direction * geometry.size.width * 0.3).combined(with: .opacity),
                            removal: .identity
                        ))
                }
            }
            .clipped()
            .onChange(of: selection) { _, next in
                guard next != displayed else { return }
                direction = index(next) > index(displayed) ? 1 : -1
                withAnimation(.timingCurve(0.22, 0.75, 0.2, 1, duration: reduceMotion ? 0.12 : 0.34)) {
                    visited.insert(next)
                    displayed = next
                }
            }
        }
    }

    private func index(_ tab: AppTab) -> Int {
        AppTab.allCases.firstIndex(of: tab) ?? 0
    }

    private func offset(for tab: AppTab, width: CGFloat) -> CGFloat {
        guard !reduceMotion, tab != displayed else { return 0 }
        return width * 0.3 * (index(tab) < index(displayed) ? -1 : 1)
    }
}
