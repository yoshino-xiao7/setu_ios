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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var environment: AppEnvironment
    @AppStorage("setu_admin_mode_enabled") private var adminModeEnabled = false
    @State private var qqSummary: LoadState<String> = .idle
    @State private var passkeySummary: LoadState<String> = .idle
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
    @State private var sessionFeedback: SetuFeedback?
    @State private var sessionDiagnostics: MobileSessionDiagnostics?
    @State private var lastSessionConfirmation: Bool?
    @State private var passkeyLoading = false
    @State private var appleLoading = false
    @State private var authActionLoading = false
    @State private var sessionActionLoading = false
    @State private var preserveAuthMessageOnNextPageChange = false
    @State private var authPage: AuthPage
    @FocusState private var focusedField: AuthFocusField?

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
        SetuBoard {
            Section {
                SetuCard(padding: SetuSpacing.xl) {
                    AccountProfileCard(user: user) {
                        router.navigate(to: .profile)
                    }
                }
            }

            SetuSectionHeader(title: "账号与安全")
            SetuBento(items: accountItems(user), span: { _ in .small }) { item in
                SetuBentoTile(title: item.title, subtitle: item.value, systemImage: item.systemImage) {
                    if let route = item.route { router.navigate(to: route) }
                }
            }

            SetuSectionHeader(title: "帮助与信息")
            SetuBento(items: helpItems, span: { _ in .small }) { item in
                SetuBentoTile(title: item.title, subtitle: item.value, systemImage: item.systemImage) {
                    if let route = item.route { router.navigate(to: route) }
                }
            }

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
            }

            Section {
                Button(role: .destructive) {
                    Task {
                        adminModeEnabled = false
                        await environment.logout()
                        sessionFeedback = .success("已退出登录")
                        updateSessionDiagnostics()
                    }
                } label: {
                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }

            if let error = environment.authSession.lastError {
                Section {
                    SetuFeedbackBanner(feedback: .error(error))
                }
            }

            if environment.authSession.currentUser?.role == .admin {
                SetuCard {
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
                            sessionFeedback = .success("本地会话已清理")
                        } label: {
                            Label("清理本地会话", systemImage: "trash")
                        }

                        Button {
                            Task { await confirmCurrentSession() }
                        } label: {
                            if sessionActionLoading {
                                HStack(spacing: SetuSpacing.sm) {
                                    ProgressView()
                                        .tint(SetuColor.brandPink)
                                    Text("正在确认会话")
                                }
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

                        if let sessionFeedback {
                            SetuFeedbackBanner(feedback: sessionFeedback)
                        }
                    }
                }
            }
        }
        .navigationTitle("我的")
        .task(id: user.id) { await loadAccountSummaries() }
        .refreshable { await loadAccountSummaries() }
    }

    private func accountItems(_ user: CurrentUser) -> [AccountSurfaceItem] {
        [
            .init(title: "个人资料", value: user.nickname?.isEmpty == false ? user.nickname! : user.email, systemImage: "person.crop.circle", route: .profile),
            .init(title: "QQ 绑定", value: summaryText(qqSummary), systemImage: "link", route: .qqBinding),
            .init(title: "修改密码", value: "当前账号已登录", systemImage: "lock", route: .security),
            .init(title: "通行密钥", value: summaryText(passkeySummary), systemImage: "touchid", route: .passkeys)
        ]
    }

    private func summaryText(_ state: LoadState<String>) -> String {
        switch state {
        case .idle, .loading: "正在同步当前状态"
        case .failed: "状态暂未同步，进入详情查看"
        case .loaded(let value): value
        }
    }

    private func loadAccountSummaries() async {
        qqSummary = .loading
        passkeySummary = .loading
        async let qq = fetchQqSummary()
        async let passkeys = fetchPasskeySummary()
        (qqSummary, passkeySummary) = await (qq, passkeys)
    }

    private func fetchQqSummary() async -> LoadState<String> {
        do {
            let binding = try await environment.userProfileClient.getQqBinding()
            guard let number = binding.qqNumber, !number.isEmpty else { return .loaded("尚未绑定 QQ") }
            return .loaded("已绑定 QQ · \(number) · 通知\(binding.isEnabled ? "已启用" : "未启用")")
        } catch {
            return .failed(UserFacingErrorMapper.map(error))
        }
    }

    private func fetchPasskeySummary() async -> LoadState<String> {
        do {
            let items = try await environment.passkeyClient.list()
            return .loaded(items.isEmpty ? "尚未开通" : "已开通 \(items.count) 个")
        } catch {
            return .failed(UserFacingErrorMapper.map(error))
        }
    }

    private var helpItems: [AccountSurfaceItem] {
        [
            .init(title: "使用帮助", value: "图库、音乐与创作说明", systemImage: "questionmark.circle", route: .docs),
            .init(title: "隐私政策", value: "数据与账号安全", systemImage: "hand.raised", route: .privacy),
            .init(title: "服务条款", value: "使用规则与内容说明", systemImage: "doc.text.magnifyingglass", route: .terms),
            .init(title: "关于雪涼云", value: "产品介绍与版本信息", systemImage: "info.circle", route: .about)
        ]
    }

    private var unauthenticatedAuthScreen: some View {
        ZStack {
            AuthWelcomeBackdrop()
                .ignoresSafeArea()

            SetuBoard(inset: SetuSpacing.xl) {
                Group {
                    if authPage == .landing {
                        AuthWelcomeView(
                            environment: environment,
                            isAppleLoading: appleLoading,
                            sessionFeedback: environment.authSession.lastError.map(SetuFeedback.error),
                            onAppleRequest: prepareAppleRequest,
                            onAppleCompletion: completeAppleLogin,
                            onEmailLogin: { showAuthPage(.login) },
                            onRegister: { showAuthPage(.register) },
                            onPasskey: { Task { await loginWithPasskey() } },
                            onPrivacy: { router.navigate(to: .privacy) },
                            onTerms: { router.navigate(to: .terms) }
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        SetuCard(padding: SetuSpacing.xl) {
                            VStack(spacing: SetuSpacing.xl) {
                                AuthHeaderImage()
                                unauthenticatedContent
                            }
                        }
                        .frame(maxWidth: 520)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SetuSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .padding(.vertical, SetuSpacing.sm)
        }
        .navigationTitle("")
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
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

            SetuPrimaryButton {
                Task { await loginWithPassword() }
            } label: {
                if authActionLoading {
                    Label("正在登录", systemImage: "hourglass")
                } else {
                    Text("登录")
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

            SetuPrimaryButton {
                Task { await registerAccount() }
            } label: {
                if authActionLoading {
                    Label("正在注册", systemImage: "hourglass")
                } else {
                    Text("注册")
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

            SetuPrimaryButton {
                Task { await sendPasswordRecoveryEmail() }
            } label: {
                if authActionLoading {
                    Label("正在发送重置邮件", systemImage: "hourglass")
                } else {
                    Text("发送重置邮件")
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

            SetuPrimaryButton {
                Task { await submitPasswordReset() }
            } label: {
                if authActionLoading {
                    Label("正在重置密码", systemImage: "hourglass")
                } else {
                    Text("重置密码")
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
        lastSessionConfirmation = nil
        defer { authActionLoading = false }
        await environment.authSession.login(
            email: email,
            password: password,
            captchaCode: loginCaptcha.code,
            captchaUuid: loginCaptcha.uuid
        )
        updateSessionDiagnostics()
        if environment.authSession.currentUser == nil {
            lastSessionConfirmation = false
            authFeedback = .error("登录失败，请重试")
            loginCaptcha.code = ""
            await refreshCaptcha(.login)
        } else {
            lastSessionConfirmation = true
            sessionFeedback = .success("登录成功")
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
        lastSessionConfirmation = nil
        authFeedback = nil
        passkeyActionFeedback = nil
        sessionFeedback = nil
        environment.authSession.lastError = nil
        defer { passkeyLoading = false }
        do {
            let options = try await environment.passkeyClient.beginAuthentication()
            let credential = try await passkeyService.assertCredential(options: options.publicKey.publicKey)
            let response = try await environment.passkeyClient.finishAuthentication(challengeID: options.challengeId, credential: credential)
            try await environment.authSession.acceptLoginResponse(response)
            updateSessionDiagnostics()
            lastSessionConfirmation = true
            passkeyActionFeedback = .success("通行密钥登录成功")
            sessionFeedback = .success("登录成功")
        } catch {
            let message = PasskeyAuthorizationService.userMessage(for: error)
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                passkeyActionFeedback = .info(message)
            } else {
                passkeyActionFeedback = .error(message)
            }
            updateSessionDiagnostics()
            lastSessionConfirmation = false
            sessionFeedback = .error("通行密钥登录失败，请重试")
        }
    }

    private func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        appleLoading = true
        authFeedback = nil
        lastSessionConfirmation = nil
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
            updateSessionDiagnostics()
            lastSessionConfirmation = true
            authFeedback = .success("Apple 登录成功")
            sessionFeedback = .success("登录成功")
        } catch {
            let message = AppleAuthorizationService.userMessage(for: error)
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                authFeedback = .info(message)
            } else {
                authFeedback = .error(message)
            }
            updateSessionDiagnostics()
            lastSessionConfirmation = false
            sessionFeedback = .error("Apple 登录失败，请重试")
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

    private func updateSessionDiagnostics() {
        sessionDiagnostics = environment.authSession.mobileSessionDiagnostics()
    }

    private func copySessionDiagnostics() {
        let diagnostics = environment.authSession.mobileSessionDiagnostics()
        sessionDiagnostics = diagnostics
        PlatformClipboard.copy(diagnosticsSummary(diagnostics))
        sessionFeedback = .success("诊断摘要已复制")
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
        let outcome = await environment.authSession.confirmSession()
        lastSessionConfirmation = outcome != .invalidated
        updateSessionDiagnostics()
        switch outcome {
        case .confirmed:
            sessionFeedback = .success("当前登录状态有效")
        case .retainedUnverified:
            sessionFeedback = .error("暂时无法确认（网络原因），会话仍保留，请稍后重试")
        case .invalidated:
            sessionFeedback = .error("当前登录状态无效，请重新登录")
        }
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
