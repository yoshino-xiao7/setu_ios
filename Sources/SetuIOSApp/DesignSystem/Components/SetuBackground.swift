import SwiftUI

extension View {
    func setuBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(SetuColor.pageGradient.ignoresSafeArea())
    }

    func setuListRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: SetuSpacing.sm, leading: SetuSpacing.lg, bottom: SetuSpacing.sm, trailing: SetuSpacing.lg))
    }
}
