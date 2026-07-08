import ActivityKit
import SetuIOSCore
import SwiftUI
import WidgetKit

@main
struct SetuIOSLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        AiGenerationLiveActivityWidget()
    }
}

struct AiGenerationLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AiGenerationActivityAttributes.self) { context in
            AiGenerationLockScreenView(context: context)
                .activityBackgroundTint(Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(.pink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("AI 绘画", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("#\(context.attributes.jobID)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.statusTitle)
                            .font(.headline)
                        Text(context.state.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: statusSymbol(for: context.state.status))
                    .foregroundStyle(statusColor(for: context.state.status))
            } compactTrailing: {
                Text(context.state.statusTitle)
                    .font(.caption2.weight(.semibold))
                    .minimumScaleFactor(0.7)
            } minimal: {
                Image(systemName: statusSymbol(for: context.state.status))
                    .foregroundStyle(statusColor(for: context.state.status))
            }
            .widgetURL(URL(string: "setuios://ai/generation/\(context.attributes.jobID)"))
            .keylineTint(statusColor(for: context.state.status))
        }
    }

    private func statusSymbol(for status: String) -> String {
        switch status {
        case "COMPLETED":
            return "checkmark.circle.fill"
        case "FAILED":
            return "exclamationmark.triangle.fill"
        case "UPLOADING":
            return "icloud.and.arrow.up"
        case "RUNNING":
            return "sparkles"
        default:
            return "clock"
        }
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "COMPLETED":
            return .green
        case "FAILED":
            return .red
        case "UPLOADING":
            return .blue
        case "RUNNING":
            return .pink
        default:
            return .orange
        }
    }
}

private struct AiGenerationLockScreenView: View {
    let context: ActivityViewContext<AiGenerationActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text("AI 绘画 #\(context.attributes.jobID)")
                    .font(.headline)
                Text(context.state.statusTitle)
                    .font(.subheadline.weight(.semibold))
                Text(context.state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
    }

    private var statusSymbol: String {
        switch context.state.status {
        case "COMPLETED":
            return "checkmark.circle.fill"
        case "FAILED":
            return "exclamationmark.triangle.fill"
        case "UPLOADING":
            return "icloud.and.arrow.up"
        case "RUNNING":
            return "sparkles"
        default:
            return "clock"
        }
    }

    private var statusColor: Color {
        switch context.state.status {
        case "COMPLETED":
            return .green
        case "FAILED":
            return .red
        case "UPLOADING":
            return .blue
        case "RUNNING":
            return .pink
        default:
            return .orange
        }
    }
}
