import SwiftUI
import SetuIOSCore
#if os(iOS)
import UIKit

struct ArtworkDetailView: View {
    let source: ArtworkSource
    let initialID: String
    @Bindable var store: ArtworkBrowserStore
    let environment: AppEnvironment
    var transition: Namespace.ID? = nil
    let onArtist: (String) -> Void
    let onTag: (String) -> Void
    @State private var selectedID: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let selection = Binding(get: { selectedID ?? initialID }, set: { selectedID = $0 })
        ArtworkPager(ids: store.state(source).items.map(\.id), selection: selection) { id, active in
            AnyView(ArtworkDetailPage(source: source, initialID: id, store: store, environment: environment,
                                     active: active, close: { dismiss() }, select: { selection.wrappedValue = $0 },
                                     onArtist: onArtist, onTag: onTag)
                .environment(\.artworkImages, store.images))
        }
        .modifier(ArtworkZoomTransition(id: "\(source.rawValue):\(selection.wrappedValue)", namespace: reduceMotion ? nil : transition))
        .task(id: selection.wrappedValue) { await store.prefetchNeighbors(source: source, id: selection.wrappedValue) }
        .ignoresSafeArea()
    }
}

struct ArtworkZoomTransition: ViewModifier {
    let id: String
    let namespace: Namespace.ID?
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18, *), let namespace {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else { content }
    }
}

/// UIPageViewController supplies interactive/cancellable horizontal paging while
/// each hosted page keeps its own vertical scroll. Retain only current +/- one.
private struct ArtworkPager: UIViewControllerRepresentable {
    let ids: [String]
    @Binding var selection: String
    let content: (String, Bool) -> AnyView

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        controller.dataSource = context.coordinator; controller.delegate = context.coordinator
        context.coordinator.synchronize(controller)
        return controller
    }
    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.synchronize(controller)
    }

    final class Page: UIHostingController<AnyView> {
        let artworkID: String
        init(id: String, root: AnyView) { artworkID = id; super.init(rootView: root); view.backgroundColor = .clear }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    }
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: ArtworkPager
        var pages: [String: Page] = [:]
        var transitioning = false
        init(_ parent: ArtworkPager) { self.parent = parent }
        func page(_ id: String) -> Page {
            if let page = pages[id] { return page }
            let page = Page(id: id, root: parent.content(id, id == parent.selection))
            pages[id] = page
            return page
        }
        func synchronize(_ controller: UIPageViewController) {
            guard !transitioning else { return }
            let selected = parent.selection
            if (controller.viewControllers?.first as? Page)?.artworkID != selected {
                controller.setViewControllers([page(selected)], direction: .forward, animated: false)
            }
            var retained: Set<String> = [selected]
            if let index = parent.ids.firstIndex(of: selected) {
                for neighbor in [index - 1, index + 1] where parent.ids.indices.contains(neighbor) {
                    retained.insert(parent.ids[neighbor])
                }
            }
            pages = pages.filter { retained.contains($0.key) }
            for (id, page) in pages { page.rootView = parent.content(id, id == selected) }
        }
        func neighbor(_ controller: UIViewController, offset: Int) -> UIViewController? {
            guard let page = controller as? Page, let index = parent.ids.firstIndex(of: page.artworkID),
                  parent.ids.indices.contains(index + offset) else { return nil }
            return self.page(parent.ids[index + offset])
        }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? { neighbor(viewController, offset: -1) }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? { neighbor(viewController, offset: 1) }
        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) { transitioning = true }
        func pageViewController(_ controller: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            transitioning = false
            if completed, let page = controller.viewControllers?.first as? Page { parent.selection = page.artworkID }
            synchronize(controller)
        }
    }
}
#endif
