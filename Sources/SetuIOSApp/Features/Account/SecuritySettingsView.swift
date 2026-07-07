import SetuIOSCore
import SwiftUI

struct SecuritySettingsView: View {
    @Bindable var environment: AppEnvironment
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var message: String?
    @State private var isSaving = false

    var body: some View {
        Form {
            Section("修改密码") {
                SecureField("原密码", text: $oldPassword)
                    .textContentType(.password)
                SecureField("新密码", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("确认新密码", text: $confirmPassword)
                    .textContentType(.newPassword)
                Button("保存新密码") {
                    Task { await save() }
                }
                .disabled(!canSave || isSaving)
            }

            if let message {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(message.contains("失败") || message.contains("不一致") ? .red : .secondary)
                }
            }
        }
        .navigationTitle("修改密码")
    }

    private var canSave: Bool {
        !oldPassword.isEmpty && newPassword.count >= 8 && newPassword == confirmPassword
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
            await environment.authSession.logout()
        } catch {
            message = "修改失败：\(error.localizedDescription)"
        }
    }
}
