import SetuIOSCore
import SwiftUI

struct ImagePidCopyButton: View {
    let display: ImagePidDisplay
    var onCopied: () -> Void

    var body: some View {
        Button(action: copy) {
            HStack(spacing: SetuSpacing.sm) {
                Text("PID")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SetuColor.textSecondary)
                Text(display.text)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Image(systemName: "doc.on.doc")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SetuColor.brandInk)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, SetuSpacing.md)
            .padding(.vertical, SetuSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(SetuColor.brandSoft.opacity(0.42), in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous)
                    .stroke(SetuColor.brandInk.opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(display.accessibilityLabel)
        .accessibilityHint("复制后可粘贴到笔记或搜索")
        .accessibilityIdentifier("image.pid.copy")
    }

    private func copy() {
        PlatformClipboard.copy(display.copyText)
        onCopied()
    }
}
