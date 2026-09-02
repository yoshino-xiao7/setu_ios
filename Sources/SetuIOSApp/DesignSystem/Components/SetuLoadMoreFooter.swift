import SetuIOSCore
import SwiftUI

enum SetuLoadMoreFooterState: Equatable {
    case idle
    case loading
    case failed(UserFacingError)

    static func failed(_ message: String) -> Self { .failed(UserFacingError(message: message)) }
    case complete(String)
}

struct SetuLoadMoreFooter: View {
    let state: SetuLoadMoreFooterState
    var retry: (() -> Void)?

    @ViewBuilder
    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView("正在加载更多")
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel("正在加载更多内容")
        case .failed(let message):
            ViewThatFits(in: .horizontal) {
                HStack(spacing: SetuSpacing.md) {
                    failureLabel(message.message)
                    Spacer(minLength: SetuSpacing.sm)
                    SetuErrorRecoveryButton(error: message, retry: retry)
                }
                VStack(spacing: SetuSpacing.sm) {
                    failureLabel(message.message)
                    SetuErrorRecoveryButton(error: message, retry: retry)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        case .complete(let message):
            Label(message, systemImage: "checkmark.circle")
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel(message)
        }
    }

    private func failureLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(SetuTypography.caption)
            .foregroundStyle(SetuColor.textSecondary)
            .multilineTextAlignment(.leading)
    }

}
