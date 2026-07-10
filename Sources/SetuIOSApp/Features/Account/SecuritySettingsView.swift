import SetuIOSCore
import SwiftUI

struct SecuritySettingsView: View {
    @Bindable var environment: AppEnvironment
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var message: String?
    @State private var isSaving = false
    @State private var appleAuthorizationService = AppleAuthorizationService()
    @State private var appleBinding: AppleBindingStatus?
    @State private var appleBindingLoading = false
    @State private var showAppleUnbindConfirmation = false

    var body: some View {
        List {
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "修改密码", subtitle: "新密码至少 8 位，保存后需要重新登录")
                        SecureField("原密码", text: $oldPassword)
                            .textContentType(.password)
                            .textFieldStyle(.roundedBorder)
                        SecureField("新密码", text: $newPassword)
                            .textContentType(.newPassword)
                            .textFieldStyle(.roundedBorder)
                        SecureField("确认新密码", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .textFieldStyle(.roundedBorder)
                        SetuPrimaryButton {
                            Task { await save() }
                        } label: {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Label("保存新密码", systemImage: "lock.rotation")
                            }
                        }
                        .disabled(!canSave || isSaving)
                        .opacity(!canSave || isSaving ? 0.55 : 1)
                    }
                }
            }

            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(
                            title: "Apple 登录",
                            subtitle: appleBinding?.linked == true
                                ? "已绑定(appleEmailDescription)"
                                : "绑定后可以使用 Apple 安全登录"
                        )
                        if appleBindingLoading {
                            ProgressView("正在更新 Apple 绑定")
                        } else if appleBinding?.linked == true {
                            Button(role: .destructive) {
                                showAppleUnbindConfirmation = true
                            } label: {
                                Label("解除 Apple 绑定", systemImage: "link.badge.minus")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button {
                                Task { await bindApple() }
                            } label: {
                                Label("绑定 Apple 账号", systemImage: "apple.logo")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.primary)
                        }
                    }
                }
            }

            if let message {
                Section {
                    SetuPill(
                        text: message,
                        systemImage: isDangerMessage ? "exclamationmark.triangle" : "checkmark.seal",
                        tone: messageTone
                    )
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .setuBackground()
        .navigationTitle("账号安全")
        .task { await loadAppleBinding() }
        .confirmationDialog("解除 Apple 绑定？", isPresented: $showAppleUnbindConfirmation) {
            Button("解除绑定", role: .destructive) {
                Task { await unbindApple() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("解除后将不能再用该 Apple 账号登录；密码和通行密钥登录不受影响。")
        }
    }

    private var canSave: Bool {
        !oldPassword.isEmpty && newPassword.count >= 8 && newPassword == confirmPassword
    }

    private var appleEmailDescription: String {
        guard let email = appleBinding?.email, !email.isEmpty else { return "" }
        return "（\(email)）"
    }

    private var messageTone: SetuPillTone {
        isDangerMessage ? .danger : .success
    }

    private var isDangerMessage: Bool {
        guard let message else { return false }
        return message.contains("失败") || message.contains("不一致") || message.contains("至少")
    }

    private func save() async {
        guard newPassword == confirmPassword else {
            message = "两次输入的新密码不一致"
            return
        }
        guard newPassword.count >= 8 else {
            message = "新密码至少 8 位"
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            try await environment.userProfileClient.changePassword(oldPassword: oldPassword, newPassword: newPassword)
            oldPassword = ""
            newPassword = ""
            confirmPassword = ""
            message = "密码已修改，请重新登录"
            await environment.logout()
        } catch {
            message = "修改失败：\(error.localizedDescription)"
        }
    }

    private func loadAppleBinding() async {
        appleBindingLoading = true
        defer { appleBindingLoading = false }
        appleBinding = try? await environment.appleAuthClient.binding()
    }

    private func bindApple() async {
        appleBindingLoading = true
        defer { appleBindingLoading = false }
        do {
            let credential = try await appleAuthorizationService.authorize()
            appleBinding = try await environment.appleAuthClient.bind(
                identityToken: credential.identityToken,
                nonce: credential.nonce
            )
            message = "Apple 账号已绑定"
        } catch {
            message = AppleAuthorizationService.userMessage(for: error)
        }
    }

    private func unbindApple() async {
        appleBindingLoading = true
        defer { appleBindingLoading = false }
        do {
            appleBinding = try await environment.appleAuthClient.unbind()
            message = "Apple 绑定已解除"
        } catch {
            message = "解除失败：\(error.localizedDescription)"
        }
    }
}
