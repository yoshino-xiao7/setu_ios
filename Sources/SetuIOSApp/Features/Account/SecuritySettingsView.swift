import SetuIOSCore
import SwiftUI
import AuthenticationServices

struct SecuritySettingsView: View {
    @Bindable var environment: AppEnvironment
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var feedback: SetuFeedback?
    @State private var isSaving = false
    @State private var appleAuthorizationService = AppleAuthorizationService()
    @State private var appleBindingState: LoadState<AppleBindingStatus> = .idle
    @State private var isAppleMutationInProgress = false
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
                                HStack(spacing: SetuSpacing.sm) {
                                    ProgressView()
                                        .tint(.white)
                                    Text("正在保存新密码")
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } else {
                                HStack(spacing: SetuSpacing.sm) {
                                    Image(systemName: "lock.rotation").accessibilityHidden(true)
                                    Text("保存新密码")
                                        .fixedSize(horizontal: false, vertical: true)
                                }
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
                            subtitle: appleBindingSubtitle
                        )
                        switch appleBindingState {
                        case .idle, .loading:
                            HStack(spacing: SetuSpacing.md) {
                                ProgressView()
                                    .accessibilityHidden(true)
                                Text("正在检查 Apple 绑定状态")
                                    .font(SetuTypography.body)
                                    .foregroundStyle(SetuColor.textSecondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("正在检查 Apple 绑定状态")
                        case .failed(let message):
                            SetuEmptyState(
                                title: "Apple 绑定状态加载失败",
                                message: message,
                                systemImage: "exclamationmark.triangle",
                                actionTitle: "重试",
                                action: { Task { await loadAppleBinding() } }
                            )
                            .accessibilityIdentifier("security.apple.binding.failed")
                        case .loaded(let binding):
                            if binding.linked {
                                Button(role: .destructive) {
                                    showAppleUnbindConfirmation = true
                                } label: {
                                    Label("解除 Apple 绑定", systemImage: "link.badge.minus")
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isAppleMutationInProgress)
                            } else {
                                Button {
                                    Task { await bindApple() }
                                } label: {
                                    Label("绑定 Apple 账号", systemImage: "apple.logo")
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                                .tint(SetuColor.brandInk)
                                .disabled(isAppleMutationInProgress)
                            }
                        }
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
        .accessibilityIdentifier("security.page")
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
        guard case .loaded(let binding) = appleBindingState,
              let email = binding.email,
              !email.isEmpty else { return "" }
        return "（\(email)）"
    }

    private var appleBindingSubtitle: String {
        switch appleBindingState {
        case .idle, .loading:
            return "正在确认当前账号状态"
        case .failed:
            return "暂时无法确认是否已绑定"
        case .loaded(let binding):
            return binding.linked
                ? "已绑定\(appleEmailDescription)"
                : "绑定后可以使用 Apple 安全登录"
        }
    }

    private func save() async {
        guard newPassword == confirmPassword else {
            feedback = .warning("两次输入的新密码不一致")
            return
        }
        guard newPassword.count >= 8 else {
            feedback = .warning("新密码至少 8 位")
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            try await environment.userProfileClient.changePassword(oldPassword: oldPassword, newPassword: newPassword)
            oldPassword = ""
            newPassword = ""
            confirmPassword = ""
            feedback = .success("密码已修改，请重新登录")
            await environment.logout()
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }

    private func loadAppleBinding() async {
        appleBindingState = .loading
        do {
            appleBindingState = .loaded(try await environment.appleAuthClient.binding())
        } catch {
            appleBindingState = .failed(UserFacingErrorMapper.map(error))
        }
    }

    private func bindApple() async {
        isAppleMutationInProgress = true
        defer { isAppleMutationInProgress = false }
        do {
            let credential = try await appleAuthorizationService.authorize()
            appleBindingState = .loaded(
                try await environment.appleAuthClient.bind(
                    identityToken: credential.identityToken,
                    nonce: credential.nonce
                )
            )
            feedback = .success("Apple 账号已绑定")
        } catch {
            let message = AppleAuthorizationService.userMessage(for: error)
            if (error as? ASAuthorizationError)?.code == .canceled {
                feedback = .info(message)
            } else {
                feedback = .error(message)
            }
        }
    }

    private func unbindApple() async {
        isAppleMutationInProgress = true
        defer { isAppleMutationInProgress = false }
        do {
            appleBindingState = .loaded(try await environment.appleAuthClient.unbind())
            feedback = .success("Apple 绑定已解除")
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }
}
