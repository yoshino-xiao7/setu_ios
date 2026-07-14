import SwiftUI

struct SetuSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var cornerRadius: CGFloat = SetuRadius.sm
    @State private var isDimmed = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(SetuColor.surfaceMuted)
            .opacity(isDimmed ? 0.55 : 1)
            .onAppear { updateAnimation() }
            .onChange(of: reduceMotion) { _, _ in updateAnimation() }
            .accessibilityHidden(true)
    }

    private func updateAnimation() {
        guard !reduceMotion else {
            isDimmed = false
            return
        }

        isDimmed = false
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            isDimmed = true
        }
    }
}
