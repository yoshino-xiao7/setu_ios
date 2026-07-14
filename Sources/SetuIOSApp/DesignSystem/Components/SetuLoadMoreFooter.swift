import SwiftUI

enum SetuLoadMoreFooterState: Equatable {
    case idle
    case loading
    case failed(String)
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
                    failureLabel(message)
                    Spacer(minLength: SetuSpacing.sm)
                    retryButton
                }
                VStack(spacing: SetuSpacing.sm) {
                    failureLabel(message)
                    retryButton
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

    @ViewBuilder
    private var retryButton: some View {
        if let retry {
            Button("重试加载", action: retry)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .frame(minHeight: 44)
        }
    }
}
