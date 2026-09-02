import SetuIOSCore
import SwiftUI
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif


struct AuthWelcomeBackdrop: View {
    var body: some View {
        SetuColor.pageGradient
            .overlay {
                Circle()
                    .fill(SetuColor.brandSoft.opacity(0.22))
                    .frame(width: 300, height: 300)
                    .blur(radius: 28)
                    .offset(x: 150, y: -260)
            }
            .overlay {
                Circle()
                    .fill(SetuColor.gradientBottom.opacity(0.12))
                    .frame(width: 260, height: 260)
                    .blur(radius: 36)
                    .offset(x: -150, y: 290)
            }
            .accessibilityHidden(true)
    }
}

struct AuthGlassPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(SetuColor.separator.opacity(0.9), lineWidth: 1)
        }
        .shadow(color: SetuColor.brandPink.opacity(0.16), radius: 28, x: 0, y: 18)
    }
}

struct AuthPanelHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title.weight(.bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [SetuColor.brandInk, SetuColor.brandPink.opacity(0.78)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SetuColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }
}

struct AuthTextInputRow: View {
    let systemImage: String
    let placeholder: LocalizedStringKey
    @Binding var text: String
    let focus: FocusState<AuthFocusField?>.Binding
    let field: AuthFocusField
    let accessibilityIdentifier: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(SetuColor.brandInk.opacity(0.72))
                .frame(width: 26)
            TextField(placeholder, text: $text)
                .font(.body)
                .focused(focus, equals: field)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .authInputStyle()
    }
}

struct AuthSecureInputRow: View {
    let systemImage: String
    let placeholder: LocalizedStringKey
    @Binding var text: String
    let focus: FocusState<AuthFocusField?>.Binding
    let field: AuthFocusField
    let accessibilityIdentifier: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(SetuColor.brandInk.opacity(0.72))
                .frame(width: 26)
            SecureField(placeholder, text: $text)
                .font(.body)
                .focused(focus, equals: field)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .authInputStyle()
    }
}

struct AuthGradientButtonLabel: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                LinearGradient(
                    colors: [
                        SetuColor.gradientTop,
                        SetuColor.gradientBottom
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .shadow(color: SetuColor.brandPink.opacity(0.26), radius: 14, x: 0, y: 8)
    }
}

struct AuthGradientProgressLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: SetuSpacing.sm) {
            ProgressView()
                .tint(.white)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(
            LinearGradient(
                colors: [SetuColor.info.opacity(0.70), SetuColor.brandPink.opacity(0.70)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

struct AuthSocialButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(SetuColor.surface.opacity(0.72))
                        .overlay {
                            Circle()
                                .stroke(SetuColor.separator.opacity(0.70), lineWidth: 1)
                        }
                    if isLoading {
                        ProgressView()
                            .tint(SetuColor.brandPink)
                    } else {
                        Image(systemName: systemImage)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(systemImage == "apple.logo" ? SetuColor.textPrimary : SetuColor.brandInk)
                    }
                }
                .frame(width: 62, height: 62)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SetuColor.brandInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func authInputStyle() -> some View {
        self
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(SetuColor.surface.opacity(0.68), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(SetuColor.brandSoft.opacity(0.28), lineWidth: 1)
            }
    }
}

struct AuthHeaderImage: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(authImageBackground)

            Image("AuthHeader")
                .resizable()
                .scaledToFill()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }

    private var authImageBackground: Color {
        #if os(iOS)
        SetuColor.surfaceMuted
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.secondary.opacity(0.12)
        #endif
    }

}

struct AuthCaptchaState {
    var code = ""
    var uuid = ""
    var imageSource: String?
    var isLoading = false
    var errorMessage: String?
}

struct CaptchaInputRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Binding var code: String
    let imageSource: String?
    let isLoading: Bool
    let errorMessage: String?
    let focus: FocusState<AuthFocusField?>.Binding
    let field: AuthFocusField
    let accessibilityIdentifier: String
    let refresh: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                    HStack(spacing: SetuSpacing.sm) {
                        fieldIcon
                        codeField
                    }
                    HStack(spacing: SetuSpacing.sm) {
                        Text("图片验证码")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SetuColor.textSecondary)
                        Spacer(minLength: 0)
                        refreshButton
                    }
                }
            } else {
                HStack(spacing: SetuSpacing.md) {
                    fieldIcon
                    codeField
                    Spacer(minLength: 0)
                    refreshButton
                }
            }
        }
        .authInputStyle()
    }

    private var fieldIcon: some View {
        Image(systemName: "number")
            .font(.title3)
            .foregroundStyle(SetuColor.brandInk.opacity(0.72))
            .frame(width: 26)
            .accessibilityHidden(true)
    }

    private var codeField: some View {
        TextField("验证码", text: $code)
            .font(.body)
            .focused(focus, equals: field)
            .accessibilityIdentifier(accessibilityIdentifier)
            #if os(iOS)
            .textInputAutocapitalization(.characters)
            #endif
    }

    private var refreshButton: some View {
        Button(action: refresh) {
            CaptchaImage(source: imageSource, isLoading: isLoading, errorMessage: errorMessage)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(captchaAccessibilityLabel)
        .accessibilityHint("图片验证码无法由旁白朗读；可改用 Apple 登录或通行密钥。")
    }

    private var captchaAccessibilityLabel: String {
        if isLoading { return "正在加载图片验证码" }
        if errorMessage != nil || imageSource == nil { return "图片验证码加载失败，轻点重试" }
        return "图片验证码，轻点更换"
    }
}

struct CaptchaImage: View {
    let source: String?
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(SetuColor.surfaceMuted.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(SetuColor.separator.opacity(0.9), lineWidth: 1)
                )

            if isLoading {
                ProgressView()
                    .tint(SetuColor.brandPink)
            } else if let image = platformImage(from: source) {
                captchaImage(image)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            } else {
                Text(errorMessage ?? "点击加载")
                    .font(.caption2)
                    .foregroundStyle(SetuColor.textSecondary)
            }
        }
        .frame(width: 132, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func captchaImage(_ image: PlatformImage) -> Image {
        #if canImport(UIKit)
        Image(uiImage: image)
        #elseif canImport(AppKit)
        Image(nsImage: image)
        #endif
    }

    private func platformImage(from source: String?) -> PlatformImage? {
        guard var value = source, !value.isEmpty else {
            return nil
        }
        if let commaIndex = value.firstIndex(of: ",") {
            value = String(value[value.index(after: commaIndex)...])
        }
        guard let data = Data(base64Encoded: value) else {
            return nil
        }
        return PlatformImage(data: data)
    }
}

#if canImport(UIKit)
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
typealias PlatformImage = NSImage
#endif
