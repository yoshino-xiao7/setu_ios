import SetuIOSCore
import SwiftUI

struct MusicTonearmView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isPlaying: Bool
    var scale: CGFloat = 1.0

    // NetEase tonearm lift/drop angles:
    // Lifted when paused or buffering (-28 degrees)
    // Dropped onto vinyl when playing (0 degrees)
    private var targetAngle: Double {
        isPlaying ? 0 : -28
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                pivotView
                    .frame(width: 32 * scale, height: 32 * scale)

                armBodyView
            }
        }
        // Rotate around pivot center
        .rotationEffect(.degrees(reduceMotion ? (isPlaying ? 0 : -28) : targetAngle), anchor: .init(x: 0.5, y: 0.11))
        .animation(
            reduceMotion ? nil : (isPlaying
                ? .spring(response: 0.44, dampingFraction: 0.7).delay(0.08)
                : .spring(response: 0.32, dampingFraction: 0.82)),
            value: isPlaying
        )
        .shadow(
            color: Color.black.opacity(isPlaying ? 0.38 : 0.18),
            radius: isPlaying ? 8 : 14,
            x: 4,
            y: isPlaying ? 6 : 12
        )
        .accessibilityHidden(true)
    }

    private var pivotView: some View {
        ZStack {
            // Outer bearing ring with metallic finish
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.92), Color(white: 0.55), Color(white: 0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .stroke(Color.white.opacity(0.85), lineWidth: 1)

            // Inner dark inset
            Circle()
                .fill(Color(white: 0.22))
                .padding(4 * scale)

            // Center metal screw
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white, Color(white: 0.65)],
                        center: .center,
                        startRadius: 1,
                        endRadius: 5 * scale
                    )
                )
                .frame(width: 10 * scale, height: 10 * scale)
        }
    }

    private var armBodyView: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            let start = CGPoint(x: w * 0.5, y: 0)
            let elbow = CGPoint(x: w * 0.52, y: h * 0.38)
            let wrist = CGPoint(x: w * 0.34, y: h * 0.82)
            let tip = CGPoint(x: w * 0.25, y: h * 0.98)

            // Upper rod
            var upperPath = Path()
            upperPath.move(to: start)
            upperPath.addLine(to: elbow)
            context.stroke(
                upperPath,
                with: .linearGradient(
                    Gradient(colors: [Color(white: 0.92), Color(white: 0.65), Color(white: 0.85)]),
                    startPoint: start,
                    endPoint: elbow
                ),
                style: StrokeStyle(lineWidth: 4.5 * scale, lineCap: .round)
            )

            // Elbow joint connector
            context.fill(
                Circle().path(in: CGRect(x: elbow.x - 3.5 * scale, y: elbow.y - 3.5 * scale, width: 7 * scale, height: 7 * scale)),
                with: .color(Color(white: 0.72))
            )

            // Lower rod
            var lowerPath = Path()
            lowerPath.move(to: elbow)
            lowerPath.addLine(to: wrist)
            context.stroke(
                lowerPath,
                with: .linearGradient(
                    Gradient(colors: [Color(white: 0.85), Color(white: 0.6), Color(white: 0.8)]),
                    startPoint: elbow,
                    endPoint: wrist
                ),
                style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round)
            )

            // Cartridge / Stylus head
            var cartridgePath = Path()
            cartridgePath.move(to: CGPoint(x: wrist.x - 4.5 * scale, y: wrist.y))
            cartridgePath.addLine(to: CGPoint(x: wrist.x + 4.5 * scale, y: wrist.y))
            cartridgePath.addLine(to: CGPoint(x: tip.x + 3.5 * scale, y: tip.y))
            cartridgePath.addLine(to: CGPoint(x: tip.x - 3.5 * scale, y: tip.y))
            cartridgePath.closeSubpath()

            context.fill(
                cartridgePath,
                with: .linearGradient(
                    Gradient(colors: [Color(white: 0.32), Color(white: 0.16), Color(white: 0.26)]),
                    startPoint: wrist,
                    endPoint: tip
                )
            )

            // Needle tip highlight
            context.fill(
                Circle().path(in: CGRect(x: tip.x - 1.5 * scale, y: tip.y - 1.5 * scale, width: 3 * scale, height: 3 * scale)),
                with: .color(Color(white: 0.96))
            )
        }
        .frame(width: 80 * scale, height: 130 * scale)
    }
}
