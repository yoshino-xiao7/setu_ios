import SetuIOSCore
import SwiftUI

struct QqBindingView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<QqBinding> = .idle
    @State private var qqNumber = ""
    @State private var verificationCode = ""
    @State private var feedback: SetuFeedback?

    var body: some View {
        List {
            switch state {
            case .idle, .loading:
                Section {
                    SetuCard {
                        SetuEmptyState(title: "正在加载", systemImage: "link.badge.plus", isLoading: true)
                    }
                }
            case .failed(let message):
                Section {
                    SetuCard {
                        SetuEmptyState(
                            title: "QQ 绑定加载失败",
                            message: message,
                            systemImage: "link.badge.plus",
                            actionTitle: "重试",
                            action: { Task { await load() } }
                        )
                    }
                }
            case .loaded(let binding):
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            HStack {
                                SetuSectionHeader(title: "当前绑定", subtitle: "QQ 通知和登录提醒状态")
                                Spacer()
                                SetuPill(
                                    text: binding.isEnabled ? "已启用" : "未启用",
                                    systemImage: binding.isEnabled ? "checkmark.circle" : "pause.circle",
                                    tone: binding.isEnabled ? .success : .muted
                                )
                            }
                            QqBindingInfoRow(title: "QQ", value: binding.qqNumber?.isEmpty == false ? binding.qqNumber! : "-")
                            if let updatedAt = binding.updatedAt, !updatedAt.isEmpty {
                                QqBindingInfoRow(title: "更新时间", value: SetuDateFormatter.string(from: updatedAt, style: .full))
                            }
                            if binding.isEnabled {
                                Button(role: .destructive) {
                                    Task { await disable() }
                                } label: {
                                    Label("停用 QQ 通知", systemImage: "bell.slash")
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }

            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "绑定 QQ 邮箱", subtitle: "输入 QQ 号并使用邮件验证码确认")
                        TextField("QQ 号", text: $qqNumber)
                            .textContentType(.username)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            Task { await sendCode() }
                        } label: {
                            Label("发送验证码", systemImage: "paperplane")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(SetuColor.brandPink)
                        .disabled(trimmedQqNumber.isEmpty)

                        TextField("验证码", text: $verificationCode)
                            .textContentType(.oneTimeCode)
                            .textFieldStyle(.roundedBorder)
                        SetuPrimaryButton {
                            Task { await save() }
                        } label: {
                            Label("保存绑定", systemImage: "checkmark.seal")
                        }
                        .disabled(!canSaveBinding)
                        .opacity(canSaveBinding ? 1 : 0.55)

                        Text("AI 绘图推送需要先添加 bot QQ：2830323446，否则可能收不到队列和完成通知。")
                            .font(.footnote)
                            .foregroundStyle(SetuColor.textSecondary)
                    }
                }
            }

            if let feedback {
                Section {
                    SetuFeedbackBanner(feedback: feedback)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .setuBackground()
        .setuFeedbackPresentation($feedback)
        .navigationTitle("QQ 绑定")
        .task { await load() }
        .refreshable { await load() }
    }

    private var trimmedQqNumber: String {
        qqNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedVerificationCode: String {
        verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveBinding: Bool {
        !trimmedQqNumber.isEmpty && !trimmedVerificationCode.isEmpty
    }

    private func load() async {
        state = .loading
        feedback = nil
        do {
            let binding = try await environment.userProfileClient.getQqBinding()
            qqNumber = binding.qqNumber ?? qqNumber
            state = .loaded(binding)
        } catch {
            state = .failed(UserFacingErrorMapper.map(error))
        }
    }

    private func sendCode() async {
        let number = trimmedQqNumber
        guard !number.isEmpty else { return }
        do {
            let response = try await environment.userProfileClient.sendQqBindingVerificationCode(qqNumber: number)
            if let email = response.qqEmail, let seconds = response.expiresInSeconds {
                feedback = .info("验证码已发送到 \(email)，\(seconds) 秒内有效")
            } else {
                feedback = .info("验证码已发送")
            }
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }

    private func save() async {
        let number = trimmedQqNumber
        let code = trimmedVerificationCode
        guard !number.isEmpty, !code.isEmpty else { return }
        do {
            let binding = try await environment.userProfileClient.saveQqBinding(qqNumber: number, verificationCode: code)
            verificationCode = ""
            feedback = .success("QQ 绑定已保存")
            state = .loaded(binding)
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }

    private func disable() async {
        do {
            let binding = try await environment.userProfileClient.disableQqBinding()
            feedback = .success("QQ 通知已停用")
            state = .loaded(binding)
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }
}

private struct QqBindingInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
            Spacer(minLength: SetuSpacing.md)
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(SetuColor.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}
