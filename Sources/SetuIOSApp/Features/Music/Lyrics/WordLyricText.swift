import SwiftUI
#if os(iOS)
import UIKit
#endif

/// One Text per lyric line. Glyph geometry is cached at layout time, never parsed per frame.
struct WordLyricText: View {
    let line: LyricLine
    let currentTime: TimeInterval
    let isPlaying: Bool
    let sampleTime: () -> TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var rects: [[CGRect]] = []
    @ScaledMetric(relativeTo: .subheadline) private var pointSize = 15

    private var font: UIFont { .systemFont(ofSize: pointSize, weight: .semibold) }

    var body: some View {
        Text(line.text)
            .font(Font(font))
            .multilineTextAlignment(.center)
            .foregroundStyle(SetuColor.brandPink)
            .mask {
                GeometryReader { proxy in
                    TimelineView(.animation(minimumInterval: 1.0 / 120, paused: !isPlaying || reduceMotion)) { _ in
                        let time = isPlaying ? sampleTime() : currentTime
                        let progress = LyricParser.syllableProgress(in: line, at: milliseconds(time))
                        Path { path in
                            for (index, segments) in rects.enumerated() {
                                let ratio = progress.map { index < $0.index ? 1 : (index == $0.index ? $0.ratio : 0) } ?? 0
                                var remaining = segments.reduce(0) { $0 + $1.width } * ratio
                                for segment in segments {
                                    let width = min(segment.width, max(0, remaining))
                                    path.addRect(CGRect(x: segment.minX, y: segment.minY, width: width, height: segment.height))
                                    remaining -= segment.width
                                }
                            }
                        }
                        .fill(.white)
                        .background(.white.opacity(0.45))
                    }
                    .onAppear { rects = glyphRects(size: proxy.size) }
                    .onChange(of: proxy.size) { _, size in rects = glyphRects(size: size) }
                    .onChange(of: dynamicTypeSize) { _, _ in rects = glyphRects(size: proxy.size) }
                }
            }
    }

    private func glyphRects(size: CGSize) -> [[CGRect]] {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        let storage = NSTextStorage(string: line.text, attributes: [.font: font, .paragraphStyle: style])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(size.width, 1), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        let verticalScale = size.height / max(layout.usedRect(for: container).height, 1)
        var offset = 0
        return line.words.map { word in
            let length = (word.text as NSString).length
            let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: offset, length: length), actualCharacterRange: nil)
            offset += length
            var segments: [CGRect] = []
            layout.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, range, _ in
                let intersection = NSIntersectionRange(glyphs, range)
                let bounds = layout.boundingRect(forGlyphRange: intersection, in: container)
                // Cover each complete typographic line, including SwiftUI's leading/descenders.
                segments.append(CGRect(x: bounds.minX, y: fragment.minY * verticalScale,
                                       width: bounds.width, height: fragment.height * verticalScale))
            }
            return segments
        }
    }
    #else
    var body: some View { Text(line.text).foregroundStyle(SetuColor.brandPink) }
    #endif

    private func milliseconds(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite else { return 0 }
        return Int(min(Double(Int.max / 2), max(Double(Int.min / 2), seconds * 1000)))
    }
}
