import SetuIOSCore
import SwiftUI

struct AiGenerationGridTile: View {
    let imageURLString: String?
    let prompt: String
    let width: Int
    let height: Int
    let badgeTitle: String
    let badgeTone: SetuPillTone
    var footerTitle: String?
    let action: () -> Void

    init(job: AiGenerationJob, footerTitle: String? = nil, action: @escaping () -> Void) {
        imageURLString = job.imageUrl
        prompt = job.promptCn
        width = job.width
        height = job.height
        badgeTitle = job.publicCategory == "R18" ? "成人内容" : job.statusTitle
        switch job.status {
        case "COMPLETED": badgeTone = job.publicCategory == "R18" ? .danger : .success
        case "FAILED": badgeTone = .danger
        case "RUNNING", "UPLOADING": badgeTone = .info
        case "QUEUED", "CLAIMED": badgeTone = .warning
        default: badgeTone = .brand
        }
        self.footerTitle = footerTitle
        self.action = action
    }

    init(work: AiPublicWork, footerTitle: String? = nil, action: @escaping () -> Void) {
        imageURLString = work.imageUrl
        prompt = work.promptCn
        width = work.width
        height = work.height
        badgeTitle = work.publicCategory == "R18" ? "成人内容" : "公开作品"
        badgeTone = work.publicCategory == "R18" ? .danger : .success
        self.footerTitle = footerTitle
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                SetuImageTile(
                    urlString: imageURLString,
                    accessibilityLabel: "AI 作品：\(prompt)",
                    aspectRatio: imageAspectRatio
                ) {
                    SetuPill(text: badgeTitle, tone: badgeTone)
                }

                Text(prompt)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: SetuSpacing.xs) {
                    Label("\(width)x\(height)", systemImage: "aspectratio")
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
        guard width > 0, height > 0 else {
            return 1
        }
        return CGFloat(width) / CGFloat(height)
    }
}
