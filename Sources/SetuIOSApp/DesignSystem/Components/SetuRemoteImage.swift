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

    let urlString: String?
    let accessibilityLabel: String
    var width: CGFloat? = 58
    var height: CGFloat? = 58
    var cornerRadius: CGFloat = SetuRadius.sm
    var contentMode: ContentMode = .fill
    var allowsTapToRetry = true
    var onActivate: (() -> Void)?
    var activationHint: String?

    @State private var image: SetuPlatformImage?
    @State private var isLoading = false
    @State private var loadFailed = false
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
        .task(id: reloadID) { await load() }
        .onChange(of: urlString) { _, _ in
            image = nil
            loadFailed = false
            reloadID = UUID()
        }
    }

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
        image = nil
        loadFailed = false
        reloadID = UUID()
    }

    private var normalizedURL: URL? {
        urlString.flatMap(URL.init(string:))
    }

    @MainActor
    private func load() async {
        guard let url = normalizedURL else {
            image = nil
            isLoading = false
            loadFailed = false
            return
        }

        isLoading = true
        loadFailed = false
        do {
            let loaded = try await SetuRemoteImageLoader.shared.image(from: url)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                image = loaded
                isLoading = false
            }
        } catch {
            guard !Task.isCancelled else { return }
            image = nil
            isLoading = false
            loadFailed = true
        }
    }
}

actor SetuRemoteImageLoader {
    static let shared = SetuRemoteImageLoader()

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "SetuRemoteImageCache"
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
    }

    func image(from url: URL) async throws -> SetuPlatformImage {
        let data = try await data(from: url)
        guard let image = SetuPlatformImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        return image
    }

    func data(from url: URL) async throws -> Data {
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        if let cached = session.configuration.urlCache?.cachedResponse(for: request) {
            return cached.data
        }

        do {
            return try await fetchData(with: request)
        } catch {
            return try await fetchData(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        }
    }

    private func fetchData(with request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
