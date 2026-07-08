import SwiftUI

struct SetuPrimaryButton<Label: View>: View {
    let action: () -> Void
    private let label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, SetuSpacing.lg)
                .background(SetuColor.heroGradient, in: Capsule())
                .shadow(color: SetuColor.brandPink.opacity(0.24), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
    }
}
