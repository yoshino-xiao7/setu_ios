import SwiftUI

enum LyricFontScale: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }

    var font: Font {
        switch self {
        case .small: .subheadline
        case .medium: .body
        case .large: .title3
        }
    }

    var translationFont: Font {
        switch self {
        case .small: .caption
        case .medium: .subheadline
        case .large: .body
        }
    }
}

struct LyricScrollView: View {
    let lines: [LyricLine]
    let currentTime: TimeInterval
    let fontScale: LyricFontScale
    let onSeek: (TimeInterval) -> Void

    private var activeIndex: Int? {
        LyricParser.activeIndex(in: lines, at: currentTime)
    }

    var body: some View {
        if lines.isEmpty {
            SetuEmptyState(title: "暂无歌词", systemImage: "text.quote")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: SetuSpacing.md) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            lyricRow(line, isActive: index == activeIndex)
                                .id(line.id)
                        }
                    }
                    .padding(.vertical, SetuSpacing.sm)
                }
                .frame(minHeight: 220, maxHeight: 360)
                .onChange(of: activeIndex) { _, index in
                    guard let index, lines.indices.contains(index) else { return }
                    withAnimation(.easeInOut(duration: 0.22)) {
                        proxy.scrollTo(lines[index].id, anchor: .center)
                    }
                }
            }
        }
    }

    private func lyricRow(_ line: LyricLine, isActive: Bool) -> some View {
        Button {
            onSeek(line.time)
        } label: {
            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                Text(line.text)
                    .font(fontScale.font.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? SetuColor.brandInk : SetuColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let translation = line.translation, !translation.isEmpty {
                    Text(translation)
                        .font(fontScale.translationFont)
                        .foregroundStyle(isActive ? SetuColor.brandPink : SetuColor.textSecondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, SetuSpacing.md)
            .padding(.vertical, SetuSpacing.sm)
            .background(isActive ? SetuColor.brandSoft.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(formatTime(line.time)) \(line.text)")
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
