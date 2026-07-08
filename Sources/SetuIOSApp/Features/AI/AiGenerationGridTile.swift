import SetuIOSCore
import SwiftUI

struct AiGenerationGridTile: View {
    let job: AiGenerationJob
    var footerTitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                SetuImageTile(urlString: job.imageUrl, aspectRatio: imageAspectRatio) {
                    SetuPill(text: badgeTitle, tone: badgeTone)
                }

                Text(job.promptCn)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: SetuSpacing.xs) {
                    Label("\(job.width)x\(job.height)", systemImage: "aspectratio")
                    if let footerTitle {
                        Text(footerTitle)
                    }
                }
                .font(.caption2)
                .foregroundStyle(SetuColor.textSecondary)
                .lineLimit(1)
            }
            .padding(SetuSpacing.sm)
            .background(SetuColor.surface, in: RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SetuRadius.md, style: .continuous)
                    .stroke(SetuColor.separator, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var imageAspectRatio: CGFloat {
        guard job.height > 0 else {
            return 1
        }
        return CGFloat(job.width) / CGFloat(job.height)
    }

    private var badgeTitle: String {
        if let category = job.publicCategory, !category.isEmpty {
            return category == "R18" ? "R18" : job.statusTitle
        }
        return job.statusTitle
    }

    private var badgeTone: SetuPillTone {
        switch job.status {
        case "COMPLETED":
            job.publicCategory == "R18" ? .danger : .success
        case "FAILED":
            .danger
        case "RUNNING", "UPLOADING":
            .info
        case "QUEUED", "CLAIMED":
            .warning
        default:
            .brand
        }
    }
}
