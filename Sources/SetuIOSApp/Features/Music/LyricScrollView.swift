import SwiftUI
#if os(iOS)
import UIKit
#endif

struct LyricScrollView: View {
    let lines: [LyricLine]
    let currentTime: TimeInterval
    /// Fill all available height (full-page lyrics) instead of the compact inline size.
    var expands = false
    var onBackgroundTap: (() -> Void)?
    let onSeek: (TimeInterval) -> Void

    /// While the user is browsing lyrics manually, auto-centering is suspended so the
    /// list does not jump out from under their finger; it resumes shortly after.
    @State private var isAutoScrollSuspended = false
    @State private var isSelectionGuideVisible = false
    @State private var selectedBrowsingIndex: Int?
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var resumeAutoScrollTask: Task<Void, Never>?
    @State private var lastObservedScrollOffset: CGPoint?

    private var activeIndex: Int? {
        LyricParser.activeIndex(in: lines, at: currentTime)
    }

    var body: some View {
        if lines.isEmpty {
            SetuEmptyState(title: "暂无歌词", systemImage: "text.quote")
        } else {
            GeometryReader { containerProxy in
                ScrollViewReader { proxy in
                    ZStack {
                        ScrollView {
                            LazyVStack(alignment: .center, spacing: SetuSpacing.sm) {
                                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                                    lyricRow(
                                        line,
                                        isActive: index == activeIndex,
                                        isBrowsingSelected: index == selectedBrowsingIndex
                                    )
                                    .id(line.id)
                                    .background {
                                        GeometryReader { rowProxy in
                                            Color.clear.preference(
                                                key: LyricRowFramePreferenceKey.self,
                                                value: [line.id: rowProxy.frame(in: .named(lyricCoordinateSpaceName))]
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, verticalContentPadding(for: containerProxy.size.height))
                            .background {
                                scrollInteractionObserver(viewportHeight: containerProxy.size.height)
                            }
                        }
                        .coordinateSpace(name: lyricCoordinateSpaceName)
                        .modifier(LyricFrameModifier(expands: expands))
                        .background {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onBackgroundTap?()
                                }
                        }
                        .onPreferenceChange(LyricRowFramePreferenceKey.self) { frames in
                            rowFrames = frames
                            if isSelectionGuideVisible {
                                updateSelectedBrowsingIndex(viewportHeight: containerProxy.size.height)
                            }
                        }
                        .onChange(of: activeIndex) { _, index in
                            guard !isAutoScrollSuspended, let index, lines.indices.contains(index) else { return }
                            withAnimation(.easeInOut(duration: 0.22)) {
                                proxy.scrollTo(lines[index].id, anchor: .center)
                            }
                        }
                        .onAppear {
                            if let index = activeIndex, lines.indices.contains(index) {
                                proxy.scrollTo(lines[index].id, anchor: .center)
                            }
                        }
                        .onDisappear {
                            resumeAutoScrollTask?.cancel()
                        }

                        if isSelectionGuideVisible, let line = guideLine {
                            selectionGuide(for: line) {
                                seekSelectedLine(line, proxy: proxy)
                            }
                            .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.16), value: isSelectionGuideVisible)
                    .animation(.easeInOut(duration: 0.16), value: selectedBrowsingIndex)
                }
            }
        }
    }

    @ViewBuilder
    private func scrollInteractionObserver(viewportHeight: CGFloat) -> some View {
        #if os(iOS)
        LyricScrollInteractionObserver { snapshot in
            handleScrollSnapshot(snapshot, viewportHeight: viewportHeight)
        } onPhaseChange: { phase in
            handleScrollPhase(phase, viewportHeight: viewportHeight)
        }
        #else
        Color.clear
        #endif
    }

    private func handleScrollSnapshot(_ snapshot: LyricScrollInteractionSnapshot, viewportHeight: CGFloat) {
        let didMove: Bool
        if let lastObservedScrollOffset {
            let deltaX = abs(snapshot.contentOffset.x - lastObservedScrollOffset.x)
            let deltaY = abs(snapshot.contentOffset.y - lastObservedScrollOffset.y)
            didMove = deltaX > 0.5 || deltaY > 0.5
        } else {
            didMove = false
        }
        lastObservedScrollOffset = snapshot.contentOffset

        guard snapshot.isUserDriven, didMove else { return }
        enterBrowsingMode(viewportHeight: viewportHeight, keepAlive: snapshot.isFingerDown)
    }

    private func handleScrollPhase(_ phase: LyricScrollInteractionPhase, viewportHeight: CGFloat) {
        switch phase {
        case .began, .changed:
            enterBrowsingMode(viewportHeight: viewportHeight, keepAlive: true)
        case .ended, .cancelled:
            if isSelectionGuideVisible {
                updateSelectedBrowsingIndex(viewportHeight: viewportHeight)
            }
            scheduleAutoScrollResume()
        }
    }

    private func enterBrowsingMode(viewportHeight: CGFloat, keepAlive: Bool) {
        if keepAlive {
            resumeAutoScrollTask?.cancel()
        }
        isAutoScrollSuspended = true
        if selectedBrowsingIndex == nil {
            selectedBrowsingIndex = fallbackSelectedIndex(viewportHeight: viewportHeight)
        }
        updateSelectedBrowsingIndex(viewportHeight: viewportHeight)
        if !isSelectionGuideVisible {
            withAnimation(.easeInOut(duration: 0.15)) {
                isSelectionGuideVisible = true
            }
        }
    }

    private func verticalContentPadding(for viewportHeight: CGFloat) -> CGFloat {
        guard expands else { return SetuSpacing.sm }
        return max((viewportHeight / 2) - SetuSpacing.xl, SetuSpacing.xxl)
    }

    private func scheduleAutoScrollResume() {
        resumeAutoScrollTask?.cancel()
        resumeAutoScrollTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                isAutoScrollSuspended = false
                isSelectionGuideVisible = false
                selectedBrowsingIndex = nil
            }
        }
    }

