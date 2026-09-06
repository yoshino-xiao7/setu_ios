import SwiftUI

struct SetuTimelineEvent: Identifiable {
    let id: String
    let title: String
    var detail: String?
    var timestamp: String?
    var tone: SetuPillTone = .muted
    var isCurrent = false
}

struct SetuTimeline: View {
    let events: [SetuTimelineEvent]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                HStack(alignment: .top, spacing: SetuSpacing.md) {
                    VStack(spacing: SetuSpacing.xs) {
                        Circle().fill(event.tone.foreground).frame(width: 12, height: 12)
                        if index < events.count - 1 {
                            Rectangle().fill(SetuColor.separator).frame(width: 2).frame(minHeight: 36)
                        }
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                        Text(event.title).font(SetuTypography.headline).foregroundStyle(SetuColor.textPrimary)
                        if event.isCurrent { SetuPill(text: "当前进度", tone: event.tone) }
                        if let detail = event.detail {
                            Text(detail).font(SetuTypography.body).foregroundStyle(SetuColor.textSecondary)
                        }
                        if let timestamp = event.timestamp {
                            Text(timestamp).font(SetuTypography.caption).foregroundStyle(SetuColor.textTertiary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, SetuSpacing.lg)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
