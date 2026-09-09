import SetuIOSCore
import SwiftUI
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif


enum AuthPalette {
    static let background = Color("auth/background")
    static let onAccent = Color("auth/onAccent")
}

struct AuthWelcomeBackdrop: View {
    var body: some View {
        AuthPalette.background.accessibilityHidden(true)
    }
}

struct AuthFormPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
    }
}

struct AuthPanelHeader: View {
    @ScaledMetric(relativeTo: .title2) private var titleSize = 24.0
    @ScaledMetric(relativeTo: .subheadline) private var subtitleSize = 13.0
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: titleSize, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(SetuColor.textPrimary)
            Text(subtitle)
                .font(.system(size: subtitleSize, weight: .regular))
                .foregroundStyle(SetuColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 10)
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

struct AuthPrimaryButtonLabel: View {
    @ScaledMetric(relativeTo: .body) private var textSize = 15.0
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.system(size: textSize, weight: .medium))
            .tracking(0.3)
            .foregroundStyle(AuthPalette.onAccent)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(SetuColor.brandPink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct AuthPrimaryProgressLabel: View {
    @ScaledMetric(relativeTo: .body) private var textSize = 15.0
    let title: String

    var body: some View {
        HStack(spacing: SetuSpacing.sm) {
            ProgressView().tint(AuthPalette.onAccent)
            Text(title)
                .font(.system(size: textSize, weight: .medium))
                .foregroundStyle(AuthPalette.onAccent)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(SetuColor.brandPink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .foregroundStyle(SetuColor.textPrimary)
                .padding(32)
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
