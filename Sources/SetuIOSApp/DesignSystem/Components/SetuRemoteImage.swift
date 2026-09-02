import Foundation
import SwiftUI

#if os(iOS)
import UIKit
typealias SetuPlatformImage = UIImage
#elseif os(macOS)
import AppKit
typealias SetuPlatformImage = NSImage
#endif

struct SetuRemoteImage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    let urlString: String?
    let accessibilityLabel: String
    var width: CGFloat? = 58
    var height: CGFloat? = 58
    var cornerRadius: CGFloat = SetuRadius.sm
    var contentMode: ContentMode = .fill
    var allowsTapToRetry = true
    var onActivate: (() -> Void)?
    var activationHint: String?

    @State private var imageState = SetuRemoteImageState()
    @State private var reloadID = UUID()

    var body: some View {
        Group {
            if loadFailed, allowsTapToRetry {
                Button(action: retry) {
                    imageContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(accessibilityLabel)，加载失败")
                .accessibilityHint("轻点重新加载")
            } else if image != nil, let onActivate {
                Button(action: onActivate) {
                    imageContent
                }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityHint(activationHint ?? "轻点查看")
            } else {
                imageContent
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityDescription)
            }
        }
        .task(id: SetuImageLoadID(key: imageKey, retry: reloadID)) {
            await imageState.load(imageKey, animation: reduceMotion ? nil : .easeInOut(duration: 0.18))
        }
    }

    private var imageKey: SetuImageKey? {
        normalizedURL.map { SetuImageKey(url: $0, size: .fitting(width: width, height: height, scale: displayScale)) }
    }
    private var image: SetuPlatformImage? { imageState.displayedImage(for: imageKey) }
    private var loadFailed: Bool { imageState.key == imageKey && imageState.failed && image == nil }
    private var isLoading: Bool { imageState.key == imageKey && imageState.isLoading && image == nil }

    private var imageContent: some View {
        ZStack {
            if let image {
                renderedImage(image)
                    .transition(.opacity)
            } else if isLoading {
                SetuSkeleton(cornerRadius: cornerRadius)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(SetuColor.textTertiary)
                            .accessibilityHidden(true)
                    }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: width == nil ? .infinity : nil)
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(SetuColor.separator, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(SetuColor.brandSoft.opacity(0.18))
            .overlay {
                VStack(spacing: SetuSpacing.xs) {
                    Image(systemName: failureSystemImage)
                        .font(.body.weight(.semibold))
                    if loadFailed, allowsTapToRetry, min(width ?? 120, height ?? 120) >= 96 {
                        Text("重新加载")
                            .font(SetuTypography.caption)
                    }
                }
                .foregroundStyle(loadFailed ? SetuColor.danger : SetuColor.brandPink)
                .accessibilityHidden(true)
            }
    }

    private var failureSystemImage: String {
        guard loadFailed else { return "photo" }
        return allowsTapToRetry ? "arrow.clockwise" : "exclamationmark.triangle"
    }

    private var accessibilityDescription: String {
        if isLoading { return "\(accessibilityLabel)，正在加载" }
        if loadFailed { return "\(accessibilityLabel)，加载失败" }
        return accessibilityLabel
    }

    @ViewBuilder
    private func platformImage(_ image: SetuPlatformImage) -> Image {
        #if os(iOS)
        Image(uiImage: image)
        #elseif os(macOS)
        Image(nsImage: image)
        #endif
    }

    @ViewBuilder
    private func renderedImage(_ image: SetuPlatformImage) -> some View {
        switch contentMode {
        case .fit:
            platformImage(image)
                .resizable()
                .scaledToFit()
        case .fill:
            platformImage(image)
                .resizable()
                .scaledToFill()
        }
    }

    private func retry() {
        guard normalizedURL != nil else { return }
        reloadID = UUID()
    }

    private var normalizedURL: URL? {
        urlString.flatMap(URL.init(string:))
    }

}
