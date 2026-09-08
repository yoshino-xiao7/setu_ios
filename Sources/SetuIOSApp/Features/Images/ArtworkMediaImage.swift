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
    @State private var image: UIImage?
    @State private var failed = false
    @State private var retry = UUID()

    var body: some View {
        Rectangle().fill(SetuColor.surfaceMuted)
            .aspectRatio(ratio > 0 ? ratio : 1, contentMode: .fit)
            .overlay {
                if let image {
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
            .task(id: "\(path ?? "")-\(retry)") {
                image = nil; failed = false
                guard let path else { return }
                do {
                    let data = try await client.media(path)
                    try Task.checkCancellation()
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                            kCGImageSourceCreateThumbnailWithTransform: true
                          ] as CFDictionary) else { failed = true; return }
                    image = UIImage(cgImage: cgImage)
                } catch { if !Task.isCancelled { failed = true } }
            }
            .onDisappear { image = nil }
    }
}

struct ArtworkTile: View {
    let work: BrowserArtwork
    let client: ArtworkClient
    var busy = false
    let open: () -> Void
    let bookmark: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Button(action: open) {
                ArtworkMediaImage(path: work.pages.first?.thumbnailUrl, client: client, ratio: work.pages.first?.aspectRatio ?? 1, label: work.title)
                    .overlay(alignment: .topTrailing) {
                        if work.pageCount > 1 || work.kind == "ugoira" {
                            Label(work.kind == "ugoira" ? "动图" : String(work.pageCount), systemImage: work.kind == "ugoira" ? "play.circle" : "square.on.square")
                                .font(.caption2).padding(6).foregroundStyle(.white).background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6)).padding(8)
                        }
                    }
            }.buttonStyle(.plain)
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
