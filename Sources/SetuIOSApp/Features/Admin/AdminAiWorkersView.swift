import SetuIOSCore
import SwiftUI

struct AdminAiWorkersView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<AiWorkerSnapshot> = .idle
    @State private var controlLoading: String?
    @State private var message: String?

    @State private var pendingAction: (() -> Void)?
    @State private var pendingActionTitle = ""

    var body: some View {
        SetuBoard {
            if environment.authSession.currentUser?.role != .admin {
                AdminWorkerStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后查看 AI Worker。", systemImage: "shield.slash")
            } else {
                if let message {
                    SetuCard {
                        Label(message, systemImage: "checkmark.circle")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                }
                content
            }
        }
        .setuBackground()
        .navigationTitle("AI Worker")
        .confirmationDialog(pendingActionTitle, isPresented: Binding(
            get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }
        ), titleVisibility: .visible) {
            Button("确认执行", role: .destructive) {
                let action = pendingAction
                pendingAction = nil
                action?()
            }
            Button("取消", role: .cancel) { pendingAction = nil }
        } message: {
            Text("此操作将改变当前记录或服务状态，请核对目标后确认。")
        }
        .toolbar {
            Button {
                Task { await load() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            AdminWorkerStateSection(title: "Worker", stateTitle: "正在加载 AI Worker 状态", systemImage: "cpu", isLoading: true)
        case .failed(let message):
            AdminWorkerStateSection(title: "Worker", stateTitle: "AI Worker 加载失败", message: message, systemImage: "cpu")
        case .loaded(let snapshot):
            serviceSection(snapshot)
            controlSection(snapshot.control)
            queueSection(snapshot.status)
            workersSection(snapshot.workers)
            capabilitySection(snapshot.capabilities)
        }
    }

    private func serviceSection(_ snapshot: AiWorkerSnapshot) -> some View {
        SetuRecordCard(headline: "服务状态", supporting: snapshot.status.message,
            status: .init(snapshot.status.statusTitle, tone: snapshot.status.online ? .success : .danger),
            fields: [.init("状态码", snapshot.status.status),
                     .init("在线 Worker", "\(snapshot.status.activeWorkerCount ?? 0) / \(snapshot.workerCount)"),
                     .init("预计等待", formatWait(snapshot.status.estimatedWaitSeconds)),
                     .init("服务器时间", snapshot.status.serverTime ?? "-"), .init("最近心跳", snapshot.status.lastSeenAt ?? "-")], density: .compact)
    }

    private func controlSection(_ control: AiControlStatus?) -> some View {
        SetuRecordCard(headline: "本机控制", supporting: control?.stateMessage ?? "控制服务状态未知",
            status: .init("停止或重启将影响服务", tone: .danger),
            fields: control.map { [.init("最新命令", $0.actionTitle), .init("命令状态", $0.commandStatusTitle),
                                   .init("控制服务", $0.controlReady == true ? "就绪" : "未知/未就绪"),
                                   .init("ComfyUI", $0.comfyReady == true ? "就绪" : "未知/未就绪"),
                                   .init("完成时间", $0.completedAt ?? "-")] } ?? [], density: .compact) {
            ViewThatFits(in: .horizontal) {
                HStack { controlActions }
                VStack { controlActions }
            }
        }
    }

    @ViewBuilder private var controlActions: some View {
        controlButton("启动", action: "start", systemImage: "play.circle")
        controlButton("重启", action: "restart", systemImage: "arrow.clockwise.circle")
        controlButton("停止", action: "stop", systemImage: "stop.circle", role: .destructive)
    }

    private func queueSection(_ status: AiServiceStatusResponse) -> some View {
        SetuRecordCard(headline: "队列", fields: [
                    .init("排队中", "\(status.queuedCount ?? 0)"),
                    .init("生成中", "\(status.runningCount ?? 0)"),
                    .init("上传中", "\(status.uploadingCount ?? 0)")
                ], density: .compact)

    }

    private func workersSection(_ workers: [AiWorkerNode]) -> some View {
        VStack(alignment: .leading, spacing: SetuSpacing.md) {
            SetuSectionHeader(title: "Worker 节点")
            if workers.isEmpty { SetuEmptyState(title: "暂无 Worker 心跳", systemImage: "cpu") }
            SetuRecordBoard(items: workers) { worker in
                SetuRecordCard(headline: worker.nodeName ?? worker.workerId, supporting: worker.message,
                    status: .init(worker.status == "ONLINE" ? "在线" : worker.status ?? "未知", tone: worker.status == "ONLINE" ? .success : .danger),
                    fields: [.init("Worker ID", worker.workerId), .init("版本", worker.version ?? "未知版本"),
                             .init("最近心跳", worker.lastSeenAt ?? "-")], density: .compact)
            }
        }
    }

    private func capabilitySection(_ capabilities: AiCapabilityResponse) -> some View {
        SetuRecordCard(headline: "模型能力", fields: [
            .init("Checkpoint", "\(capabilities.checkpoints.count)"), .init("LoRA", "\(capabilities.loras.count)"),
            .init("角色", "\(capabilities.characters.count)"), .init("提示词预设", "\(capabilities.promptPresets.count)"),
            .init("VAE", "\(capabilities.vaes.count)")], density: .compact) {
            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                capabilityPreview("Checkpoint", items: capabilities.checkpoints)
                capabilityPreview("LoRA", items: capabilities.loras)
                capabilityPreview("角色", items: capabilities.characters)
            }
        }
    }

    private func capabilityPreview(_ title: String, items: [AiCapabilityItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(SetuTypography.caption.weight(.semibold))
                .foregroundStyle(SetuColor.textPrimary)
            if items.isEmpty {
                Text("无")
                    .font(.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            } else {
                TagFlow(tags: items.prefix(12).map { $0.displayName ?? $0.name })
                if items.count > 12 {
                    Text("+\(items.count - 12)")
                        .font(.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                }
            }
        }
        .padding(.vertical, SetuSpacing.xs)
    }

    private func controlButton(_ title: String, action: String, systemImage: String, role: ButtonRole? = nil) -> some View {
        Button(role: role) {
            pendingActionTitle = "确认执行 AI 服务控制命令？"; pendingAction = { Task { await runControl(action) } }
        } label: {
            Label(controlLoading == action ? "处理中" : title, systemImage: controlLoading == action ? "hourglass" : systemImage)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(controlLoading != nil)
    }

    private func load() async {
        guard environment.authSession.currentUser?.role == .admin else { return }
        state = .loading
        do {
            async let status = environment.aiGenerationClient.serviceStatus()
            async let capabilities = environment.aiGenerationClient.capabilities()
            async let control = environment.aiGenerationClient.adminControlStatus()
            let snapshot = try await AiWorkerSnapshot(
                status: status,
                capabilities: capabilities,
                control: control
            )
            state = .loaded(snapshot)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func runControl(_ action: String) async {
        controlLoading = action
        message = nil
        do {
            let control: AiControlStatus
            switch action {
            case "start":
                control = try await environment.aiGenerationClient.startAdminStack()
                message = "AI 绘图启动命令已入队"
            case "stop":
                control = try await environment.aiGenerationClient.stopAdminStack()
                message = "AI 绘图停止命令已入队"
            default:
                control = try await environment.aiGenerationClient.restartAdminStack()
                message = "AI 绘图重启命令已入队"
            }
            if let errorMessage = control.errorMessage, !errorMessage.isEmpty {
                message = errorMessage
            }
            await load()
        } catch {
            message = error.localizedDescription
        }
        controlLoading = nil
    }

    private func formatWait(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "较短" }
        if seconds < 60 {
            return "\(seconds) 秒"
        }
        return "\(Int(ceil(Double(seconds) / 60))) 分钟"
    }
}

private struct AiWorkerSnapshot: Sendable {
    let status: AiServiceStatusResponse
    let capabilities: AiCapabilityResponse
    let control: AiControlStatus?

    var workers: [AiWorkerNode] {
        if let statusWorkers = status.workers, !statusWorkers.isEmpty {
            return statusWorkers
        }
        return capabilities.workers
    }

    var workerCount: Int {
        status.workerCount ?? workers.count
    }
}

private typealias AdminWorkerStateSection = AdminRecordStateSection
