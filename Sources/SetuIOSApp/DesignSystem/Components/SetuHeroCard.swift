import SwiftUI

struct SetuHeroCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var showsChevron = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SetuSpacing.lg) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                    Text(title)
                        .font(SetuTypography.title)
                    Text(subtitle)
                        .font(SetuTypography.caption)
                        .opacity(0.9)
                        .lineLimit(3)
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: SetuSpacing.sm)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .opacity(0.8)
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
}