    private func seekSelectedLine(_ line: LyricLine, proxy: ScrollViewProxy) {
        resumeAutoScrollTask?.cancel()
        onSeek(line.time)
        withAnimation(.easeInOut(duration: 0.15)) {
            isAutoScrollSuspended = false
            isSelectionGuideVisible = false
            selectedBrowsingIndex = nil
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(line.id, anchor: .center)
        }
    }

    private func updateSelectedBrowsingIndex(viewportHeight: CGFloat) {
        selectedBrowsingIndex = nearestRowIndex(viewportHeight: viewportHeight) ?? selectedBrowsingIndex ?? activeIndex
    }

    private var guideLine: LyricLine? {
        guard let index = selectedBrowsingIndex ?? activeIndex ?? lines.indices.first else { return nil }
        return lines.indices.contains(index) ? lines[index] : nil
    }

    private func fallbackSelectedIndex(viewportHeight: CGFloat) -> Int? {
        if let index = nearestRowIndex(viewportHeight: viewportHeight) {
            return index
        }
        return activeIndex ?? lines.indices.first
    }

    private func nearestRowIndex(viewportHeight: CGFloat) -> Int? {
        guard !rowFrames.isEmpty else { return nil }
        let viewportCenter = viewportHeight / 2
        return lines.enumerated().compactMap { index, line -> (Int, CGFloat)? in
            guard let frame = rowFrames[line.id] else { return nil }
            return (index, abs(frame.midY - viewportCenter))
        }
        .min { lhs, rhs in
            lhs.1 < rhs.1
        }?
        .0
    }

