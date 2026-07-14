import SwiftUI

enum SetuPermissionState: Equatable {
    case notDetermined
    case granted
    case denied

    var title: String {
        switch self {
        case .notDetermined: "尚未设置"
        case .granted: "已允许"
        case .denied: "已关闭"
        }
    }

    var systemImage: String {
        switch self {
        case .notDetermined: "questionmark.circle"
        case .granted: "checkmark.circle.fill"
        case .denied: "exclamationmark.triangle"
        }
    }

    var tone: SetuPillTone {
        switch self {
        case .notDetermined: .muted
        case .granted: .success
        case .denied: .warning
        }
    }
}

struct SetuPermissionPrompt: View {
    let title: String
    let message: String
    let systemImage: String
    let state: SetuPermissionState
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.md) {
            Label {
                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                    Text(title)
                        .font(SetuTypography.headline)
                        .foregroundStyle(SetuColor.textPrimary)
                    Text(message)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SetuColor.brandPink)
                    .frame(width: 32, height: 32)
            }

            if actionTitle != nil, action != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: SetuSpacing.md) {
                        statusPill
                        Spacer(minLength: SetuSpacing.sm)
                        actionButton
                    }
                    VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                        statusPill
                        actionButton
                    }
                }
            } else {
                statusPill
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var statusPill: some View {
        SetuPill(text: state.title, systemImage: state.systemImage, tone: state.tone)
    }

    @ViewBuilder
    private var actionButton: some View {
        if let actionTitle, let action {
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }
}
