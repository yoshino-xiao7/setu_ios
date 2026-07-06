import SetuIOSCore
import SwiftUI

struct AccountView: View {
    @Bindable var environment: AppEnvironment
    @State private var email = ""
    @State private var password = ""
    @State private var captchaCode = ""
    @State private var captchaUuid = ""

    var body: some View {
        Form {
            if let user = environment.authSession.currentUser {
                Section("当前账号") {
                    LabeledContent("邮箱", value: user.email)
                    LabeledContent("角色", value: user.role == .admin ? "管理员" : "用户")
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
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
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
        }
        .navigationTitle("我的")
    }
}
