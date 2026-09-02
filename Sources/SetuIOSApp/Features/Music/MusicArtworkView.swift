import Foundation
import SetuIOSCore
import SwiftUI

struct MusicArtworkView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    let urlString: String?
    var width: CGFloat? = 54
    var height: CGFloat = 54
    var cornerRadius: CGFloat = 8
    var artworkSize: MusicArtworkSize = .thumbnail
    var systemImage: String = "music.note"
    var onTap: (() -> Void)?
    var allowsTapToRetry = false

    @State private var imageState = SetuRemoteImageState()
    @State private var reloadID = UUID()

    var body: some View {
        Group {
            if onTap != nil || (loadFailed && allowsTapToRetry) {
                Button(action: handleTap) {
                    artworkContent
                }
                .setuButtonFeedback(cornerRadius: cornerRadius)
                .accessibilityLabel(loadFailed ? "封面加载失败，点按重试" : "播放歌曲")
            } else {
                artworkContent
                    .accessibilityLabel("音乐封面")
            }
        }
        .task(id: SetuImageLoadID(key: imageKey, retry: reloadID)) {
            await imageState.load(imageKey, animation: reduceMotion ? nil : .easeInOut(duration: 0.18))
        }
    }

    private var imageKey: SetuImageKey? {
        let size: SetuImageSize
        switch artworkSize {
        case .lockScreen: size = .large
        case .thumbnail, .custom: size = .fitting(width: width, height: height, scale: displayScale)
        }
        return SetuImageKey.music(urlString, size: size)
    }
    private var image: SetuPlatformImage? { imageState.displayedImage(for: imageKey) }
    private var loadFailed: Bool { imageState.key == imageKey && imageState.failed && image == nil }

    private var artworkContent: some View {
        ZStack {
            if let image {
                platformImage(image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: width == nil ? .infinity : nil)
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func handleTap() {
        if loadFailed {
            reloadID = UUID()
        } else {
            onTap?()
        }
    }

    private var normalizedURLString: String? {
        imageKey?.url.absoluteString
    }

    @ViewBuilder
    private var placeholder: some View {
        if normalizedURLString != nil, !loadFailed {
            SetuSkeleton(cornerRadius: cornerRadius)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SetuColor.textTertiary)
                }
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(SetuColor.brandSoft.opacity(0.18))
                .overlay {
                    Image(systemName: loadFailed && allowsTapToRetry ? "arrow.clockwise" : systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(loadFailed && allowsTapToRetry ? SetuColor.danger : SetuColor.brandPink)
                }
        }
    }

    @ViewBuilder
    private func platformImage(_ image: SetuPlatformImage) -> Image {
        #if os(iOS)
        Image(uiImage: image)
        #elseif os(macOS)
        Image(nsImage: image)
        #endif
    }

}
