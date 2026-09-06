import SwiftUI

enum SetuTypography {
    static let display = Font.largeTitle.weight(.bold)
    static let title = Font.title3.weight(.semibold)
    static let headline = Font.headline
    static let body = Font.body
    static let caption = Font.footnote
    static let metric = Font.title2.weight(.semibold).monospacedDigit()
    static let numeric = Font.body.monospacedDigit()
    static let label = Font.caption.weight(.semibold)
}
