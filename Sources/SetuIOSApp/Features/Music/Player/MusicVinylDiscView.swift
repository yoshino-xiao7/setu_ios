import SetuIOSCore
import SwiftUI

struct MusicVinylDiscView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let artworkURLString: String?
    let diameter: CGFloat
    let isPlaying: Bool
    var onTap: (() -> Void)?

    @State private var rotationAngle: Double = 0
    @State private var lastTick: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isPlaying || reduceMotion)) { timeline in
            discBody
                .rotationEffect(.degrees(reduceMotion ? 0 : rotationAngle))
                .onChange(of: timeline.date) { _, newDate in
                    guard isPlaying, !reduceMotion else {
                        lastTick = nil
                        return
                    }
                    if let last = lastTick {
                        let delta = newDate.timeIntervalSince(last)
                        // 360 degrees in 20 seconds = 18 degrees/sec
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
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .onTapGesture {
            onTap?()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("黑胶唱片，点按查看歌词")
    }

    private var discBody: some View {
        ZStack {
            // 1. Vinyl black disc base with realistic concentric gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.12, green: 0.12, blue: 0.14),
                            Color(red: 0.05, green: 0.05, blue: 0.07),
                            Color.black
                        ],
                        center: .center,
                        startRadius: diameter * 0.28,
                        endRadius: diameter * 0.5
                    )
                )
                .shadow(color: Color.black.opacity(0.4), radius: 22, y: 12)

            // 2. Concentric sound grooves
            ForEach(0..<10, id: \.self) { i in
                let factor = 0.65 + Double(i) * 0.033
                Circle()
                    .stroke(Color.white.opacity(0.045), lineWidth: 0.75)
                    .frame(width: diameter * factor, height: diameter * factor)
            }

            // 3. Specular sheen (dual conic reflection)
            AngularGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.0),
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.0),
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.0)
                ]),
                center: .center
            )
            .clipShape(Circle())

            // 4. Center Artwork Circle
            let centerDiameter = diameter * 0.62
            ZStack {
                // Outer ring border
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.black.opacity(0.7), Color.white.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: centerDiameter + 2, height: centerDiameter + 2)

                // Artwork
                MusicArtworkView(
                    urlString: artworkURLString,
                    width: centerDiameter,
                    height: centerDiameter,
                    cornerRadius: centerDiameter / 2,
                    artworkSize: .lockScreen
                )
                .clipShape(Circle())

                // 5. Spindle pin (Center metallic hole)
                let spindleDiameter: CGFloat = max(diameter * 0.07, 16)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(white: 0.85),
                                Color(white: 0.45),
                                Color(white: 0.15)
                            ],
                            center: .center,
                            startRadius: 1,
                            endRadius: spindleDiameter / 2
                        )
                    )
                    .frame(width: spindleDiameter, height: spindleDiameter)
                    .overlay {
                        Circle()
                            .fill(Color.black)
                            .frame(width: spindleDiameter * 0.35, height: spindleDiameter * 0.35)
                    }
                    .shadow(color: Color.black.opacity(0.35), radius: 2, y: 1)
            }
        }
    }
}
