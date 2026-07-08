import SetuIOSCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct AccountView: View {
    @Environment(RouterPath.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    @AppStorage("setu_admin_mode_enabled") private var adminModeEnabled = false
    @State private var email = ""
    @State private var password = ""
    @State private var loginCaptcha = AuthCaptchaState()
    @State private var registerEmail = ""
    @State private var registerPassword = ""
    @State private var registerPasswordConfirmation = ""
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
    @State private var preserveAuthMessageOnNextPageChange = false
    @State private var authPage: AuthPage

    init(environment: AppEnvironment, initialAuthPage: AuthPage = .landing) {
        self.environment = environment
        _authPage = State(initialValue: initialAuthPage)
    }

    var body: some View {
        Group {
            if let user = environment.authSession.currentUser {
                authenticatedContent(user: user)
            } else {
                unauthenticatedAuthScreen
            }
        }
        .task {
            if environment.authSession.currentUser == nil, let captchaKind = authPage.captchaKind {
                await refreshCaptchaIfNeeded(captchaKind)
            }
            updateSessionDiagnostics()
        }
        .onChange(of: authPage) {
            if preserveAuthMessageOnNextPageChange {
                preserveAuthMessageOnNextPageChange = false
            } else {
                authMessage = nil
            }
            passkeyMessage = nil
            if let captchaKind = authPage.captchaKind {
                Task { await refreshCaptchaIfNeeded(captchaKind) }
            }
        }
        .toolbar {
            if environment.authSession.currentUser == nil, authPage != .landing {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showAuthPage(.landing)
                    } label: {
                        Label("返回", systemImage: "chevron.left")
                    }
                }
            }
        }
    }

    private func authenticatedContent(user: CurrentUser) -> some View {
        List {
            Section {
                SetuCard(padding: SetuSpacing.xl) {
                    AccountProfileCard(user: user) {
                        router.navigate(to: .profile)
                    }
                }
            }
            .setuListRow()

            Section {
                SetuCard {
                    VStack(spacing: SetuSpacing.lg) {
                        SetuSectionHeader(title: "账号与安全")
                        SetuNavigationRow(title: "个人资料", subtitle: "头像、昵称和账号信息", systemImage: "person.crop.circle") {
                            router.navigate(to: .profile)
                        }
                        SetuNavigationRow(title: "QQ 绑定", subtitle: "连接 QQ 账号与通知", systemImage: "link") {
                            router.navigate(to: .qqBinding)
                        }
                        SetuNavigationRow(title: "修改密码", subtitle: "更新账号登录密码", systemImage: "lock") {
                            router.navigate(to: .security)
                        }
                        SetuNavigationRow(title: "通行密钥", subtitle: "Face ID、Touch ID 或设备密码登录", systemImage: "touchid") {
                            router.navigate(to: .passkeys)
                        }
                    }
                }
            }
            .setuListRow()

            Section {
                SetuCard {
                    VStack(spacing: SetuSpacing.lg) {
                        SetuSectionHeader(title: "帮助与信息")
                        SetuNavigationRow(title: "开发文档", subtitle: "查看 API 与移动端说明", systemImage: "doc.text") {
                            router.navigate(to: .docs)
                        }
                        SetuNavigationRow(title: "隐私政策", subtitle: "了解数据与账号安全", systemImage: "hand.raised") {
                            router.navigate(to: .privacy)
                        }
                        SetuNavigationRow(title: "关于本站", subtitle: "雪涼云项目与版本信息", systemImage: "info.circle") {
                            router.navigate(to: .about)
                        }
                    }
                }
            }
            .setuListRow()

            if user.role == .admin {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "管理员入口")
                            Toggle("管理员模式", isOn: $adminModeEnabled)
                                .tint(SetuColor.brandPink)
                            if adminModeEnabled {
                                SetuPrimaryButton {
                                    router.navigate(to: .admin)
                                } label: {
                                    Label("进入管理员界面", systemImage: "switch.2")
                                }
                            }
                        }
                    }
                }
                .setuListRow()
            }

            Section {
                Button(role: .destructive) {
                    Task {
                        adminModeEnabled = false
                        await environment.authSession.logout()
                        sessionMessage = "已退出登录"
                        updateSessionDiagnostics()
                    }
                } label: {
                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .setuListRow()

            if let error = environment.authSession.lastError {
                Section {
                    SetuPill(text: error, systemImage: "exclamationmark.triangle", tone: .danger)
                }
                .setuListRow()
            }

            if environment.authSession.currentUser?.role == .admin {
                Section("故障排查") {
                    DisclosureGroup("会话与登录状态") {
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

                        Button {
                            Task { await confirmCurrentSession() }
                        } label: {
                            if sessionActionLoading {
                                ProgressView()
                                    .tint(SetuColor.brandPink)
                            } else {
                                Label("确认当前会话", systemImage: "network")
                            }
                        }
                        .disabled(sessionActionLoading)

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
                                .foregroundStyle(SetuColor.textSecondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("我的")
    }

    private var unauthenticatedAuthScreen: some View {
        GeometryReader { proxy in
            ZStack {
                AuthBackgroundImage()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                if authPage == .landing {
                    VStack {
                        Spacer()
                        Button {
                            showAuthPage(.login)
                        } label: {
                            AuthGradientButtonLabel(title: "立即登录")
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 34)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    let panelWidth = min(520, max(0, proxy.size.width - 48))

                    ZStack {
                        AuthGlassPanel {
                            unauthenticatedContent
                        }
                        .frame(width: panelWidth)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        #if os(iOS)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        #endif
        .navigationTitle("")
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
    }

    @ViewBuilder
    private var unauthenticatedContent: some View {
        Group {
            switch authPage {
            case .landing:
                EmptyView()
            case .login:
                loginContent
            case .register:
                registerContent
            case .recovery:
                recoveryContent
            case .passwordReset:
                passwordResetContent
            }
        }
        .id(authPage)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .animation(.snappy(duration: 0.28), value: authPage)
    }

    private var unauthenticatedHero: some View {
        Section {
            VStack(alignment: .center, spacing: 16) {
                AuthHeaderImage()
                VStack(alignment: .center, spacing: 6) {
                    Text("雪涼云登录")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Text("登录后继续创作、刷图、听歌和管理你的内容。")
                        .font(.subheadline)
                        .foregroundStyle(SetuColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var loginOptionsContent: some View {
        EmptyView()
    }

    private var loginContent: some View {
        VStack(spacing: 18) {
            AuthPanelHeader(title: "欢迎回来", subtitle: "登录后即可体验全部功能")
            AuthTextInputRow(systemImage: "person", placeholder: "请输入邮箱", text: $email)
                .textContentType(.username)
                .modifier(EmailInputModifier())
            AuthSecureInputRow(systemImage: "lock", placeholder: "请输入密码", text: $password)
                .textContentType(.password)
            CaptchaInputRow(
                code: $loginCaptcha.code,
                imageSource: loginCaptcha.imageSource,
                isLoading: loginCaptcha.isLoading,
                errorMessage: loginCaptcha.errorMessage
            ) {
                Task { await refreshCaptcha(.login) }
            }

            HStack {
                Button("注册新账号") {
                    showAuthPage(.register)
                }
                Spacer()
                Button("忘记密码？") {
                    showAuthPage(.recovery)
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(SetuColor.brandInk)

            Button {
                Task { await loginWithPassword() }
            } label: {
                AuthGradientButtonLabel(title: "登录")
            }
            .buttonStyle(.plain)
            .disabled(email.isEmpty || password.isEmpty || loginCaptcha.code.isEmpty || loginCaptcha.uuid.isEmpty)
            .opacity(email.isEmpty || password.isEmpty || loginCaptcha.code.isEmpty || loginCaptcha.uuid.isEmpty ? 0.55 : 1)

            authMessageView
            socialLoginContent
        }
        .frame(maxWidth: .infinity)
    }

    private var registerContent: some View {
        VStack(spacing: 18) {
            AuthPanelHeader(title: "创建账号", subtitle: "邮箱注册后即可同步你的内容")
            AuthTextInputRow(systemImage: "envelope", placeholder: "请输入邮箱", text: $registerEmail)
                .textContentType(.emailAddress)
                .modifier(EmailInputModifier())
            AuthSecureInputRow(systemImage: "lock", placeholder: "请输入密码", text: $registerPassword)
                .textContentType(.newPassword)
            AuthSecureInputRow(systemImage: "checkmark.shield", placeholder: "请重复密码", text: $registerPasswordConfirmation)
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
                    AuthGradientProgressLabel()
                } else {
                    AuthGradientButtonLabel(title: "注册")
                }
            }
            .buttonStyle(.plain)
            .disabled(registerButtonDisabled)
            .opacity(registerButtonDisabled ? 0.55 : 1)

            Text("密码长度需为 8 到 72 个字符，两次输入需一致。")
                .font(.footnote)
                .foregroundStyle(SetuColor.textSecondary)
            authMessageView
            Button("已有账号？返回登录") {
                showAuthPage(.login)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(SetuColor.brandInk)
        }
        .frame(maxWidth: .infinity)
    }

    private var recoveryContent: some View {
        VStack(spacing: 18) {
            AuthPanelHeader(title: "找回密码", subtitle: "验证邮箱后发送重置邮件")
            AuthTextInputRow(systemImage: "envelope", placeholder: "请输入邮箱", text: $recoveryEmail)
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
                    AuthGradientProgressLabel()
                } else {
                    AuthGradientButtonLabel(title: "发送重置邮件")
                }
            }
            .buttonStyle(.plain)
            .disabled(authActionLoading || recoveryEmail.isEmpty || recoveryCaptcha.code.isEmpty || recoveryCaptcha.uuid.isEmpty)
            .opacity(authActionLoading || recoveryEmail.isEmpty || recoveryCaptcha.code.isEmpty || recoveryCaptcha.uuid.isEmpty ? 0.55 : 1)

            authMessageView
            Button("想起密码了？返回登录") {
                showAuthPage(.login)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(SetuColor.brandInk)
        }
        .frame(maxWidth: .infinity)
    }

    private var passwordResetContent: some View {
        VStack(spacing: 18) {
            AuthPanelHeader(title: "重置密码", subtitle: "输入邮件里的重置码和新密码")
            AuthTextInputRow(systemImage: "number", placeholder: "邮件重置码", text: $resetToken)
                .textContentType(.oneTimeCode)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            AuthSecureInputRow(systemImage: "key", placeholder: "新密码", text: $resetPassword)
                .textContentType(.newPassword)

            Button {
                Task { await submitPasswordReset() }
            } label: {
                if authActionLoading {
                    AuthGradientProgressLabel()
                } else {
                    AuthGradientButtonLabel(title: "重置密码")
                }
            }
            .buttonStyle(.plain)
            .disabled(authActionLoading || resetToken.isEmpty || resetPassword.count < 8)
            .opacity(authActionLoading || resetToken.isEmpty || resetPassword.count < 8 ? 0.55 : 1)

            Text("新密码长度需为 8 到 72 个字符。")
                .font(.footnote)
                .foregroundStyle(SetuColor.textSecondary)
            authMessageView

            HStack {
                Button("重新发送重置邮件") {
                    showAuthPage(.recovery)
                }
                Spacer()
                Button("返回登录") {
                    showAuthPage(.login)
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(SetuColor.brandInk)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var authMessageView: some View {
        if let authMessage {
            Text(authMessage)
                .font(.footnote)
                .foregroundStyle(SetuColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        if let passkeyMessage {
            Text(passkeyMessage)
                .font(.footnote)
                .foregroundStyle(SetuColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        if let error = environment.authSession.lastError {
            Text(error)
                .font(.footnote)
                .foregroundStyle(SetuColor.danger)
                .multilineTextAlignment(.center)
        }
    }

    private var socialLoginContent: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(SetuColor.separator.opacity(0.9))
                    .frame(height: 1)
                Text("或者")
                    .font(.footnote)
                    .foregroundStyle(SetuColor.textSecondary)
                Rectangle()
                    .fill(SetuColor.separator.opacity(0.9))
                    .frame(height: 1)
            }

            HStack(spacing: 18) {
                AuthSocialButton(title: "Apple", systemImage: "apple.logo") {
                    authMessage = "Apple 账号登录需要后端完成 Apple 身份令牌校验接口后启用。"
                }
                AuthSocialButton(title: "通行密钥", systemImage: "touchid", isLoading: passkeyLoading) {
                    Task { await loginWithPasskey() }
                }
                .disabled(passkeyLoading)
            }
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
            authMessage = "登录失败，请重试"
            loginCaptcha.code = ""
            await refreshCaptcha(.login)
        } else {
            lastSessionConfirmation = true
            sessionMessage = "登录成功"
        }
    }

    private func showAuthPage(_ page: AuthPage) {
        withAnimation(.snappy(duration: 0.28)) {
            prepareAuthState(for: page)
            authPage = page
        }
    }

    private func prepareAuthState(for page: AuthPage) {
        switch page {
        case .register:
            recoveryCaptcha.code = ""
            resetToken = ""
            resetPassword = ""
        case .recovery:
            registerPassword = ""
            registerPasswordConfirmation = ""
            resetToken = ""
            resetPassword = ""
        case .login, .landing:
            registerPassword = ""
            registerPasswordConfirmation = ""
            recoveryCaptcha.code = ""
            resetToken = ""
            resetPassword = ""
        case .passwordReset:
            registerPassword = ""
            registerPasswordConfirmation = ""
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
            sessionMessage = "登录成功"
        } catch {
            passkeyMessage = PasskeyAuthorizationService.userMessage(for: error)
            updateSessionDiagnostics()
            lastSessionConfirmation = false
            sessionMessage = "通行密钥登录失败，请重试"
        }
        passkeyLoading = false
    }

    private func registerAccount() async {
        guard registerPassword == registerPasswordConfirmation else {
            authMessage = "两次输入的密码不一致"
            return
        }
        guard registerPassword.count >= 8, registerPassword.count <= 72 else {
            authMessage = "密码长度需为 8 到 72 个字符"
            return
        }

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
            registerPassword = ""
            registerPasswordConfirmation = ""
            preserveAuthMessageOnNextPageChange = true
            showAuthPage(.login)
        }
        registerCaptcha.code = ""
        if !success {
            await refreshCaptcha(.register)
        }
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
            authMessage = "重置邮件已发送，请打开邮件获取重置码"
            preserveAuthMessageOnNextPageChange = true
            showAuthPage(.passwordReset)
        }
        recoveryCaptcha.code = ""
        if !success {
            await refreshCaptcha(.recovery)
        }
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
            showAuthPage(.login)
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
        sessionMessage = confirmed ? "当前登录状态有效" : "当前登录状态无效，请重新登录"
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

    private var registerButtonDisabled: Bool {
        authActionLoading
            || registerEmail.isEmpty
            || registerPassword.count < 8
            || registerPassword.count > 72
            || registerPassword != registerPasswordConfirmation
            || registerCaptcha.code.isEmpty
            || registerCaptcha.uuid.isEmpty
    }
}

private struct AccountProfileCard: View {
    let user: CurrentUser
    let onEditProfile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                AccountAvatarView(urlString: user.avatarUrl, name: displayName)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(displayName)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                        Text(roleTitle)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(roleColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(roleColor)
                    }
                    Text(user.email)
                        .font(.footnote)
                        .foregroundStyle(SetuColor.textSecondary)
                        .lineLimit(1)
                    if user.lastLoginIp?.isEmpty == false {
                        Text("最近登录已记录")
                            .font(.caption)
                            .foregroundStyle(SetuColor.textTertiary)
                            .lineLimit(1)
                    }
                }
            }

            Button(action: onEditProfile) {
                Label("完善个人资料", systemImage: "person.crop.circle.badge.checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
    }

    private var displayName: String {
        let trimmed = user.nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? user.email : trimmed
    }

    private var roleTitle: String {
        user.role == .admin ? "管理员" : "普通用户"
    }

    private var roleColor: Color {
        user.role == .admin ? SetuColor.warning : SetuColor.brandInk
    }
}

private struct AccountAvatarView: View {
    let urlString: String?
    let name: String

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 62, height: 62)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Circle()
            .fill(SetuColor.brandSoft.opacity(0.18))
            .overlay {
                Text(String(name.prefix(1)).uppercased())
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(SetuColor.brandInk)
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

private struct AuthButtonLabel: View {
    let title: LocalizedStringKey
    let systemImage: String?

    init(_ title: LocalizedStringKey, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 24)
    }
}

private struct AuthButtonProgressLabel: View {
    var body: some View {
        HStack {
            Spacer(minLength: 0)
            ProgressView()
                .tint(SetuColor.brandPink)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 24)
    }
}

private enum AuthCaptchaKind {
    case login
    case register
    case recovery
}

enum AuthPage {
    case landing
    case login
    case register
    case recovery
    case passwordReset

    var title: String {
        switch self {
        case .landing: "雪涼云登录"
        case .login: "邮箱登录"
        case .register: "注册账号"
        case .recovery: "找回密码"
        case .passwordReset: "重置密码"
        }
    }

    fileprivate var captchaKind: AuthCaptchaKind? {
        switch self {
        case .landing: nil
        case .login: .login
        case .register: .register
        case .recovery: .recovery
        case .passwordReset: nil
        }
    }
}

private struct AuthBackgroundImage: View {
    var body: some View {
        Image("AuthBackground")
            .resizable()
            .scaledToFill()
            .overlay {
                LinearGradient(
                    colors: [
                        SetuColor.surface.opacity(0.02),
                        SetuColor.surface.opacity(0.12),
                        SetuColor.brandPink.opacity(0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        .clear,
                        SetuColor.bgBase.opacity(0.58),
                        SetuColor.bgBase.opacity(0.82)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 260)
            }
            .accessibilityHidden(true)
    }
}

private struct AuthGlassPanel<Content: View>: View {
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

private struct AuthPanelHeader: View {
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

private struct AuthTextInputRow: View {
    let systemImage: String
    let placeholder: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(SetuColor.brandInk.opacity(0.72))
                .frame(width: 26)
            TextField(placeholder, text: $text)
                .font(.body)
        }
        .authInputStyle()
    }
}

private struct AuthSecureInputRow: View {
    let systemImage: String
    let placeholder: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(SetuColor.brandInk.opacity(0.72))
                .frame(width: 26)
            SecureField(placeholder, text: $text)
                .font(.body)
        }
        .authInputStyle()
    }
}

private struct AuthGradientButtonLabel: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                LinearGradient(
                    colors: [
                        SetuColor.info,
                        SetuColor.brandPink,
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

private struct AuthGradientProgressLabel: View {
    var body: some View {
        HStack {
            ProgressView()
                .tint(.white)
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

private struct AuthSocialButton: View {
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

private extension View {
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

private struct AuthHeaderImage: View {
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
            Image(systemName: "number")
                .font(.title3)
                .foregroundStyle(SetuColor.brandInk.opacity(0.72))
                .frame(width: 26)
            TextField("验证码", text: $code)
                .font(.body)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
            Spacer(minLength: 0)
            Button(action: refresh) {
                CaptchaImage(source: imageSource, isLoading: isLoading, errorMessage: errorMessage)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityLabel("刷新验证码")
        }
        .authInputStyle()
    }
}

private struct CaptchaImage: View {
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
private typealias PlatformImage = UIImage
#elseif canImport(AppKit)
private typealias PlatformImage = NSImage
#endif
