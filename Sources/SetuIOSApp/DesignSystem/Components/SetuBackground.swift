import SwiftUI

extension View {
    func setuBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(SetuColor.pageGradient.ignoresSafeArea())
    }

    func setuListRow() -> some View {
        modifier(SetuListRowModifier())
    }
}

private struct SetuListRowModifier: ViewModifier {
    @Environment(\.setuCanvas) private var canvas

    func body(content: Content) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(
                EdgeInsets(
                    top: SetuSpacing.sm,
                    leading: canvas.pageGutter,
                    bottom: SetuSpacing.sm,
                    trailing: canvas.pageGutter
                )
            )
    }
}
