import SetuIOSCore
import SwiftUI

struct MusicTurntableView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let track: MusicPlaybackTrack
    let isPlaying: Bool
    let isBuffering: Bool
    let canPlayPrevious: Bool
    let canPlayNext: Bool
    let onSkipPrevious: () -> Void
    let onSkipNext: () -> Void
    let onTapDisc: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isTransitioning = false

    private var effectiveIsPlaying: Bool {
        isPlaying && !isBuffering && !isTransitioning
    }

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width
            let availableHeight = proxy.size.height
            let discDiameter = max(min(availableWidth - SetuSpacing.xl * 2, availableHeight - 44, 330), 160)
            let tonearmScale: CGFloat = min(discDiameter / 280, 1.15)

            ZStack(alignment: .top) {
                // 1. Vinyl disc centered in the staging area
                VStack {
                    Spacer(minLength: 0)
                    MusicVinylDiscView(
                        artworkURLString: track.coverURLString,
                        diameter: discDiameter,
                        isPlaying: effectiveIsPlaying,
                        onTap: {
                            PlayerHaptics.light()
                            onTapDisc()
                        }
                    )
                    .offset(x: dragOffset)
                    .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78), value: dragOffset)
                    Spacer(minLength: 0)
                }
                .frame(width: availableWidth, height: availableHeight)

                // 2. Tonearm positioned at top-center offset towards the top-right
                MusicTonearmView(
                    isPlaying: effectiveIsPlaying,
                    scale: tonearmScale
                )
                // Pivot base anchored at top right quadrant relative to disc center
                .offset(
                    x: min(discDiameter * 0.16, 42),
                    y: max((availableHeight - discDiameter) / 2 - 28, 6)
                )
                .zIndex(2)
            }
            .frame(width: availableWidth, height: availableHeight)
            .contentShape(Rectangle())
            .simultaneousGesture(trackDragGesture)
            .onChange(of: track.id) { _, _ in
                // Lift tonearm briefly on track change
                isTransitioning = true
                Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    isTransitioning = false
                }
            }
        }
    }

    private var trackDragGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                if abs(horizontal) > abs(vertical) {
                    dragOffset = horizontal * 0.4
                }
            }
            .onEnded { value in
                let horizontal = value.predictedEndTranslation.width
                let translation = value.translation.width
                let vertical = value.translation.height

                defer {
                    dragOffset = 0
                }

                guard abs(horizontal) > 40 || abs(translation) > 40,
                      abs(horizontal) > abs(vertical) * 1.2 else {
                    return
                }

                if horizontal < 0 || translation < -40 {
                    if canPlayNext {
                        PlayerHaptics.light()
                        onSkipNext()
                    }
                } else if horizontal > 0 || translation > 40 {
                    if canPlayPrevious {
                        PlayerHaptics.light()
                        onSkipPrevious()
                    }
                }
            }
    }
}
