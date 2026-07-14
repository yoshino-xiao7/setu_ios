import SwiftUI

struct SetuPrimaryButton<Label: View>: View {
    @Environment(\.isEnabled) private var isEnabled

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
                .shadow(color: SetuColor.brandPink.opacity(isEnabled ? 0.24 : 0), radius: 14, y: 8)
        }
        .setuButtonFeedback(cornerRadius: 24)
        .opacity(isEnabled ? 1 : 0.52)
    }
}
