import SetuIOSCore
import SwiftUI
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum AuthFocusField: Hashable {
    case loginEmail, loginPassword, loginCaptcha
    case registerEmail, registerPassword, registerConfirmation, registerCaptcha
    case recoveryEmail, recoveryCaptcha
    case resetToken, resetPassword
}

struct AccountView: View {
    @Environment(RouterPath.self) private var router
    @Environment(\.loginConfirmationActive) private var loginConfirmed
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var appleAuthorizationService = AppleAuthorizationService()
    @State private var passkeyActionFeedback: SetuFeedback?
    @State private var authFeedback: SetuFeedback?
    @State private var passkeyLoading = false
    @State private var appleLoading = false
    @State private var authActionLoading = false
    @State private var preserveAuthMessageOnNextPageChange = false
    @State private var authPage: AuthPage
    @FocusState private var focusedField: AuthFocusField?

    init(environment: AppEnvironment, initialAuthPage: AuthPage = .landing) {
        self.environment = environment
        _authPage = State(initialValue: initialAuthPage)
    }

    var body: some View {
        Group {
            if let user = environment.authSession.currentUser, !loginConfirmed {
                authenticatedContent(user: user)
            } else {
                unauthenticatedAuthScreen
            }
        }
        .overlay(alignment: .bottom) {
            if loginConfirmed, authPage != .login {
                Label("登录成功", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(SetuColor.brandPink)
                    .padding()
                    .background(AuthPalette.background, in: Capsule())
                    .padding(.bottom, 24)
            }
        }
        .task {
            if environment.authSession.currentUser == nil, let captchaKind = authPage.captchaKind {
                await refreshCaptchaIfNeeded(captchaKind)
            }
        }
        .onChange(of: authPage) {
            focusedField = nil
            if preserveAuthMessageOnNextPageChange {
                preserveAuthMessageOnNextPageChange = false
            } else {
                authFeedback = nil
            }
            passkeyActionFeedback = nil
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
            #if os(iOS)
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedField = nil }
            }
            #endif
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
                        SetuSectionHeader(title: "通用设置")
                        SetuNavigationRow(title: "音乐缓存", subtitle: "存储空间与自动缓存", systemImage: "internaldrive") {
                            router.navigate(to: .musicCacheSettings)
                        }
                        .accessibilityIdentifier("account.music-cache")
                        SetuNavigationRow(title: "图片显示", subtitle: "薄雾效果与首页推荐展示", systemImage: "eye.slash") {
                            router.navigate(to: .imageDisplaySettings)
                        }
                        .accessibilityIdentifier("account.image-display")
                        if user.role == .admin {
                            SetuNavigationRow(title: "故障排查", subtitle: "检查会话与登录状态", systemImage: "wrench.and.screwdriver") {
                                router.navigate(to: .sessionDiagnostics)
                            }
                            .accessibilityIdentifier("account.diagnostics")
                        }
                    }
                }
            }
            .setuListRow()

            Section {
                SetuCard {
                    VStack(spacing: SetuSpacing.lg) {
                        SetuSectionHeader(title: "帮助与信息")
                        SetuNavigationRow(title: "使用帮助", subtitle: "查看图片、音乐与创作说明", systemImage: "questionmark.circle") {
                            router.navigate(to: .docs)
                        }
                        SetuNavigationRow(title: "隐私政策", subtitle: "了解数据与账号安全", systemImage: "hand.raised") {
                            router.navigate(to: .privacy)
                        }
                        SetuNavigationRow(title: "服务条款", subtitle: "了解使用规则与内容说明", systemImage: "doc.text.magnifyingglass") {
                            router.navigate(to: .terms)
                        }
                        SetuNavigationRow(title: "关于亦可", subtitle: "产品介绍与版本信息", systemImage: "info.circle") {
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
                        await environment.logout()
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
                    SetuFeedbackBanner(feedback: .error(error))
                }
                .setuListRow()
            }


        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("我的")
    }

    private var unauthenticatedAuthScreen: some View {
        ZStack {
            AuthWelcomeBackdrop()
                .ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView {
                    Group {
                        if authPage == .landing {
                            AuthWelcomeView(
                                isAppleLoading: appleLoading,
                                sessionFeedback: passkeyActionFeedback ?? environment.authSession.lastError.map(SetuFeedback.error),
                                onAppleRequest: prepareAppleRequest,
                                onAppleCompletion: completeAppleLogin,
                                onEmailLogin: { showAuthPage(.login) },
                                onRegister: { showAuthPage(.register) },
                                onPasskey: { Task { await loginWithPasskey() } },
                                onPrivacy: { router.navigate(to: .privacy) },
                                onTerms: { router.navigate(to: .terms) },
                                minimumHeight: max(0, geometry.size.height - 32),
                                isPasskeyLoading: passkeyLoading
                            )
                            .transition(.opacity)
                        } else {
                            AuthFormPanel {
                                unauthenticatedContent
                            }
                            .frame(maxWidth: 390)
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.horizontal, 30)

        }
        .navigationTitle("")
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(authPage == .landing ? .hidden : .visible, for: .navigationBar)
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
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: authPage)
    }

    private var unauthenticatedHero: some View {
        Section {
            VStack(alignment: .center, spacing: 16) {
                AuthHeaderImage()
                VStack(alignment: .center, spacing: 6) {
                    Text("亦可登录")
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
            AuthTextInputRow(systemImage: "person", placeholder: "请输入邮箱", text: $email, focus: $focusedField, field: .loginEmail, accessibilityIdentifier: "auth.login.email")
                .textContentType(.username)
                .modifier(EmailInputModifier())
                .onSubmit { focusedField = .loginPassword }
            AuthSecureInputRow(systemImage: "lock", placeholder: "请输入密码", text: $password, focus: $focusedField, field: .loginPassword, accessibilityIdentifier: "auth.login.password")
                .textContentType(.password)
                .onSubmit { focusedField = .loginCaptcha }
            CaptchaInputRow(
                code: $loginCaptcha.code,
                imageSource: loginCaptcha.imageSource,
                isLoading: loginCaptcha.isLoading,
                errorMessage: loginCaptcha.errorMessage,
                focus: $focusedField,
                field: .loginCaptcha,
                accessibilityIdentifier: "auth.login.captcha"
            ) {
                Task { await refreshCaptcha(.login) }
            }

            HStack {
                Button {
                    showAuthPage(.register)
                } label: {
                    AuthLinkButtonLabel("注册新账号")
                }
                Spacer()
                Button {
                    showAuthPage(.recovery)
                } label: {
                    AuthLinkButtonLabel("忘记密码？")
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(SetuColor.brandInk)

            Button {
                Task { await loginWithPassword() }
            } label: {
                if loginConfirmed {
                    AuthPrimaryButtonLabel(title: "✓ 登录成功")
                } else if authActionLoading {
                    AuthPrimaryProgressLabel(title: "正在登录")
                } else {
                    AuthPrimaryButtonLabel(title: "登录")
                }
            }
            .buttonStyle(.plain)
            .disabled(authActionLoading || email.isEmpty || password.isEmpty || loginCaptcha.code.isEmpty || loginCaptcha.uuid.isEmpty)
            .opacity(authActionLoading || email.isEmpty || password.isEmpty || loginCaptcha.code.isEmpty || loginCaptcha.uuid.isEmpty ? 0.55 : 1)

            authMessageView
            socialLoginContent
        }
        .frame(maxWidth: .infinity)
    }

    private var registerContent: some View {
        VStack(spacing: 18) {
            AuthPanelHeader(title: "创建账号", subtitle: "邮箱注册后即可同步你的内容")
            AuthTextInputRow(systemImage: "envelope", placeholder: "请输入邮箱", text: $registerEmail, focus: $focusedField, field: .registerEmail, accessibilityIdentifier: "auth.register.email")
                .textContentType(.emailAddress)
                .modifier(EmailInputModifier())
                .onSubmit { focusedField = .registerPassword }
            AuthSecureInputRow(systemImage: "lock", placeholder: "请输入密码", text: $registerPassword, focus: $focusedField, field: .registerPassword, accessibilityIdentifier: "auth.register.password")
                .textContentType(.newPassword)
                .onSubmit { focusedField = .registerConfirmation }
            AuthSecureInputRow(systemImage: "checkmark.shield", placeholder: "请重复密码", text: $registerPasswordConfirmation, focus: $focusedField, field: .registerConfirmation, accessibilityIdentifier: "auth.register.confirmation")
                .textContentType(.newPassword)
                .onSubmit { focusedField = .registerCaptcha }
            CaptchaInputRow(
                code: $registerCaptcha.code,
                imageSource: registerCaptcha.imageSource,
                isLoading: registerCaptcha.isLoading,
                errorMessage: registerCaptcha.errorMessage,
                focus: $focusedField,
                field: .registerCaptcha,
                accessibilityIdentifier: "auth.register.captcha"
            ) {
                Task { await refreshCaptcha(.register) }
            }

            Button {
                Task { await registerAccount() }
            } label: {
                if loginConfirmed {
                    AuthPrimaryButtonLabel(title: "✓ 登录成功")
                } else if authActionLoading {
                    AuthPrimaryProgressLabel(title: "正在注册")
                } else {
                    AuthPrimaryButtonLabel(title: "注册")
                }
            }
            .buttonStyle(.plain)
            .disabled(registerButtonDisabled)
            .opacity(registerButtonDisabled ? 0.55 : 1)

            Text("密码长度需为 8 到 72 个字符，两次输入需一致。")
                .font(.footnote)
                .foregroundStyle(SetuColor.textSecondary)
            authMessageView
            Button {
                showAuthPage(.login)
            } label: {
                AuthLinkButtonLabel("已有账号？返回登录")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(SetuColor.brandInk)
        }
        .frame(maxWidth: .infinity)
    }

    private var recoveryContent: some View {
        VStack(spacing: 18) {
            AuthPanelHeader(title: "找回密码", subtitle: "验证邮箱后发送重置邮件")
            AuthTextInputRow(systemImage: "envelope", placeholder: "请输入邮箱", text: $recoveryEmail, focus: $focusedField, field: .recoveryEmail, accessibilityIdentifier: "auth.recovery.email")
                .textContentType(.emailAddress)
                .modifier(EmailInputModifier())
                .onSubmit { focusedField = .recoveryCaptcha }
            CaptchaInputRow(
                code: $recoveryCaptcha.code,
                imageSource: recoveryCaptcha.imageSource,
                isLoading: recoveryCaptcha.isLoading,
                errorMessage: recoveryCaptcha.errorMessage,
                focus: $focusedField,
                field: .recoveryCaptcha,
                accessibilityIdentifier: "auth.recovery.captcha"
            ) {
                Task { await refreshCaptcha(.recovery) }
            }

            Button {
                Task { await sendPasswordRecoveryEmail() }
            } label: {
                if loginConfirmed {
                    AuthPrimaryButtonLabel(title: "✓ 登录成功")
                } else if authActionLoading {
                    AuthPrimaryProgressLabel(title: "正在发送重置邮件")
                } else {
                    AuthPrimaryButtonLabel(title: "发送重置邮件")
                }
            }
            .buttonStyle(.plain)
            .disabled(authActionLoading || recoveryEmail.isEmpty || recoveryCaptcha.code.isEmpty || recoveryCaptcha.uuid.isEmpty)
            .opacity(authActionLoading || recoveryEmail.isEmpty || recoveryCaptcha.code.isEmpty || recoveryCaptcha.uuid.isEmpty ? 0.55 : 1)

            authMessageView
            Button {
                showAuthPage(.login)
            } label: {
                AuthLinkButtonLabel("想起密码了？返回登录")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(SetuColor.brandInk)
        }
        .frame(maxWidth: .infinity)
    }

    private var passwordResetContent: some View {
        VStack(spacing: 18) {
            AuthPanelHeader(title: "重置密码", subtitle: "输入邮件里的重置码和新密码")
            AuthTextInputRow(systemImage: "number", placeholder: "邮件重置码", text: $resetToken, focus: $focusedField, field: .resetToken, accessibilityIdentifier: "auth.reset.token")
                .textContentType(.oneTimeCode)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .onSubmit { focusedField = .resetPassword }
            AuthSecureInputRow(systemImage: "key", placeholder: "新密码", text: $resetPassword, focus: $focusedField, field: .resetPassword, accessibilityIdentifier: "auth.reset.password")
                .textContentType(.newPassword)

            Button {
                Task { await submitPasswordReset() }
            } label: {
                if loginConfirmed {
                    AuthPrimaryButtonLabel(title: "✓ 登录成功")
                } else if authActionLoading {
                    AuthPrimaryProgressLabel(title: "正在重置密码")
                } else {
                    AuthPrimaryButtonLabel(title: "重置密码")
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
                Button {
                    showAuthPage(.recovery)
                } label: {
                    AuthLinkButtonLabel("重新发送重置邮件")
                }
                Spacer()
                Button {
                    showAuthPage(.login)
                } label: {
                    AuthLinkButtonLabel("返回登录")
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(SetuColor.brandInk)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var authMessageView: some View {
        if let authFeedback {
            SetuFeedbackBanner(feedback: authFeedback)
        }
        if let passkeyActionFeedback {
            SetuFeedbackBanner(feedback: passkeyActionFeedback)
        }
        if let error = environment.authSession.lastError {
            SetuFeedbackBanner(feedback: .error(error))
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

            VStack(spacing: SetuSpacing.md) {
                SetuAppleSignInButton(
                    isLoading: appleLoading,
                    onRequest: prepareAppleRequest,
                    onCompletion: completeAppleLogin
                )
                .disabled(appleLoading)
                AuthSocialButton(title: "通行密钥", systemImage: "touchid", isLoading: passkeyLoading) {
                    Task { await loginWithPasskey() }
                }
                .disabled(passkeyLoading)
            }
        }
    }

    private func loginWithPassword() async {
        authActionLoading = true
        defer { authActionLoading = false }
        await environment.authSession.login(
            email: email,
            password: password,
            captchaCode: loginCaptcha.code,
            captchaUuid: loginCaptcha.uuid
        )
        if environment.authSession.currentUser == nil {
            authFeedback = .error("登录失败，请重试")
            loginCaptcha.code = ""
            await refreshCaptcha(.login)
        }
    }

    private func showAuthPage(_ page: AuthPage) {
        let update = {
            prepareAuthState(for: page)
            authPage = page
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(.snappy(duration: 0.28), update)
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
        authFeedback = nil
        passkeyActionFeedback = nil
        environment.authSession.lastError = nil
        defer { passkeyLoading = false }
        do {
            let options = try await environment.passkeyClient.beginAuthentication()
            let credential = try await passkeyService.assertCredential(options: options.publicKey.publicKey)
            let response = try await environment.passkeyClient.finishAuthentication(challengeID: options.challengeId, credential: credential)
            try await environment.authSession.acceptLoginResponse(response)
            passkeyActionFeedback = .success("通行密钥登录成功")
        } catch {
            let message = PasskeyAuthorizationService.userMessage(for: error)
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                passkeyActionFeedback = .info(message)
            } else {
                passkeyActionFeedback = .error(message)
            }
        }
    }

    private func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        appleLoading = true
        authFeedback = nil
        appleAuthorizationService.configure(request)
    }

    private func completeAppleLogin(_ result: Result<ASAuthorization, Error>) {
        Task { await loginWithApple(result) }
    }

    private func loginWithApple(_ result: Result<ASAuthorization, Error>) async {
        defer { appleLoading = false }
        do {
            let credential = try appleAuthorizationService.credential(from: result)
            let response = try await environment.appleAuthClient.login(
                identityToken: credential.identityToken,
                nonce: credential.nonce
            )
            try await environment.authSession.acceptLoginResponse(response)
            authFeedback = .success("Apple 登录成功")
        } catch {
            let message = AppleAuthorizationService.userMessage(for: error)
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                authFeedback = .info(message)
            } else {
                authFeedback = .error(message)
            }
        }
    }

    private func registerAccount() async {
        guard registerPassword == registerPasswordConfirmation else {
            authFeedback = .warning("两次输入的密码不一致")
            return
        }
        guard registerPassword.count >= 8, registerPassword.count <= 72 else {
            authFeedback = .warning("密码长度需为 8 到 72 个字符")
            return
        }

        authActionLoading = true
        authFeedback = nil
        let success = await environment.authSession.register(
            email: registerEmail,
            password: registerPassword,
            captchaCode: registerCaptcha.code,
            captchaUuid: registerCaptcha.uuid
        )
        if success {
            authFeedback = .success("注册成功，可以使用新账号登录")
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
        authFeedback = nil
        let success = await environment.authSession.forgotPassword(
            email: recoveryEmail,
            captchaCode: recoveryCaptcha.code,
            captchaUuid: recoveryCaptcha.uuid
        )
        if success {
            authFeedback = .success("重置邮件已发送，请打开邮件获取重置码")
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
        authFeedback = nil
        let success = await environment.authSession.resetPassword(token: resetToken, newPassword: resetPassword)
        if success {
            authFeedback = .success("密码已重置，可以使用新密码登录")
            resetToken = ""
            resetPassword = ""
            showAuthPage(.login)
        }
        authActionLoading = false
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

enum AuthPage {
    case landing
    case login
    case register
    case recovery
    case passwordReset

    var title: String {
        switch self {
        case .landing: "亦可登录"
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
