import SetuIOSCore
import SwiftUI

#if os(iOS)
import UIKit
#endif

enum SetuFeedback: Hashable {
    case success(String)
    case error(String)
    case failure(UserFacingError)
    case info(String)
    case warning(String)

    static func warning(_ error: UserFacingError) -> Self { .failure(error) }

    static func error(_ error: UserFacingError) -> Self { .failure(error) }

    var userFacingError: UserFacingError? {
        if case .failure(let error) = self { return error }
        return nil
    }

    var message: String {
        switch self {
        case .failure(let error): error.message
        case .success(let message), .error(let message), .info(let message), .warning(let message):
            message
        }
    }

    var systemImage: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .error, .failure: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        }
    }

    var tone: SetuPillTone {
        switch self {
        case .success: .success
        case .error, .failure: .danger
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
        feedback = .failure(error)
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
            HStack(alignment: .firstTextBaseline, spacing: SetuSpacing.sm) {
                Image(systemName: feedback.systemImage)
                    .accessibilityHidden(true)
                Text(title ?? feedback.userFacingError?.title ?? feedback.message)
                    .font(SetuTypography.body.weight(title == nil ? .regular : .semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(feedback.tone.foreground)

            if title != nil || feedback.userFacingError != nil {
                Text(feedback.message)
                    .font(SetuTypography.body)
                    .foregroundStyle(feedback.tone.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = feedback.userFacingError, action == nil {
                SetuErrorRecoveryButton(error: error)
            } else if let actionTitle, let action {
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
            .accessibilityElement(children: action == nil && feedback.userFacingError == nil ? .combine : .contain)
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
