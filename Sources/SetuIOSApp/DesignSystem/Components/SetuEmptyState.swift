import SwiftUI

struct SetuEmptyState: View {
    let title: String
    var message: String?
    var systemImage: String = "sparkles"
    var isLoading = false

    var body: some View {
        VStack(spacing: SetuSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous)
                    .fill(SetuColor.brandSoft.opacity(0.2))
                    .frame(width: 64, height: 64)
                if isLoading {
                    ProgressView()
                        .tint(SetuColor.brandPink)
                } else {
                    Image(systemName: systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(SetuColor.brandPink)
                }
            }

            VStack(spacing: SetuSpacing.xs) {
                Text(title)
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                if let message {
                    Text(message)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(SetuSpacing.xl)
    }
}
