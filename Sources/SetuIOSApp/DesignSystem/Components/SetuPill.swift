import SwiftUI

enum SetuPillTone {
    case brand
    case success
    case warning
    case danger
    case info
    case muted

    var color: Color {
        switch self {
        case .brand: SetuColor.brandInk
        case .success: SetuColor.success
        case .warning: SetuColor.warning
        case .danger: SetuColor.danger
        case .info: SetuColor.info
        case .muted: SetuColor.textSecondary
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
        .foregroundStyle(tone.color)
        .padding(.horizontal, SetuSpacing.md)
        .padding(.vertical, SetuSpacing.xs)
        .background(tone.color.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tone.color.opacity(0.18), lineWidth: 1)
        }
    }
}
