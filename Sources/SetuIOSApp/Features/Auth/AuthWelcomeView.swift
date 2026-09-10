import AuthenticationServices
import SwiftUI
import SetuIOSCore

struct AuthWelcomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.brandSplashActive) private var brandSplashActive
    @ScaledMetric(relativeTo: .title) private var titleSize = 27.0
    @ScaledMetric(relativeTo: .subheadline) private var subtitleSize = 13.0
    @ScaledMetric(relativeTo: .footnote) private var initialsSize = 14.0
    @ScaledMetric(relativeTo: .caption) private var legalSize = 12.0

    let isAppleLoading: Bool
    let sessionFeedback: SetuFeedback?
    let onAppleRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onAppleCompletion: (Result<ASAuthorization, Error>) -> Void
    let onEmailLogin: () -> Void
    let onRegister: () -> Void
    let onPasskey: () -> Void
    let onPrivacy: () -> Void
    let onTerms: () -> Void
    var onBrowse: (() -> Void)? = nil
    var minimumHeight: CGFloat = 0
    var isPasskeyLoading = false

    var body: some View {
        VStack(spacing: 0) {
            brand
                .padding(.top, dynamicTypeSize.isAccessibilitySize ? 24 : 64)

            VStack(spacing: 12) {
                Button(action: onEmailLogin) {
                    AuthPrimaryButtonLabel(title: "使用邮箱登录")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("auth.welcome.email")

                SetuAppleSignInButton(
                    isLoading: isAppleLoading,
                    onRequest: onAppleRequest,
                    onCompletion: onAppleCompletion
                )
                .accessibilityIdentifier("auth.welcome.apple")

                secondaryActions
                    .padding(.top, 4)
                if let onBrowse {
                    Button(action: onBrowse) {
                        Text("先浏览更多")
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: subtitleSize, weight: .regular))
                    .tracking(0.4)
                    .foregroundStyle(SetuColor.textSecondary)
                    .accessibilityIdentifier("auth.welcome.browse")
                }
            }
            .disabled(isAppleLoading || isPasskeyLoading)
            .padding(.top, dynamicTypeSize.isAccessibilitySize ? 32 : 64)

            if let sessionFeedback {
                SetuFeedbackBanner(feedback: sessionFeedback)
                    .padding(.top, SetuSpacing.md)
            }

            Spacer(minLength: 32)
            legalLinks
                .padding(.bottom, 8)
        }
        .frame(maxWidth: 390, minHeight: minimumHeight)
        .frame(maxWidth: .infinity)
    }

    private var brand: some View {
        VStack(spacing: 0) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 66, height: 58)
                .foregroundStyle(SetuColor.textPrimary)
                .opacity(brandSplashActive ? 0 : 1)
                .anchorPreference(key: WelcomeLogoAnchorKey.self, value: .bounds) { EntryAnchors(logo: $0) }
                .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("亦可")
                    .font(.system(size: titleSize, weight: .medium))
                    .tracking(2)
                Text("YK")
                    .font(.system(size: initialsSize, weight: .regular))
                    .tracking(1.5)
                    .foregroundStyle(SetuColor.textSecondary)
            }
            .foregroundStyle(SetuColor.textPrimary)
            .padding(.top, 22)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("亦可 YK")
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("auth.welcome.title")

            Text("图片、AI 创作与音乐")
                .font(.system(size: subtitleSize, weight: .regular))
                .tracking(0.65)
                .foregroundStyle(SetuColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 9)
                .accessibilityIdentifier("auth.welcome.subtitle")
        }
    }

    private var secondaryActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(HStackLayout(spacing: 20))
        return layout {
            Button(action: onRegister) {
                Text("注册账号")
                    .frame(minWidth: 80, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("auth.welcome.register")
            if !dynamicTypeSize.isAccessibilitySize {
                Rectangle()
                    .fill(SetuColor.separator)
                    .frame(width: 1, height: 12)
                    .accessibilityHidden(true)
            }
            Button(action: onPasskey) {
                HStack(spacing: 6) {
                    if isPasskeyLoading { ProgressView().tint(SetuColor.brandPink) }
                    Text(isPasskeyLoading ? "正在验证" : "通行密钥")
                }
                .frame(minWidth: 80, minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("auth.welcome.passkey")
        }
        .buttonStyle(.plain)
        .font(.system(size: subtitleSize, weight: .regular))
        .tracking(0.4)
        .foregroundStyle(SetuColor.textSecondary)
    }

    private var legalLinks: some View {
        VStack(spacing: 0) {
            Text("继续即表示你同意")
            HStack(spacing: 6) {
                Button(action: onPrivacy) {
                    Text("隐私政策")
                        .frame(minWidth: 80, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("auth.welcome.privacy")
                Text("与")
                Button(action: onTerms) {
                    Text("服务条款")
                        .frame(minWidth: 80, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("auth.welcome.terms")
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: legalSize, weight: .regular))
        .foregroundStyle(SetuColor.textSecondary)
        .multilineTextAlignment(.center)
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
                    .fill(Color.white)
                    .overlay {
                        ProgressView()
                            .tint(.black)
                    }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
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
                .signInWithAppleButtonStyle(.whiteOutline)
        }
    }
}

#Preview("欢迎页 · 浅色") {
    AuthWelcomeView(
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
    .background(AuthPalette.background)
    .preferredColorScheme(.light)
}

#Preview("欢迎页 · 深色 · 大字") {
    AuthWelcomeView(
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
    .background(AuthPalette.background)
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility3)
}
