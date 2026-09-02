import AuthenticationServices
import SwiftUI
import SetuIOSCore

struct AuthWelcomeView: View {
    @Bindable var environment: AppEnvironment
    @State private var dailyExample: SetuImageItem?
    @State private var preview: UserImagePreviewItem?
    let isAppleLoading: Bool
    let sessionFeedback: SetuFeedback?
    let onAppleRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onAppleCompletion: (Result<ASAuthorization, Error>) -> Void
    let onEmailLogin: () -> Void
    let onRegister: () -> Void
    let onPasskey: () -> Void
    let onPrivacy: () -> Void
    let onTerms: () -> Void

    var body: some View {
        VStack(spacing: SetuSpacing.lg) {

            VStack(spacing: SetuSpacing.lg) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(SetuColor.brandInk, SetuColor.brandSoft)
                    .accessibilityHidden(true)

                VStack(spacing: SetuSpacing.sm) {
                    Text("把灵感变成作品")
                        .font(.largeTitle.bold())
                        .foregroundStyle(SetuColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("auth.welcome.title")

                    Text("AI 绘画、高清图片与音乐，都在雪涼云")
                        .font(.title3)
                        .foregroundStyle(SetuColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("auth.welcome.subtitle")
                }
            }

            if let dailyExample {
                DailyExampleCard(item: dailyExample) {
                    preview = UserImagePreviewItem(image: dailyExample)
                }
                .frame(maxWidth: 520)
            }

            if let sessionFeedback {
                SetuFeedbackBanner(feedback: sessionFeedback)
                    .frame(maxWidth: 520)
            }

            VStack(spacing: SetuSpacing.md) {
                SetuAppleSignInButton(
                    isLoading: isAppleLoading,
                    onRequest: onAppleRequest,
                    onCompletion: onAppleCompletion
                )
                .disabled(isAppleLoading)
                .accessibilityIdentifier("auth.welcome.apple")

                Button(action: onEmailLogin) {
                    Label("使用邮箱登录", systemImage: "envelope")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .tint(SetuColor.brandInk)
                .accessibilityIdentifier("auth.welcome.email")

                Button(action: onRegister) {
                    Text("第一次来？创建账号")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SetuColor.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("auth.welcome.register")

                Button(action: onPasskey) {
                    Label("使用通行密钥", systemImage: "touchid")
                        .foregroundStyle(SetuColor.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .disabled(isAppleLoading)
            }
            .frame(maxWidth: 520)

            VStack(spacing: SetuSpacing.md) {
                Text("继续即表示你同意以下内容")
                    .font(.footnote)
                    .foregroundStyle(SetuColor.textSecondary)
                HStack(spacing: SetuSpacing.lg) {
                    Button(action: onPrivacy) {
                        Text("隐私政策")
                            .foregroundStyle(SetuColor.textPrimary)
                            .frame(minWidth: 96, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("auth.welcome.privacy")
                    Button(action: onTerms) {
                        Text("服务条款")
                            .foregroundStyle(SetuColor.textPrimary)
                            .frame(minWidth: 96, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("auth.welcome.terms")
                }
                .font(.footnote.weight(.semibold))
                .frame(minHeight: 44)

                Label("你的创作、收藏和歌单会安全同步", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(SetuColor.textTertiary)
            }

            Spacer(minLength: SetuSpacing.xl)
        }
        .frame(maxWidth: .infinity)
        .task { dailyExample = try? await environment.publicBlogClient.dailySetu() }
        .sheet(item: $preview) { UserImagePreviewSheet(item: $0) }
    }
}

struct SetuAppleSignInButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let isLoading: Bool
    let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        ZStack {
            appleButton
                .opacity(isLoading ? 0 : 1)
                .allowsHitTesting(!isLoading)

            if isLoading {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white : Color.black)
                    .overlay {
                        ProgressView()
                            .tint(colorScheme == .dark ? .black : .white)
                    }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(isLoading ? "正在使用 Apple 登录" : "使用 Apple 登录")
        .accessibilityValue(isLoading ? "处理中" : "")
    }

    @ViewBuilder
    private var appleButton: some View {
        if colorScheme == .dark {
            SignInWithAppleButton(.continue, onRequest: onRequest, onCompletion: onCompletion)
                .signInWithAppleButtonStyle(.white)
        } else {
            SignInWithAppleButton(.continue, onRequest: onRequest, onCompletion: onCompletion)
                .signInWithAppleButtonStyle(.black)
        }
    }
}

#Preview("欢迎页 · 浅色") {
    AuthWelcomeView(
        environment: SetuPreviewEnvironment.make(),
        isAppleLoading: false,
        sessionFeedback: nil,
        onAppleRequest: { _ in },
        onAppleCompletion: { _ in },
        onEmailLogin: {},
        onRegister: {},
        onPasskey: {},
        onPrivacy: {},
        onTerms: {}
    )
    .padding()
    .background(SetuColor.pageGradient)
    .preferredColorScheme(.light)
}

#Preview("欢迎页 · 深色 · 大字") {
    AuthWelcomeView(
        environment: SetuPreviewEnvironment.make(),
        isAppleLoading: false,
        sessionFeedback: .error("登录已过期，请重新登录，完成后会返回之前的页面。"),
        onAppleRequest: { _ in },
        onAppleCompletion: { _ in },
        onEmailLogin: {},
        onRegister: {},
        onPasskey: {},
        onPrivacy: {},
        onTerms: {}
    )
    .padding()
    .background(SetuColor.pageGradient)
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility3)
}
