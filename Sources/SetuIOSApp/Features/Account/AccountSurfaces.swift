import SwiftUI

struct AccountSurfaceItem: Identifiable {
    let title: String
    let value: String
    let systemImage: String
    var route: AppRoute?
    var id: String { title }
}

struct AccountSurfaceSkeleton: View {
    var title = "正在加载"

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.md) {
            SetuSkeleton().frame(height: 140)
            SetuSkeleton().frame(height: 100)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}
