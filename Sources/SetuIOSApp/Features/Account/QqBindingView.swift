import SetuIOSCore
import SwiftUI

struct QqBindingView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<QqBinding> = .idle
    @State private var qqNumber = ""
    @State private var verificationCode = ""
    @State private var feedback: SetuFeedback?

    var body: some View {
        SetuBoard {
            switch state {
            case .idle, .loading:
                Section {
                    SetuCard {
                        AccountSurfaceSkeleton(title: "正在加载 QQ 绑定")
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
                SetuBento(items: bindingItems(binding), span: { _ in .small }) { item in
                    SetuBentoTile(title: item.title, subtitle: item.value, systemImage: item.systemImage)
                }
                if binding.isEnabled {
                    SetuRecordCard(headline: "QQ 通知", supporting: "停用后不再通过 QQ 接收通知", status: .init("已启用", tone: .success)) {
                        Button(role: .destructive) { Task { await disable() } } label: {
                            Label("停用 QQ 通知", systemImage: "bell.slash").frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
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
                    }
                }
            }

            if let feedback {
                Section {
                    SetuFeedbackBanner(feedback: feedback)
                }
            }
        }
        .setuFeedbackPresentation($feedback)
        .navigationTitle("QQ 绑定")
        .task { await load() }
        .refreshable { await load() }
    }

    private func bindingItems(_ binding: QqBinding) -> [AccountSurfaceItem] {
        var items = [
            AccountSurfaceItem(title: "当前 QQ", value: binding.qqNumber?.isEmpty == false ? binding.qqNumber! : "尚未绑定", systemImage: "link"),
            AccountSurfaceItem(title: "通知状态", value: binding.isEnabled ? "已启用" : "未启用", systemImage: "bell.badge")
        ]
        if let updatedAt = binding.updatedAt, !updatedAt.isEmpty {
            items.append(.init(title: "更新时间", value: SetuDateFormatter.string(from: updatedAt, style: .full), systemImage: "clock"))
        }
        return items
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
