import SwiftUI

enum SetuPillTone {
    case brand
    case success
    case warning
    case danger
    case info
    case muted

    var foreground: Color {
        switch self {
        case .brand: SetuColor.brandInk
        case .success: SetuColor.successForeground
        case .warning: SetuColor.warningForeground
        case .danger: SetuColor.dangerForeground
        case .info: SetuColor.infoForeground
        case .muted: SetuColor.textSecondary
        }
    }

    var fill: Color {
        switch self {
        case .brand: SetuColor.brandSoft
        case .success: SetuColor.success
        case .warning: SetuColor.warning
        case .danger: SetuColor.danger
        case .info: SetuColor.info
        case .muted: SetuColor.surfaceMuted
        }
    }
}

struct SetuPill: View {
    let text: String
    var systemImage: String?
    var tone: SetuPillTone = .brand

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, SetuSpacing.md)
        .padding(.vertical, SetuSpacing.xs)
        .background(tone.fill.opacity(0.18), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tone.foreground.opacity(0.20), lineWidth: 1)
        }
    }
}
