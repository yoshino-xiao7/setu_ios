import SetuIOSCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct AccountView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var email = ""
    @State private var password = ""
    @State private var loginCaptcha = AuthCaptchaState()
    @State private var registerEmail = ""
    @State private var registerPassword = ""
    @State private var registerCaptcha = AuthCaptchaState()
    @State private var recoveryEmail = ""
    @State private var recoveryCaptcha = AuthCaptchaState()
    @State private var resetToken = ""
    @State private var resetPassword = ""
    @State private var passkeyService = PasskeyAuthorizationService()
    @State private var passkeyMessage: String?
    @State private var authMessage: String?
    @State private var sessionMessage: String?
    @State private var sessionDiagnostics: MobileSessionDiagnostics?
    @State private var lastSessionConfirmation: Bool?
    @State private var passkeyLoading = false
    @State private var authActionLoading = false
    @State private var sessionActionLoading = false

    var body: some View {
        Form {
            if let user = environment.authSession.currentUser {
                Section("当前账号") {
                    LabeledContent("邮箱", value: user.email)
                    LabeledContent("角色", value: user.role == .admin ? "管理员" : "用户")
                    Button {
                        router.navigate(to: .profile)
                    } label: {
                        Label("个人资料", systemImage: "person.crop.circle")
                    }
                    Button {
                        router.navigate(to: .qqBinding)
                    } label: {
                        Label("QQ 绑定", systemImage: "link")
                    }
                    Button {
                        router.navigate(to: .security)
                    } label: {
                        Label("安全设置", systemImage: "lock")
                    }
                    Button {
                        router.navigate(to: .passkeys)
                    } label: {
                        Label("通行密钥", systemImage: "touchid")
                    }
                    Button {
                        router.navigate(to: .docs)
                    } label: {
                        Label("开发文档", systemImage: "doc.text")
                    }
                    Button {
                        router.navigate(to: .about)
                    } label: {
                        Label("关于本站", systemImage: "info.circle")
                    }
                    Button {
                        router.navigate(to: .privacy)
                    } label: {
                        Label("隐私政策", systemImage: "hand.raised")
                    }
                    Button("退出登录", role: .destructive) {
                        Task {
                            await environment.authSession.logout()
                            sessionMessage = "已退出登录"
                            updateSessionDiagnostics()
                        }
                    }
                }
            } else {
                Section("登录") {
                    TextField("邮箱", text: $email)
                        .textContentType(.username)
                        .modifier(EmailInputModifier())
                    SecureField("密码", text: $password)
                        .textContentType(.password)
                    CaptchaInputRow(
                        code: $loginCaptcha.code,
                        imageSource: loginCaptcha.imageSource,
                        isLoading: loginCaptcha.isLoading,
                        errorMessage: loginCaptcha.errorMessage
                    ) {
                        Task { await refreshCaptcha(.login) }
                    }
                    Button("登录") {
                        Task { await loginWithPassword() }
                    }
                    .disabled(email.isEmpty || password.isEmpty || loginCaptcha.code.isEmpty || loginCaptcha.uuid.isEmpty)
                    Button {
                        Task { await loginWithPasskey() }
                    } label: {
                        if passkeyLoading {
                            ProgressView()
                        } else {
                            Label("使用通行密钥登录", systemImage: "touchid")
                        }
                    }
                    .disabled(passkeyLoading)
                    if let passkeyMessage {
                        Text(passkeyMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let authMessage {
                        Text(authMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("注册账号") {
                    TextField("邮箱", text: $registerEmail)
                        .textContentType(.emailAddress)
                        .modifier(EmailInputModifier())
                    SecureField("密码", text: $registerPassword)
                        .textContentType(.newPassword)
                    CaptchaInputRow(
                        code: $registerCaptcha.code,
                        imageSource: registerCaptcha.imageSource,
                        isLoading: registerCaptcha.isLoading,
                        errorMessage: registerCaptcha.errorMessage
                    ) {
                        Task { await refreshCaptcha(.register) }
                    }
                    Button {
                        Task { await registerAccount() }
                    } label: {
                        if authActionLoading {
                            ProgressView()
                        } else {
                            Label("注册", systemImage: "person.badge.plus")
                        }
                    }
                    .disabled(authActionLoading || registerEmail.isEmpty || registerPassword.isEmpty || registerCaptcha.code.isEmpty || registerCaptcha.uuid.isEmpty)
                }

                Section("找回密码") {
                    TextField("邮箱", text: $recoveryEmail)
                        .textContentType(.emailAddress)
                        .modifier(EmailInputModifier())
                    CaptchaInputRow(
                        code: $recoveryCaptcha.code,
                        imageSource: recoveryCaptcha.imageSource,
                        isLoading: recoveryCaptcha.isLoading,
                        errorMessage: recoveryCaptcha.errorMessage
                    ) {
                        Task { await refreshCaptcha(.recovery) }
                    }
                    Button {
                        Task { await sendPasswordRecoveryEmail() }
                    } label: {
                        if authActionLoading {
                            ProgressView()
                        } else {
                            Label("发送重置邮件", systemImage: "envelope")
                        }
                    }
                    .disabled(authActionLoading || recoveryEmail.isEmpty || recoveryCaptcha.code.isEmpty || recoveryCaptcha.uuid.isEmpty)
                }

                Section("重置密码") {
                    TextField("邮件 Token", text: $resetToken)
                        .modifier(EmailInputModifier())
                    SecureField("新密码", text: $resetPassword)
                        .textContentType(.newPassword)
                    Button {
                        Task { await submitPasswordReset() }
                    } label: {
                        if authActionLoading {
                            ProgressView()
                        } else {
                            Label("重置密码", systemImage: "key")
                        }
                    }
                    .disabled(authActionLoading || resetToken.isEmpty || resetPassword.isEmpty)
                }
            }

            if let error = environment.authSession.lastError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            Section("移动端会话") {
                Button("刷新签名密钥") {
                    Task {
                        _ = await environment.authSession.refreshSignature()
                        updateSessionDiagnostics()
                    }
                }
                .disabled(environment.authSession.isRefreshing)

                Button {
                    updateSessionDiagnostics()
                } label: {
                    Label("检查会话状态", systemImage: "checkmark.shield")
                }

                Button {
                    copySessionDiagnostics()
                } label: {
                    Label("复制诊断摘要", systemImage: "doc.on.doc")
                }

                Button(role: .destructive) {
                    environment.authSession.resetLocalSession()
                    updateSessionDiagnostics()
                    sessionMessage = "本地会话已清理"
                } label: {
                    Label("清理本地会话", systemImage: "trash")
                }

                if environment.authSession.currentUser != nil {
                    Button {
                        Task { await confirmCurrentSession() }
                    } label: {
                        if sessionActionLoading {
                            ProgressView()
                        } else {
                            Label("确认当前会话", systemImage: "network")
                        }
                    }
                    .disabled(sessionActionLoading)
                }

                if let expireAt = environment.authSession.expireAt {
                    LabeledContent("过期时间", value: expireAt.formatted())
                }

                if let sessionDiagnostics {
                    LabeledContent("API 主机", value: sessionDiagnostics.apiHost)
                    LabeledContent("本地登录态", value: sessionDiagnostics.isSignedIn ? "存在" : "未登录")
                    LabeledContent("SID Cookie", value: sessionDiagnostics.hasSIDCookie ? "存在" : "缺失")
                    LabeledContent("Cookie 数量", value: "\(sessionDiagnostics.cookieCount)")
                    LabeledContent("签名密钥", value: sessionDiagnostics.hasSignSecret ? "存在" : "缺失")
                    LabeledContent("上次会话确认", value: sessionConfirmationText)
                }

                if let sessionMessage {
                    Text(sessionMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if environment.authSession.currentUser == nil {
                Section("帮助") {
                    Button {
                        router.navigate(to: .docs)
                    } label: {
                        Label("开发文档", systemImage: "doc.text")
                    }
                    Button {
                        router.navigate(to: .privacy)
                    } label: {
                        Label("隐私政策", systemImage: "hand.raised")
                    }
                }
            }
        }
        .navigationTitle("我的")
        .task {
            if environment.authSession.currentUser == nil {
                await refreshCaptchaIfNeeded(.login)
            }
            updateSessionDiagnostics()
        }
    }

    private func loginWithPassword() async {
        lastSessionConfirmation = nil
        await environment.authSession.login(
            email: email,
            password: password,
            captchaCode: loginCaptcha.code,
            captchaUuid: loginCaptcha.uuid
        )
        updateSessionDiagnostics()
        if environment.authSession.currentUser == nil {
            lastSessionConfirmation = false
            sessionMessage = "登录未建立有效会话，请查看下方状态"
            loginCaptcha.code = ""
            await refreshCaptcha(.login)
        } else {
            lastSessionConfirmation = true
            sessionMessage = "登录成功，会话已确认"
        }
    }

    private func loginWithPasskey() async {
        passkeyLoading = true
        lastSessionConfirmation = nil
        passkeyMessage = nil
        do {
            let options = try await environment.passkeyClient.beginAuthentication()
            let credential = try await passkeyService.assertCredential(options: options.publicKey.publicKey)
            let response = try await environment.passkeyClient.finishAuthentication(challengeID: options.challengeId, credential: credential)
            try await environment.authSession.acceptLoginResponse(response)
            updateSessionDiagnostics()
            lastSessionConfirmation = true
            passkeyMessage = "通行密钥登录成功"
            sessionMessage = "登录成功，会话已确认"
        } catch {
            passkeyMessage = error.localizedDescription
            updateSessionDiagnostics()
            lastSessionConfirmation = false
            sessionMessage = "通行密钥未建立有效会话，请查看下方状态"
        }
        passkeyLoading = false
    }

    private func registerAccount() async {
        authActionLoading = true
        authMessage = nil
        let success = await environment.authSession.register(
            email: registerEmail,
            password: registerPassword,
            captchaCode: registerCaptcha.code,
            captchaUuid: registerCaptcha.uuid
        )
        if success {
            authMessage = "注册成功，可以使用新账号登录"
            email = registerEmail
            password = registerPassword
            registerPassword = ""
        }
        registerCaptcha.code = ""
        await refreshCaptcha(.register)
        authActionLoading = false
    }

    private func sendPasswordRecoveryEmail() async {
        authActionLoading = true
        authMessage = nil
        let success = await environment.authSession.forgotPassword(
            email: recoveryEmail,
            captchaCode: recoveryCaptcha.code,
            captchaUuid: recoveryCaptcha.uuid
        )
        if success {
            authMessage = "重置邮件已发送，请打开邮件获取 Token"
        }
        recoveryCaptcha.code = ""
        await refreshCaptcha(.recovery)
        authActionLoading = false
    }

    private func submitPasswordReset() async {
        authActionLoading = true
        authMessage = nil
        let success = await environment.authSession.resetPassword(token: resetToken, newPassword: resetPassword)
        if success {
            authMessage = "密码已重置，可以使用新密码登录"
            resetToken = ""
            resetPassword = ""
        }
        authActionLoading = false
    }

    private func updateSessionDiagnostics() {
        sessionDiagnostics = environment.authSession.mobileSessionDiagnostics()
    }

    private func copySessionDiagnostics() {
        let diagnostics = environment.authSession.mobileSessionDiagnostics()
        sessionDiagnostics = diagnostics
        PlatformClipboard.copy(diagnosticsSummary(diagnostics))
        sessionMessage = "诊断摘要已复制"
    }

    private func diagnosticsSummary(_ diagnostics: MobileSessionDiagnostics) -> String {
        let expireAtText = diagnostics.expireAt?.formatted() ?? "-"
        return """
        Setu iOS Session Diagnostics
        API Host: \(diagnostics.apiHost)
        Signed In: \(diagnostics.isSignedIn ? "yes" : "no")
        SID Cookie: \(diagnostics.hasSIDCookie ? "present" : "missing")
        Cookie Count: \(diagnostics.cookieCount)
        Sign Secret: \(diagnostics.hasSignSecret ? "present" : "missing")
        Expire At: \(expireAtText)
        Last Session Confirmation: \(sessionConfirmationSummary)
        Last Auth Error: \(environment.authSession.lastError ?? "-")
        """
    }

    private func confirmCurrentSession() async {
        sessionActionLoading = true
        let confirmed = await environment.authSession.confirmAuthenticatedSession()
        lastSessionConfirmation = confirmed
        updateSessionDiagnostics()
        sessionMessage = confirmed ? "当前会话有效" : "当前会话无效，请重新登录"
        sessionActionLoading = false
    }

    private var sessionConfirmationText: String {
        switch lastSessionConfirmation {
        case .some(true):
            return "有效"
        case .some(false):
            return "无效"
        case .none:
            return "未确认"
        }
    }

    private var sessionConfirmationSummary: String {
        switch lastSessionConfirmation {
        case .some(true):
            return "valid"
        case .some(false):
            return "invalid"
        case .none:
            return "not checked"
        }
    }

    private func refreshCaptchaIfNeeded(_ kind: AuthCaptchaKind) async {
        if captchaState(for: kind).uuid.isEmpty {
            await refreshCaptcha(kind)
        }
    }

    private func refreshCaptcha(_ kind: AuthCaptchaKind) async {
        updateCaptcha(kind) { state in
            state.isLoading = true
            state.errorMessage = nil
        }
        do {
            let captcha = try await environment.authSession.fetchCaptcha()
            updateCaptcha(kind) { state in
                state.uuid = captcha.uuid
                state.imageSource = captcha.img
                state.isLoading = false
                state.errorMessage = nil
            }
        } catch {
            updateCaptcha(kind) { state in
                state.uuid = ""
                state.imageSource = nil
                state.isLoading = false
                state.errorMessage = "验证码加载失败"
            }
        }
    }

    private func captchaState(for kind: AuthCaptchaKind) -> AuthCaptchaState {
        switch kind {
        case .login:
            loginCaptcha
        case .register:
            registerCaptcha
        case .recovery:
            recoveryCaptcha
        }
    }

    private func updateCaptcha(_ kind: AuthCaptchaKind, mutate: (inout AuthCaptchaState) -> Void) {
        switch kind {
        case .login:
            mutate(&loginCaptcha)
        case .register:
            mutate(&registerCaptcha)
        case .recovery:
            mutate(&recoveryCaptcha)
        }
    }
}

private struct EmailInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
        #else
        content
        #endif
    }
}

private enum AuthCaptchaKind {
    case login
    case register
    case recovery
}

private struct AuthCaptchaState {
    var code = ""
    var uuid = ""
    var imageSource: String?
    var isLoading = false
    var errorMessage: String?
}

private struct CaptchaInputRow: View {
    @Binding var code: String
    let imageSource: String?
    let isLoading: Bool
    let errorMessage: String?
    let refresh: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("验证码", text: $code)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
            Button(action: refresh) {
                CaptchaImage(source: imageSource, isLoading: isLoading, errorMessage: errorMessage)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityLabel("刷新验证码")
        }
    }
}

private struct CaptchaImage: View {
    let source: String?
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(.secondary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.secondary.opacity(0.18), lineWidth: 1)
                )

            if isLoading {
                ProgressView()
            } else if let image = platformImage(from: source) {
                captchaImage(image)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            } else {
                Text(errorMessage ?? "点击加载")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
private typealias PlatformImage = UIImage
#elseif canImport(AppKit)
private typealias PlatformImage = NSImage
#endif
