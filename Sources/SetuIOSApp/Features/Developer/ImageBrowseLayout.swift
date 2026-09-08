import SwiftUI

/// Layout-only rules; image loading and consumption remain in the feed controller.
enum ImageBrowseLayout {
    /// Vertical and diagonal reading gestures must never change the selected image.
    static func swipeDirection(translation: CGSize) -> Int? {
        guard abs(translation.width) >= 60,
              abs(translation.width) > abs(translation.height) * 1.5 else { return nil }
        return translation.width < 0 ? -1 : 1
    }

    static func imageHeight(containerWidth: CGFloat, pixelWidth: Int, pixelHeight: Int) -> CGFloat {
        guard containerWidth.isFinite, containerWidth > 0 else { return 0 }
        guard pixelWidth > 0, pixelHeight > 0 else { return containerWidth }
        return containerWidth * CGFloat(pixelHeight) / CGFloat(pixelWidth)
    }
}

struct ImageBrowseTagLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? 390).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(subviews, width: bounds.width)
        for (index, frame) in layout.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                  anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, frames: [CGRect]) {
        let available = max(0, width)
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var frames: [CGRect] = []
        for view in subviews {
            let ideal = view.sizeThatFits(.unspecified)
            let size = view.sizeThatFits(ProposedViewSize(width: min(ideal.width, available), height: nil))
            if x > 0, x + size.width > available {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: available, height: y + rowHeight), frames)
    }
}
