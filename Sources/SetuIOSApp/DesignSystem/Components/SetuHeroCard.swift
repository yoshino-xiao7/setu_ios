import SwiftUI

struct SetuHeroCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let subtitle: String
    let systemImage: String
    var showsChevron = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        HStack {
                            heroIcon
                            Spacer(minLength: SetuSpacing.sm)
                            chevron
                        }
                        copy
                    }
                } else {
                    HStack(spacing: SetuSpacing.lg) {
                        heroIcon
                        copy
                        Spacer(minLength: SetuSpacing.sm)
                        chevron
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(SetuSpacing.xl)
            .background(SetuColor.heroGradient, in: RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous))
            .shadow(color: SetuColor.brandPink.opacity(0.28), radius: 18, y: 10)
        }
        .setuButtonFeedback(cornerRadius: SetuRadius.lg)
        .accessibilityElement(children: .combine)
    }

    private var heroIcon: some View {
        Image(systemName: systemImage)
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
            .accessibilityHidden(true)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
            Text(title)
                .font(SetuTypography.title)
            Text(subtitle)
                .font(SetuTypography.caption)
                .opacity(0.9)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var chevron: some View {
        if showsChevron {
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.bold))
                .opacity(0.8)
                .accessibilityHidden(true)
        }
    }
}