    private func lyricRow(
        _ line: LyricLine,
        isActive: Bool,
        isBrowsingSelected: Bool
    ) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(line.text)
                .font(.subheadline.weight((isActive || isBrowsingSelected) ? .semibold : .regular))
                .foregroundStyle(primaryLyricColor(isActive: isActive, isBrowsingSelected: isBrowsingSelected))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
            if let translation = line.translation, !translation.isEmpty {
                Text(translation)
                    .font(.caption)
                    .foregroundStyle(secondaryLyricColor(isActive: isActive, isBrowsingSelected: isBrowsingSelected))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, SetuSpacing.md)
        .padding(.vertical, SetuSpacing.xs)
        .contentShape(Rectangle())
        .onTapGesture {
            onBackgroundTap?()
        }
        .accessibilityLabel("\(formatTime(line.time)) \(line.text)")
    }

    private func selectionGuide(for line: LyricLine, play: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: SetuSpacing.sm) {
                Text(formatTime(line.time))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(SetuColor.textSecondary)
                    .frame(width: 44, alignment: .leading)

                LyricSelectionGuideLine()
                    .stroke(
                        SetuColor.textSecondary.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4, 6])
                    )
                    .frame(height: 1)

                Button(action: play) {
                    Image(systemName: "play.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(SetuColor.heroGradient, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("从当前选中歌词播放")
            }
            .padding(.horizontal, SetuSpacing.md)
            Spacer()
        }
    }

    private func primaryLyricColor(isActive: Bool, isBrowsingSelected: Bool) -> Color {
        if isBrowsingSelected { return SetuColor.brandInk }
        if isActive { return SetuColor.brandPink }
        return SetuColor.textPrimary.opacity(0.82)
    }

    private func secondaryLyricColor(isActive: Bool, isBrowsingSelected: Bool) -> Color {
        if isBrowsingSelected { return SetuColor.brandPink.opacity(0.82) }
        if isActive { return SetuColor.brandPink.opacity(0.9) }
        return SetuColor.textSecondary
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

private let lyricCoordinateSpaceName = "LyricScrollViewCoordinateSpace"

private struct LyricRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct LyricSelectionGuideLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct LyricScrollInteractionSnapshot {
    let contentOffset: CGPoint
    let isUserDriven: Bool
    let isFingerDown: Bool
}

private enum LyricScrollInteractionPhase {
    case began
    case changed
    case ended
    case cancelled
}

#if os(iOS)
private struct LyricScrollInteractionObserver: UIViewRepresentable {
    var onScroll: (LyricScrollInteractionSnapshot) -> Void
    var onPhaseChange: (LyricScrollInteractionPhase) -> Void

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ObserverView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.onPhaseChange = onPhaseChange
        uiView.coordinator = context.coordinator
        uiView.attachWhenPossible()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll, onPhaseChange: onPhaseChange)
    }

    final class Coordinator: NSObject {
        var onScroll: (LyricScrollInteractionSnapshot) -> Void
        var onPhaseChange: (LyricScrollInteractionPhase) -> Void

        private weak var scrollView: UIScrollView?
        private var contentOffsetObservation: NSKeyValueObservation?

        init(
            onScroll: @escaping (LyricScrollInteractionSnapshot) -> Void,
            onPhaseChange: @escaping (LyricScrollInteractionPhase) -> Void
        ) {
            self.onScroll = onScroll
            self.onPhaseChange = onPhaseChange
        }

        deinit {
            detach()
        }

        func attach(to scrollView: UIScrollView?) {
            guard let scrollView else { return }
            guard self.scrollView !== scrollView else { return }

            detach()
            self.scrollView = scrollView
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
            contentOffsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self, weak scrollView] _, _ in
                guard let self, let scrollView else { return }
                self.emitSnapshot(from: scrollView)
            }
        }

        func detach() {
            if let scrollView {
                scrollView.panGestureRecognizer.removeTarget(self, action: #selector(handlePan(_:)))
            }
            contentOffsetObservation?.invalidate()
            contentOffsetObservation = nil
            scrollView = nil
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                onPhaseChange(.began)
            case .changed:
                onPhaseChange(.changed)
            case .ended:
                onPhaseChange(.ended)
            case .cancelled, .failed:
                onPhaseChange(.cancelled)
            default:
                break
            }

            if let scrollView {
                emitSnapshot(from: scrollView)
            }
        }

        private func emitSnapshot(from scrollView: UIScrollView) {
            let panState = scrollView.panGestureRecognizer.state
            let isFingerDown = scrollView.isTracking
                || scrollView.isDragging
                || panState == .began
                || panState == .changed
            let isUserDriven = isFingerDown || scrollView.isDecelerating
            onScroll(
                LyricScrollInteractionSnapshot(
                    contentOffset: scrollView.contentOffset,
                    isUserDriven: isUserDriven,
                    isFingerDown: isFingerDown
                )
            )
        }
    }

    final class ObserverView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                coordinator?.detach()
            } else {
                attachWhenPossible()
            }
        }

        func attachWhenPossible() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.coordinator?.attach(to: self.enclosingScrollView())
            }
        }

        private func enclosingScrollView() -> UIScrollView? {
            var view = superview
            while let current = view {
                if let scrollView = current as? UIScrollView {
                    return scrollView
                }
                view = current.superview
            }
            return nil
        }
    }
}
#endif

private struct LyricFrameModifier: ViewModifier {
    let expands: Bool

    func body(content: Content) -> some View {
        if expands {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content.frame(minHeight: 220, maxHeight: 360)
        }
    }
}
