import SwiftUI

struct EntryAnchors {
    var logo: Anchor<CGRect>?
    var greeting: HomeGreetingAnchor?
}

struct WelcomeLogoAnchorKey: PreferenceKey {
    static var defaultValue: EntryAnchors { EntryAnchors() }
    static func reduce(value: inout EntryAnchors, nextValue: () -> EntryAnchors) {
        let next = nextValue()
        value.logo = next.logo ?? value.logo
        value.greeting = next.greeting ?? value.greeting
    }
}

private struct BrandSplashActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var brandSplashActive: Bool {
        get { self[BrandSplashActiveKey.self] }
        set { self[BrandSplashActiveKey.self] = newValue }
    }
}

/// A bounded, presentation-only cold-start transition. Session restoration runs underneath.
struct BrandSplashView: View {
    let destination: CGRect?
    let reduceMotion: Bool
    var signedIn = false
    var loginWelcome = false
    var greetingDestination: CGRect? = nil
    var greetingTitle = "欢迎回来"
    let completion: () -> Void
    @State private var startedAt: Date?

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { context in
                let elapsed = startedAt.map { max(0, context.date.timeIntervalSince($0)) } ?? 0
                let move = reduceMotion ? 0 : eased(elapsed, from: 1.25, to: 1.86)
                let reveal = eased(elapsed, from: reduceMotion ? 0 : 1.55, to: reduceMotion ? 0.2 : 2)
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                let target = destination.map { CGPoint(x: $0.midX, y: $0.midY) } ?? center
                ZStack(alignment: .topLeading) {
                    AuthPalette.background
                        .ignoresSafeArea()
                        .opacity(signedIn ? (!loginWelcome && elapsed < 1.36 ? 1 : 0) : 1 - reveal)
                    if !loginWelcome {
                    logo(elapsed: elapsed)
                        .frame(width: 66, height: 58)
                        .scaleEffect(reduceMotion ? 1 : 1.28 - 0.28 * move)
                        .position(x: center.x + (target.x - center.x) * move,
                                  y: center.y + (target.y - center.y) * move)
                        .opacity(signedIn ? 1 - eased(elapsed, from: 1.05, to: 1.36) : destination == nil || reduceMotion ? 1 - reveal : 1)
                    }
                    if signedIn {
                        HomeWelcomeAnimation(
                            elapsed: max(0, elapsed - (loginWelcome || reduceMotion ? 0 : 1.36)),
                            destination: greetingDestination,
                            title: greetingTitle,
                            reduceMotion: reduceMotion
                        )
                        .opacity(loginWelcome || reduceMotion || elapsed >= 1.36 ? 1 : 0)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("亦可正在启动")
        .accessibilityIdentifier("app.brandSplash")
        .task {
            do {
                // Let the initial scene layout settle before starting the drawing clock.
                try await Task.sleep(for: .milliseconds(150))
                startedAt = Date()
                try await Task.sleep(for: .seconds(reduceMotion ? 0.2 : signedIn ? (loginWelcome ? 2.29 : 3.65) : 2))
                completion()
            } catch {
                // SwiftUI cancels this task if the owning scene disappears.
            }
        }
    }

    private func logo(elapsed: Double) -> some View {
        ZStack {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .foregroundStyle(SetuColor.textPrimary)
                .opacity(reduceMotion ? 1 : eased(elapsed, from: 0.94, to: 1.24))
            if !reduceMotion {
                ForEach(0..<2) { part in
                    let progress = eased(elapsed, from: 0.1 + Double(part) * 0.4, to: 0.64 + Double(part) * 0.4)
                    let opacity = 1 - eased(elapsed, from: 1.12, to: 1.38)
                    BrandLogoContour(part: part)
                        .trim(from: 0, to: progress)
                        .stroke(SetuColor.brandPink, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                        .opacity(opacity)
                    BrandLogoContour(part: part)
                        .trim(from: max(0, progress - 0.025), to: progress)
                        .stroke(SetuColor.brandPink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        .shadow(color: SetuColor.brandPink, radius: 2)
                        .opacity(progress > 0 && progress < 1 ? opacity : 0)
                }
            }
        }
    }

    private func eased(_ time: Double, from start: Double, to end: Double) -> Double {
        let value = min(1, max(0, (time - start) / (end - start)))
        return value * value * (3 - 2 * value)
    }
}

/// Exact contours from the approved yike-logo.svg master (viewBox 220 280 805 690).
private struct BrandLogoContour: Shape {
    let part: Int
    func path(in rect: CGRect) -> Path {
        var path = Path()
        if part == 0 {
            path.move(to: CGPoint(x: 245, y: 495))
            path.addCurve(to: CGPoint(x: 425, y: 451), control1: CGPoint(x: 295, y: 439), control2: CGPoint(x: 374, y: 420))
            path.addCurve(to: CGPoint(x: 526, y: 640), control1: CGPoint(x: 482, y: 486), control2: CGPoint(x: 489, y: 620))
            path.addCurve(to: CGPoint(x: 575, y: 590), control1: CGPoint(x: 553, y: 655), control2: CGPoint(x: 575, y: 634))
            path.addLine(to: CGPoint(x: 575, y: 412))
            path.addCurve(to: CGPoint(x: 681, y: 305), control1: CGPoint(x: 575, y: 351), control2: CGPoint(x: 622, y: 305))
            path.addLine(to: CGPoint(x: 716, y: 305))
            path.addQuadCurve(to: CGPoint(x: 721, y: 311), control: CGPoint(x: 721, y: 305))
            path.addLine(to: CGPoint(x: 721, y: 508))
            path.addCurve(to: CGPoint(x: 686, y: 579), control1: CGPoint(x: 721, y: 540), control2: CGPoint(x: 708, y: 557))
            path.addLine(to: CGPoint(x: 587, y: 680))
            path.addCurve(to: CGPoint(x: 480, y: 728), control1: CGPoint(x: 552, y: 715), control2: CGPoint(x: 523, y: 728))
            path.addCurve(to: CGPoint(x: 349, y: 622), control1: CGPoint(x: 404, y: 728), control2: CGPoint(x: 372, y: 677))
            path.addLine(to: CGPoint(x: 307, y: 540))
            path.addCurve(to: CGPoint(x: 245, y: 497), control1: CGPoint(x: 291, y: 510), control2: CGPoint(x: 271, y: 494))
            path.closeSubpath()
        } else {
            path.move(to: CGPoint(x: 340, y: 813))
            path.addCurve(to: CGPoint(x: 419, y: 799), control1: CGPoint(x: 366, y: 791), control2: CGPoint(x: 395, y: 785))
            path.addCurve(to: CGPoint(x: 479, y: 820), control1: CGPoint(x: 443, y: 814), control2: CGPoint(x: 453, y: 837))
            path.addLine(to: CGPoint(x: 786, y: 521))
            path.addCurve(to: CGPoint(x: 991, y: 500), control1: CGPoint(x: 843, y: 469), control2: CGPoint(x: 925, y: 458))
            path.addLine(to: CGPoint(x: 765, y: 691))
            path.addCurve(to: CGPoint(x: 863, y: 752), control1: CGPoint(x: 809, y: 693), control2: CGPoint(x: 838, y: 718))
            path.addLine(to: CGPoint(x: 996, y: 908))
            path.addQuadCurve(to: CGPoint(x: 995, y: 918), control: CGPoint(x: 1001, y: 914))
            path.addCurve(to: CGPoint(x: 802, y: 891), control1: CGPoint(x: 927, y: 958), control2: CGPoint(x: 850, y: 945))
            path.addLine(to: CGPoint(x: 714, y: 784))
            path.addCurve(to: CGPoint(x: 649, y: 779), control1: CGPoint(x: 692, y: 755), control2: CGPoint(x: 674, y: 751))
            path.addLine(to: CGPoint(x: 545, y: 887))
            path.addCurve(to: CGPoint(x: 378, y: 942), control1: CGPoint(x: 495, y: 937), control2: CGPoint(x: 433, y: 957))
            path.addCurve(to: CGPoint(x: 317, y: 842), control1: CGPoint(x: 327, y: 929), control2: CGPoint(x: 299, y: 883))
            path.addQuadCurve(to: CGPoint(x: 340, y: 813), control: CGPoint(x: 323, y: 825))
            path.closeSubpath()
        }
        let scale = min(rect.width / 805, rect.height / 690)
        let x = rect.midX - 805 * scale / 2 - 220 * scale
        let y = rect.midY - 690 * scale / 2 - 280 * scale
        return path.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: x, ty: y))
    }
}
