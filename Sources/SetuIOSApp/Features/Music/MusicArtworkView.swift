import Foundation
import SetuIOSCore
import SwiftUI

#if os(iOS)
import UIKit
typealias PlatformArtworkImage = UIImage
#elseif os(macOS)
import AppKit
typealias PlatformArtworkImage = NSImage
#endif

struct MusicArtworkView: View {
    let urlString: String?
    var width: CGFloat? = 54
    var height: CGFloat = 54
    var cornerRadius: CGFloat = 8
    var artworkSize: MusicArtworkSize = .thumbnail
    var systemImage: String = "music.note"
    var onTap: (() -> Void)?

    @State private var image: PlatformArtworkImage?
    @State private var loadFailed = false
    @State private var reloadID = UUID()

    var body: some View {
        Group {
            if onTap != nil || loadFailed {
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
        .task(id: reloadID) {
            await load()
        }
        .onChange(of: urlString) { _, _ in
            image = nil
            loadFailed = false
            reloadID = UUID()
        }
    }

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
        secureURLString(urlString, artworkSize: artworkSize)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(SetuColor.brandSoft.opacity(0.18))
            .overlay {
                Image(systemName: loadFailed ? "arrow.clockwise" : systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(loadFailed ? SetuColor.danger : SetuColor.brandPink)
            }
    }

    @ViewBuilder
    private func platformImage(_ image: PlatformArtworkImage) -> Image {
        #if os(iOS)
        Image(uiImage: image)
        #elseif os(macOS)
        Image(nsImage: image)
        #endif
    }

    @MainActor
    private func load() async {
        guard let normalizedURLString, let url = URL(string: normalizedURLString) else {
            image = nil
            loadFailed = false
            return
        }

        do {
            let loaded = try await RemoteArtworkLoader.shared.image(from: url)
            withAnimation(.easeInOut(duration: 0.18)) {
                image = loaded
                loadFailed = false
            }
        } catch {
            image = nil
            loadFailed = true
        }
    }
}

actor RemoteArtworkLoader {
    static let shared = RemoteArtworkLoader()

    private let session: URLSession

    init() {
        let cache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "SetuMusicArtworkCache"
        )
        URLCache.shared.memoryCapacity = max(URLCache.shared.memoryCapacity, 64 * 1024 * 1024)
        URLCache.shared.diskCapacity = max(URLCache.shared.diskCapacity, 256 * 1024 * 1024)

        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
    }

    func image(from url: URL) async throws -> PlatformArtworkImage {
        let data = try await data(from: url)
        guard let image = PlatformArtworkImage(data: data) else {
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
