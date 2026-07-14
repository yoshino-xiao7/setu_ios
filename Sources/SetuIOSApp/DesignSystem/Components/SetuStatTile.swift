import SwiftUI

struct SetuStatTile: View {
    let title: String
    let value: String
    let systemImage: String
    var color: Color = SetuColor.brandPink

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(SetuTypography.metric)
                .foregroundStyle(SetuColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(title)
                .font(.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SetuSpacing.md)
        .background(SetuColor.surfaceMuted, in: RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
    }
}
