import SwiftUI

struct ImageDisplaySettingsView: View {
    @AppStorage("setu.images.blurPreviews") private var blurPreviews = true

    var body: some View {
        Form {
            Section {
                Toggle("图片模糊化", isOn: $blurPreviews)
                    .accessibilityIdentifier("settings.images.blur-previews")
            } footer: {
                Text("模糊首页收藏图片和图片列表中的 R18 图片，并隐藏首页“今日推荐”。点进图片详情仍显示清晰图片。关闭后恢复展示，设置保存在本机。")
            }
        }
        .setuBackground()
        .navigationTitle("图片显示")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Presentation only: cached image data and detail/original views remain unchanged.
struct ImagePreviewBlur: ViewModifier {
    var eligible = true
    var label = "图片预览"
    @AppStorage("setu.images.blurPreviews") private var blurPreviews = true

    @ViewBuilder func body(content: Content) -> some View {
        if eligible && blurPreviews {
            content.blur(radius: 6)
                .overlay(Color.white.opacity(0.28))
                .clipped()
                .accessibilityLabel(label)
                .accessibilityValue("图片已模糊，点按查看清晰图片")
        } else {
            content
        }
    }
}
