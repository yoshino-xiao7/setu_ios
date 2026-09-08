import SetuIOSCore
import SwiftUI

struct ImagePidCopyButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let display: ImagePidDisplay
    var onCopied: () -> Void

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 4) {
                Text(display.fieldLabel)
                    .foregroundStyle(SetuColor.textSecondary)
                Text(display.text)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(SetuColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                    .foregroundStyle(SetuColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .font(.caption)
            .padding(.vertical, 2)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 44 : 28, alignment: .leading)
            .contentShape(Rectangle())
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
