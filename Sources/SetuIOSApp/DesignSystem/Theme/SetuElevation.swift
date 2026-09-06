import SwiftUI

enum SetuElevation {
    case flat, card, raised, hero

    fileprivate var shadow: (opacity: Double, radius: CGFloat, y: CGFloat) {
        switch self {
        case .flat: (0, 0, 0)
        case .card: (0.10, 12, 6)
        case .raised: (0.18, 16, 8)
        case .hero: (0.28, 18, 10)
        }
    }
}

private struct SetuElevationModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let level: SetuElevation

    func body(content: Content) -> some View {
        let shadow = (colorScheme == .dark ? SetuElevation.flat : level).shadow
        content.shadow(
            color: SetuColor.brandPink.opacity(shadow.opacity),
            radius: shadow.radius,
            y: shadow.y
        )
    }
}

extension View {
    func setuElevation(_ level: SetuElevation) -> some View {
        modifier(SetuElevationModifier(level: level))
    }
}

enum SetuMotion {
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let gentle = Animation.easeInOut(duration: 0.22)
    static let content = Animation.easeOut(duration: 0.18)

    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
