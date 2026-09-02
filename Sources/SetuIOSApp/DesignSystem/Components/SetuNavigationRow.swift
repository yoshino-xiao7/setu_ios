import SwiftUI

struct SetuNavigationRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    var iconColor: Color = SetuColor.brandPink
    let action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        iconColor: Color = SetuColor.brandPink,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.iconColor = iconColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: SetuSpacing.md) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(iconColor)
                    .frame(width: 36, height: 36)
                    .background(SetuColor.brandSoft.opacity(0.22), in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                    Text(title)
                        .font(SetuTypography.headline)
                        .foregroundStyle(SetuColor.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: SetuSpacing.sm)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SetuColor.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .setuButtonFeedback()
        .frame(minHeight: 52)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        [title, subtitle]
            .compactMap { $0 }
            .joined(separator: "，")
    }
}
