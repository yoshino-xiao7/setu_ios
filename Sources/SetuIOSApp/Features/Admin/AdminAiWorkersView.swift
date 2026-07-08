import SetuIOSCore
import SwiftUI

struct AdminAiWorkersView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<AiWorkerSnapshot> = .idle
    @State private var controlLoading: String?
    @State private var message: String?

    var body: some View {
        List {
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
                    .setuListRow()
                }
                content
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("AI Worker")
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
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "服务状态")
                HStack {
                Label(snapshot.status.statusTitle, systemImage: snapshot.status.online ? "checkmark.circle" : "xmark.circle")
                        .foregroundStyle(snapshot.status.online ? SetuColor.success : SetuColor.danger)
                Spacer()
                Text(snapshot.status.status)
                    .font(.caption.monospaced())
                        .foregroundStyle(SetuColor.textSecondary)
            }
            if let detail = snapshot.status.message, !detail.isEmpty {
                Text(detail)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
            }
                AdminWorkerMetadataRow(title: "在线 Worker", value: "\(snapshot.status.activeWorkerCount ?? 0) / \(snapshot.workerCount)")
                AdminWorkerMetadataRow(title: "预计等待", value: formatWait(snapshot.status.estimatedWaitSeconds))
                AdminWorkerMetadataRow(title: "服务器时间", value: snapshot.status.serverTime ?? "-")
                AdminWorkerMetadataRow(title: "最近心跳", value: snapshot.status.lastSeenAt ?? "-")
            }
        }
        .setuListRow()
    }

    private func controlSection(_ control: AiControlStatus?) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "本机控制")
            if let control {
                Text(control.stateMessage)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                AdminWorkerMetadataRow(title: "最新命令", value: control.actionTitle)
                AdminWorkerMetadataRow(title: "命令状态", value: control.commandStatusTitle)
                AdminWorkerMetadataRow(title: "控制服务", value: control.controlReady == true ? "就绪" : "未知/未就绪")
                AdminWorkerMetadataRow(title: "ComfyUI", value: control.comfyReady == true ? "就绪" : "未知/未就绪")
                AdminWorkerMetadataRow(title: "完成时间", value: control.completedAt ?? "-")
            } else {
                Text("控制服务状态未知")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
            }

                HStack(spacing: SetuSpacing.md) {
                controlButton("启动", action: "start", systemImage: "play.circle")
                controlButton("重启", action: "restart", systemImage: "arrow.clockwise.circle")
                controlButton("停止", action: "stop", systemImage: "stop.circle", role: .destructive)
            }
        }
        }
        .setuListRow()
    }

    private func queueSection(_ status: AiServiceStatusResponse) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "队列")
                AdminWorkerMetadataRow(title: "排队中", value: "\(status.queuedCount ?? 0)")
                AdminWorkerMetadataRow(title: "生成中", value: "\(status.runningCount ?? 0)")
                AdminWorkerMetadataRow(title: "上传中", value: "\(status.uploadingCount ?? 0)")
            }
        }
        .setuListRow()
    }

    private func workersSection(_ workers: [AiWorkerNode]) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "Worker 节点")
            if workers.isEmpty {
                    SetuEmptyState(title: "暂无 Worker 心跳", systemImage: "cpu")
            } else {
                    ForEach(Array(workers.enumerated()), id: \.element.id) { index, worker in
                        if index > 0 {
                            Divider()
                                .overlay(SetuColor.separator)
                        }
                    VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                        HStack {
                            Text(worker.nodeName ?? worker.workerId)
                                    .font(SetuTypography.headline)
                                    .foregroundStyle(SetuColor.textPrimary)
                            Spacer()
                                SetuPill(text: worker.status == "ONLINE" ? "在线" : worker.status ?? "未知", systemImage: "cpu", tone: worker.status == "ONLINE" ? .success : .danger)
                        }
                        Text(worker.workerId)
                            .font(.caption.monospaced())
                                .foregroundStyle(SetuColor.textSecondary)
                        HStack {
                            Label(worker.version ?? "未知版本", systemImage: "cube")
                            Spacer()
                            Label(worker.lastSeenAt ?? "-", systemImage: "clock")
                        }
                        .font(.caption)
                            .foregroundStyle(SetuColor.textTertiary)
                        if let message = worker.message, !message.isEmpty {
                            Text(message)
                                    .font(SetuTypography.caption)
                                    .foregroundStyle(SetuColor.textSecondary)
                        }
                    }
                        .padding(.vertical, SetuSpacing.xs)
                }
            }
        }
        }
        .setuListRow()
    }

    private func capabilitySection(_ capabilities: AiCapabilityResponse) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "模型能力")
                AdminWorkerMetadataRow(title: "Checkpoint", value: "\(capabilities.checkpoints.count)")
                AdminWorkerMetadataRow(title: "LoRA", value: "\(capabilities.loras.count)")
                AdminWorkerMetadataRow(title: "角色", value: "\(capabilities.characters.count)")
                AdminWorkerMetadataRow(title: "提示词预设", value: "\(capabilities.promptPresets.count)")
                AdminWorkerMetadataRow(title: "VAE", value: "\(capabilities.vaes.count)")

            capabilityPreview("Checkpoint", items: capabilities.checkpoints)
            capabilityPreview("LoRA", items: capabilities.loras)
            capabilityPreview("角色", items: capabilities.characters)
        }
        }
        .setuListRow()
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
            Task { await runControl(action) }
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

private struct AdminWorkerStateSection: View {
    let title: String
    let stateTitle: String
    var message: String?
    var systemImage: String
    var isLoading = false

    var body: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: title)
                SetuEmptyState(title: stateTitle, message: message, systemImage: systemImage, isLoading: isLoading)
            }
        }
        .setuListRow()
    }
}

private struct AdminWorkerMetadataRow<Value: View>: View {
    let title: String
    private let value: Value

    init(title: String, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .top, spacing: SetuSpacing.md) {
            Text(title)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .frame(width: 84, alignment: .leading)
            value
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private extension AdminWorkerMetadataRow where Value == Text {
    init(title: String, value: String) {
        self.title = title
        self.value = Text(value)
            .font(SetuTypography.body)
            .foregroundStyle(SetuColor.textPrimary)
    }
}
