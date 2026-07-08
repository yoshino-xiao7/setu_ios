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
        .navigationTitle("修改密码")
    }

    private var canSave: Bool {
        !oldPassword.isEmpty && newPassword.count >= 8 && newPassword == confirmPassword
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
            await environment.authSession.logout()
        } catch {
            message = "修改失败：\(error.localizedDescription)"
        }
    }
}
