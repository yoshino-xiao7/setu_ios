import SwiftUI

struct SetuMetricRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: String
    var caption: String?
    let progress: Double
    var tone: Color = SetuColor.brandPink
    var diameter: CGFloat = 88
    var lineWidth: CGFloat = 9
    var accessibilityDescription: String?

    private var clampedProgress: Double { progress.isFinite ? min(1, max(0, progress)) : 0 }

    var body: some View {
        VStack(spacing: SetuSpacing.sm) {
            ZStack {
                Circle().stroke(tone.opacity(0.14), lineWidth: lineWidth)
                Circle().trim(from: 0, to: clampedProgress)
                    .stroke(tone, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(SetuMotion.resolved(SetuMotion.gentle, reduceMotion: reduceMotion), value: clampedProgress)
            }
            .frame(width: diameter, height: diameter)
            .padding(lineWidth / 2)
            Text(value).font(SetuTypography.metric).foregroundStyle(SetuColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let caption {
                Text(caption).font(SetuTypography.label).foregroundStyle(SetuColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription ?? "\(caption ?? "进度")，\(value)，\(Int(clampedProgress * 100))%")
    }
}
