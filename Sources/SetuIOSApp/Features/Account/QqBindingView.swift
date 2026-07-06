import SetuIOSCore
import SwiftUI

struct QqBindingView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<QqBinding> = .idle
    @State private var qqNumber = ""
    @State private var verificationCode = ""
    @State private var message: String?

    var body: some View {
        Form {
            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                ContentUnavailableView("QQ 绑定加载失败", systemImage: "link.badge.plus", description: Text(message))
            case .loaded(let binding):
                Section("当前绑定") {
                    LabeledContent("状态", value: binding.isEnabled ? "已启用" : "未启用")
                    if let qqNumber = binding.qqNumber, !qqNumber.isEmpty {
                        LabeledContent("QQ", value: qqNumber)
                    }
                    if let updatedAt = binding.updatedAt, !updatedAt.isEmpty {
                        LabeledContent("更新时间", value: updatedAt)
                    }
                    if binding.isEnabled {
                        Button("停用 QQ 通知", role: .destructive) {
                            Task { await disable() }
                        }
                    }
                }
            }

            Section("绑定 QQ 邮箱") {
                TextField("QQ 号", text: $qqNumber)
                    .textContentType(.username)
                Button("发送验证码") {
                    Task { await sendCode() }
                }
                .disabled(qqNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                TextField("验证码", text: $verificationCode)
                    .textContentType(.oneTimeCode)
                Button("保存绑定") {
                    Task { await save() }
                }
                .disabled(
                    qqNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            if let message {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("QQ 绑定")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        state = .loading
        message = nil
        do {
            let binding = try await environment.userProfileClient.getQqBinding()
            qqNumber = binding.qqNumber ?? qqNumber
            state = .loaded(binding)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func sendCode() async {
        let number = qqNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !number.isEmpty else { return }
        do {
            let response = try await environment.userProfileClient.sendQqBindingVerificationCode(qqNumber: number)
            if let email = response.qqEmail, let seconds = response.expiresInSeconds {
                message = "验证码已发送到 \(email)，\(seconds) 秒内有效"
            } else {
                message = "验证码已发送"
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func save() async {
        let number = qqNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !number.isEmpty, !code.isEmpty else { return }
        do {
            let binding = try await environment.userProfileClient.saveQqBinding(qqNumber: number, verificationCode: code)
            verificationCode = ""
            message = "QQ 绑定已保存"
            state = .loaded(binding)
        } catch {
            message = error.localizedDescription
        }
    }

    private func disable() async {
        do {
            let binding = try await environment.userProfileClient.disableQqBinding()
            message = "QQ 通知已停用"
            state = .loaded(binding)
        } catch {
            message = error.localizedDescription
        }
    }
}
