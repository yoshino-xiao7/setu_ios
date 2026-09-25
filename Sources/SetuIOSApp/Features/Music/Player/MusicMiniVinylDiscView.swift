import SetuIOSCore
import SwiftUI

struct MusicMiniVinylDiscView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let artworkURLString: String?
    let diameter: CGFloat
    let isPlaying: Bool
    var progress: Double = 0 // 0.0 to 1.0

    @State private var rotationAngle: Double = 0
    @State private var lastTick: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isPlaying || reduceMotion)) { timeline in
            ZStack {
                // 1. Subtle Circular Progress Ring around the mini vinyl
                Circle()
                    .stroke(SetuColor.brandPink.opacity(0.18), lineWidth: 2)
                    .frame(width: diameter + 4, height: diameter + 4)

                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(
                        SetuColor.brandPink,
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: diameter + 4, height: diameter + 4)
                    .animation(reduceMotion ? nil : .linear(duration: 0.25), value: progress)

                // 2. Mini Vinyl Body
                ZStack {
                    // Black disc
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(white: 0.18), Color(white: 0.06), Color.black],
                                center: .center,
                                startRadius: diameter * 0.2,
                                endRadius: diameter * 0.5
                            )
                        )

                    // Concentric rings
                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.6)
                        .frame(width: diameter * 0.85, height: diameter * 0.85)

                    // Artwork
                    let centerDiameter = diameter * 0.65
                    MusicArtworkView(
                        urlString: artworkURLString,
                        width: centerDiameter,
                        height: centerDiameter,
                        cornerRadius: centerDiameter / 2,
                        artworkSize: .thumbnail
                    )
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    }

                    // Center metallic spindle pin
                    Circle()
                        .fill(Color(white: 0.85))
                        .frame(width: 6, height: 6)
                        .overlay {
                            Circle().fill(Color.black).frame(width: 2.5, height: 2.5)
                        }
                }
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(reduceMotion ? 0 : rotationAngle))
            }
            .onChange(of: timeline.date) { _, newDate in
                guard isPlaying, !reduceMotion else {
                    lastTick = nil
                    return
                }
                if let last = lastTick {
                    let delta = newDate.timeIntervalSince(last)
                    rotationAngle = (rotationAngle + delta * 18.0).truncatingRemainder(dividingBy: 360.0)
                }
                lastTick = newDate
            }
            .onChange(of: isPlaying) { _, playing in
                if !playing {
                    lastTick = nil
                }
            }
        }
        .frame(width: diameter + 6, height: diameter + 6)
        .accessibilityHidden(true)
    }
}
