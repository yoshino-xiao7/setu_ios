import SwiftUI

#if os(iOS)
import UIKit
#endif

enum SetuFeedback: Hashable {
    case success(String)
    case error(String)
    case info(String)
    case warning(String)

    var message: String {
        switch self {
        case .success(let message), .error(let message), .info(let message), .warning(let message):
            message
        }
    }

    var systemImage: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        }
    }

    var tone: SetuPillTone {
        switch self {
        case .success: .success
        case .error: .danger
        case .info: .info
        case .warning: .warning
        }
    }
}

struct SetuFeedbackBanner: View {
    let feedback: SetuFeedback
    var title: String?
    var actionTitle: String?
    var action: (() -> Void)?

    init(
        feedback: SetuFeedback,
        title: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.feedback = feedback
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    init(
        error: UserFacingError,
        onAction: ((UserFacingErrorAction) -> Void)? = nil
    ) {
        feedback = .error(error.message)
        title = error.title
        if let errorAction = error.action, let onAction {
            actionTitle = errorAction.buttonTitle
            action = { onAction(errorAction) }
        } else {
            actionTitle = nil
            action = nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            Label(title ?? feedback.message, systemImage: feedback.systemImage)
                .font(SetuTypography.body.weight(title == nil ? .regular : .semibold))
                .foregroundStyle(feedback.tone.foreground)
                .multilineTextAlignment(.leading)

            if title != nil {
                Text(feedback.message)
                    .font(SetuTypography.body)
                    .foregroundStyle(feedback.tone.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(feedback.tone.foreground)
            }
        }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, SetuSpacing.lg)
            .padding(.vertical, SetuSpacing.sm)
            .background(
                feedback.tone.fill.opacity(0.14),
                in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous)
                    .stroke(feedback.tone.foreground.opacity(0.22), lineWidth: 1)
            }
            .accessibilityElement(children: action == nil ? .combine : .contain)
            .task(id: feedback) {
                #if os(iOS)
                UIAccessibility.post(notification: .announcement, argument: announcementMessage)
                #endif
            }
    }

    private var announcementMessage: String {
        [title, feedback.message]
            .compactMap { $0 }
            .joined(separator: "。")
    }
}
