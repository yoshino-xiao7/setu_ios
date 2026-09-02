import SetuIOSCore
import SwiftUI

struct DailyExampleCard: View {
    let item: SetuImageItem
    var height: CGFloat = 160
    let onPreview: () -> Void

    var body: some View {
        Button(action: onPreview) {
            SetuRemoteImage(
                urlString: item.previewURLString,
                accessibilityLabel: "今日示例：\(item.title)，作者 \(item.author)",
                width: nil,
                height: height,
                cornerRadius: SetuRadius.md,
                contentMode: .fill,
                allowsTapToRetry: false
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("预览今日示例：\(item.title)")
        .accessibilityIdentifier("daily.example.preview")
    }
}
