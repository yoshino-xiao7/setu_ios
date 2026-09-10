import SwiftUI
import SetuIOSCore
#if os(iOS)
import UIKit
import ImageIO

struct ArtworkMediaImage: View {
    let path: String?
    let client: ArtworkClient
    var ratio: Double = 1
    var label = "图片"
    var maxPixelSize = 1000
    var contentMode: ContentMode = .fit
    var identity: String? = nil
    var quality: ArtworkImageStore.Quality = .thumbnail
    @Environment(\.artworkImages) private var images
    @State private var image: UIImage?
    @State private var displayedIdentity: String?
    private var requestedQuality: ArtworkImageStore.Quality { maxPixelSize <= 200 ? .avatar : quality }
    private var cacheIdentity: String { identity ?? path ?? "missing" }
    private var visibleImage: UIImage? {
        if displayedIdentity == cacheIdentity, let image { return image }
        return images?.cached(cacheIdentity, quality: requestedQuality)?.image
    }
    @State private var failed = false
    @State private var retry = UUID()

    var body: some View {
        Rectangle().fill(SetuColor.surfaceMuted)
            .aspectRatio(ratio > 0 ? ratio : 1, contentMode: .fit)
            .overlay {
                if let image = visibleImage {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                } else if failed {
                    Button { retry = UUID() } label: {
                        VStack(spacing: 6) { Image(systemName: "arrow.clockwise"); Text("点击重试").font(.caption) }
                    }.tint(SetuColor.textSecondary)
                } else if path != nil { ProgressView().tint(SetuColor.brandPink) }
                else { Image(systemName: "photo").foregroundStyle(SetuColor.textTertiary) }
            }
            .clipped()
            .accessibilityLabel(label)
            .accessibilityValue(visibleImage != nil ? "图片已显示" : failed ? "图片加载失败" : "正在加载图片")
            .onAppear {
                if let cached = images?.cached(cacheIdentity, quality: requestedQuality) {
                    image = cached.image; displayedIdentity = cacheIdentity
                }
            }
            .task(id: "\(cacheIdentity)-\(requestedQuality.rawValue)-\(path ?? "")-\(retry)") {
                failed = false
                guard let path else { return }
                do {
                    let loader = images ?? ArtworkImageStore(fetch: { try await client.media($0) })
                    let decoded = try await loader.load(path, identity: cacheIdentity, quality: requestedQuality)
                    try Task.checkCancellation()
                    image = decoded.image; displayedIdentity = cacheIdentity
                } catch { if !Task.isCancelled { failed = true } }
            }
            .onDisappear { image = nil } // The bounded session cache retains reusable pixels.
    }
}

private struct ArtworkTransitionSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18, *), let namespace, !reduceMotion {
            content.matchedTransitionSource(id: id, in: namespace)
        } else { content }
    }
}

struct ArtworkTile: View {
    let work: BrowserArtwork
    let client: ArtworkClient
    var transition: Namespace.ID? = nil
    var busy = false
    let open: () -> Void
    let bookmark: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Button(action: open) {
                ArtworkMediaImage(path: work.pages.first?.thumbnailUrl, client: client, ratio: work.pages.first?.aspectRatio ?? 1, label: work.title, identity: work.pages.first.map { work.imageIdentity($0) })
                    .modifier(ImagePreviewBlur(eligible: work.restricted, label: work.title))
                    .contentShape(Rectangle())
                    .modifier(ArtworkTransitionSource(id: work.transitionID, namespace: transition))
                    .overlay(alignment: .topTrailing) {
                        if work.pageCount > 1 || work.kind == "ugoira" {
                            Label(work.kind == "ugoira" ? "动图" : String(work.pageCount), systemImage: work.kind == "ugoira" ? "play.circle" : "square.on.square")
                                .font(.caption2).padding(6).foregroundStyle(.white).background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6)).padding(8)
                        }
                    }
            }.buttonStyle(.plain)
                .accessibilityIdentifier("artwork-thumbnail-\(work.id)")
            HStack(spacing: 0) {
                Button(action: open) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(work.title).font(.subheadline.weight(.medium)).lineLimit(1)
                        Text(work.artist.name).font(.caption).foregroundStyle(SetuColor.textSecondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                Button(action: bookmark) {
                    Image(systemName: work.bookmarked ? "heart.fill" : "heart")
                        .font(.title3).foregroundStyle(work.bookmarked ? SetuColor.brandPink : SetuColor.textSecondary)
                        .frame(width: 44, height: 44)
                }.buttonStyle(.plain).disabled(busy).accessibilityLabel(work.bookmarked ? "取消收藏" : "收藏作品")
            }.padding(.leading, 10).padding(.vertical, 6)
        }
        .background(SetuColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: SetuRadius.md))
        .overlay(RoundedRectangle(cornerRadius: SetuRadius.md).stroke(SetuColor.separator.opacity(0.5)))
    }
}
#endif
