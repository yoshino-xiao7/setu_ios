import SetuIOSCore
import SwiftUI

struct SetuEmptyState: View {
    let title: String
    var message: String?
    var systemImage: String = "sparkles"
    var isLoading = false
    var actionTitle: String?
    var action: (() -> Void)?
    var userFacingError: UserFacingError?

    var body: some View {
        VStack(spacing: SetuSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: SetuRadius.lg, style: .continuous)
                    .fill(SetuColor.brandSoft.opacity(0.2))
                    .frame(width: 64, height: 64)
                if isLoading {
                    ProgressView()
                        .tint(SetuColor.brandPink)
                } else {
                    Image(systemName: systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(SetuColor.brandPink)
                }
            }
            .accessibilityHidden(true)

            VStack(spacing: SetuSpacing.xs) {
                Text(title)
                    .font(SetuTypography.headline)
                    .foregroundStyle(SetuColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let userFacingError {
                SetuErrorRecoveryButton(error: userFacingError, retry: action)
            } else if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .tint(SetuColor.brandPink)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(SetuSpacing.xl)
        .accessibilityElement(children: action == nil && userFacingError == nil ? .combine : .contain)
    }
}

extension SetuEmptyState {
    init(error: UserFacingError, retry: (() -> Void)? = nil) {
        self.init(title: error.title, message: error.message, systemImage: "exclamationmark.triangle", action: retry, userFacingError: error)
    }

    init(title: String, message: UserFacingError?, systemImage: String = "sparkles", isLoading: Bool = false, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        if let message {
            self.init(error: message, retry: action)
        } else {
            self.init(title: title, systemImage: systemImage, isLoading: isLoading, actionTitle: actionTitle, action: action)
        }
    }

    init(title: String, message: UserFacingError, systemImage: String = "sparkles", isLoading: Bool = false, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.init(error: message, retry: action)
    }
}

struct SetuStateView<Value, Content: View, EmptyContent: View>: View {
    let state: LoadState<Value>
    var loadingTitle: String = "正在加载"
    var loadingImage: String = "sparkles"
    var failureTitle: String = "加载失败"
    var failureImage: String = "exclamationmark.triangle"
    var failureActionTitle: String?
    var failureAction: (() -> Void)?
    let isEmpty: (Value) -> Bool
    @ViewBuilder let emptyContent: () -> EmptyContent
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            SetuEmptyState(title: loadingTitle, systemImage: loadingImage, isLoading: true)
        case .failed(let message):
            SetuEmptyState(
                title: failureTitle,
                message: message,
                systemImage: failureImage,
                actionTitle: failureActionTitle,
                action: failureAction
            )
        case .loaded(let value):
            if isEmpty(value) {
                emptyContent()
            } else {
                content(value)
            }
        }
    }
}

extension SetuStateView where EmptyContent == SetuEmptyState {
    init(
        state: LoadState<Value>,
        loadingTitle: String = "正在加载",
        loadingImage: String = "sparkles",
        failureTitle: String = "加载失败",
        failureImage: String = "exclamationmark.triangle",
        failureActionTitle: String? = nil,
        failureAction: (() -> Void)? = nil,
        emptyTitle: String,
        emptyMessage: String? = nil,
        emptyImage: String = "sparkles",
        isEmpty: @escaping (Value) -> Bool,
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.state = state
        self.loadingTitle = loadingTitle
        self.loadingImage = loadingImage
        self.failureTitle = failureTitle
        self.failureImage = failureImage
        self.failureActionTitle = failureActionTitle
        self.failureAction = failureAction
        self.isEmpty = isEmpty
        self.emptyContent = {
            SetuEmptyState(title: emptyTitle, message: emptyMessage, systemImage: emptyImage)
        }
        self.content = content
    }
}
