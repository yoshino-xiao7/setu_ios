import SetuIOSCore
import SwiftUI

struct SessionDiagnosticsView: View {
    @Bindable var environment: AppEnvironment
    @State private var sessionFeedback: SetuFeedback?
    @State private var sessionDiagnostics: MobileSessionDiagnostics?
    @State private var lastSessionConfirmation: Bool?
    @State private var sessionActionLoading = false

    var body: some View {
        List {
            if environment.authSession.currentUser?.role == .admin {
                Section("故障排查") {
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
        .listStyle(.insetGrouped)
        .setuBackground()
        .navigationTitle("故障排查")
        .task { updateSessionDiagnostics() }
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

}
