import SetuIOSCore
import SwiftUI

struct AccountView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var email = ""
    @State private var password = ""
    @State private var captchaCode = ""
    @State private var captchaUuid = ""
    @State private var passkeyService = PasskeyAuthorizationService()
    @State private var passkeyMessage: String?
    @State private var passkeyLoading = false

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
                    TextField("验证码", text: $captchaCode)
                    TextField("验证码 UUID", text: $captchaUuid)
                    Button("登录") {
                        Task {
                            await environment.authSession.login(
                                email: email,
                                password: password,
                                captchaCode: captchaCode,
                                captchaUuid: captchaUuid
                            )
                        }
                    }
                    .disabled(email.isEmpty || password.isEmpty || captchaCode.isEmpty || captchaUuid.isEmpty)
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
                    }
                }
                .disabled(environment.authSession.isRefreshing)

                if let expireAt = environment.authSession.expireAt {
                    LabeledContent("过期时间", value: expireAt.formatted())
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
    }

    private func loginWithPasskey() async {
        passkeyLoading = true
        passkeyMessage = nil
        do {
            let options = try await environment.passkeyClient.beginAuthentication()
            let credential = try await passkeyService.assertCredential(options: options.publicKey.publicKey)
            let response = try await environment.passkeyClient.finishAuthentication(challengeID: options.challengeId, credential: credential)
            try environment.authSession.applyLoginResponse(response)
            passkeyMessage = "通行密钥登录成功"
        } catch {
            passkeyMessage = error.localizedDescription
        }
        passkeyLoading = false
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
