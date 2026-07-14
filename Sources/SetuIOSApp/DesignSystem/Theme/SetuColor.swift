import SwiftUI

enum SetuColor {
    static let brandPink = Color("brand/pink")
    static let brandInk = Color("brand/ink")
    static let brandOnLight = Color("brand/onLight")
    static let brandSoft = Color("brand/soft")
    static let gradientTop = Color("brand/gradientTop")
    static let gradientBottom = Color("brand/gradientBottom")

    static let bgBase = Color("bg/base")
    static let surface = Color("bg/surface")
    static let surfaceMuted = Color("bg/surfaceMuted")
    static let separator = Color("bg/separator")

    static let textPrimary = Color("text/primary")
    static let textSecondary = Color("text/secondary")
    static let textTertiary = Color("text/tertiary")

    static let success = Color("state/success")
    static let successForeground = Color("state/successForeground")
    static let warning = Color("state/warning")
    static let warningForeground = Color("state/warningForeground")
    static let danger = Color("state/danger")
    static let dangerForeground = Color("state/dangerForeground")
    static let info = Color("state/info")
    static let infoForeground = Color("state/infoForeground")

    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [gradientTop, gradientBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var pageGradient: LinearGradient {
        LinearGradient(
            colors: [bgBase, surface],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
