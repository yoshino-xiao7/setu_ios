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
                ContentUnavailableView("需要管理员权限", systemImage: "shield.slash", description: Text("请使用管理员账号登录后查看 AI Worker。"))
            } else {
                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                content
            }
        }
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
            ProgressView("正在加载 AI Worker 状态")
        case .failed(let message):
            ContentUnavailableView("AI Worker 加载失败", systemImage: "cpu", description: Text(message))
        case .loaded(let snapshot):
            serviceSection(snapshot)
            controlSection(snapshot.control)
            queueSection(snapshot.status)
            workersSection(snapshot.workers)
            capabilitySection(snapshot.capabilities)
        }
    }

    private func serviceSection(_ snapshot: AiWorkerSnapshot) -> some View {
        Section("服务状态") {
            HStack {
                Label(snapshot.status.statusTitle, systemImage: snapshot.status.online ? "checkmark.circle" : "xmark.circle")
                    .foregroundStyle(snapshot.status.online ? .green : .red)
                Spacer()
                Text(snapshot.status.status)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let detail = snapshot.status.message, !detail.isEmpty {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("在线 Worker", value: "\(snapshot.status.activeWorkerCount ?? 0) / \(snapshot.workerCount)")
            LabeledContent("预计等待", value: formatWait(snapshot.status.estimatedWaitSeconds))
            LabeledContent("服务器时间", value: snapshot.status.serverTime ?? "-")
            LabeledContent("最近心跳", value: snapshot.status.lastSeenAt ?? "-")
        }
    }

    private func controlSection(_ control: AiControlStatus?) -> some View {
        Section("本机控制") {
            if let control {
                Text(control.stateMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LabeledContent("最新命令", value: control.actionTitle)
                LabeledContent("命令状态", value: control.commandStatusTitle)
                LabeledContent("控制服务", value: control.controlReady == true ? "就绪" : "未知/未就绪")
                LabeledContent("ComfyUI", value: control.comfyReady == true ? "就绪" : "未知/未就绪")
                LabeledContent("完成时间", value: control.completedAt ?? "-")
            } else {
                Text("控制服务状态未知")
                    .foregroundStyle(.secondary)
            }

            HStack {
                controlButton("启动", action: "start", systemImage: "play.circle")
                controlButton("重启", action: "restart", systemImage: "arrow.clockwise.circle")
                controlButton("停止", action: "stop", systemImage: "stop.circle", role: .destructive)
            }
        }
    }

    private func queueSection(_ status: AiServiceStatusResponse) -> some View {
        Section("队列") {
            LabeledContent("排队中", value: "\(status.queuedCount ?? 0)")
            LabeledContent("生成中", value: "\(status.runningCount ?? 0)")
            LabeledContent("上传中", value: "\(status.uploadingCount ?? 0)")
        }
    }

    private func workersSection(_ workers: [AiWorkerNode]) -> some View {
        Section("Worker 节点") {
            if workers.isEmpty {
                ContentUnavailableView("暂无 Worker 心跳", systemImage: "cpu")
            } else {
                ForEach(workers) { worker in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(worker.nodeName ?? worker.workerId)
                                .font(.headline)
                            Spacer()
                            Text(worker.status == "ONLINE" ? "在线" : worker.status ?? "未知")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(worker.status == "ONLINE" ? .green : .red)
                        }
                        Text(worker.workerId)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        HStack {
                            Label(worker.version ?? "未知版本", systemImage: "cube")
                            Spacer()
                            Label(worker.lastSeenAt ?? "-", systemImage: "clock")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let message = worker.message, !message.isEmpty {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func capabilitySection(_ capabilities: AiCapabilityResponse) -> some View {
        Section("模型能力") {
            LabeledContent("Checkpoint", value: "\(capabilities.checkpoints.count)")
            LabeledContent("LoRA", value: "\(capabilities.loras.count)")
            LabeledContent("角色", value: "\(capabilities.characters.count)")
            LabeledContent("提示词预设", value: "\(capabilities.promptPresets.count)")
            LabeledContent("VAE", value: "\(capabilities.vaes.count)")

            capabilityPreview("Checkpoint", items: capabilities.checkpoints)
            capabilityPreview("LoRA", items: capabilities.loras)
            capabilityPreview("角色", items: capabilities.characters)
        }
    }

    private func capabilityPreview(_ title: String, items: [AiCapabilityItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
            if items.isEmpty {
                Text("无")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TagFlow(tags: items.prefix(12).map { $0.displayName ?? $0.name })
                if items.count > 12 {
                    Text("+\(items.count - 12)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func controlButton(_ title: String, action: String, systemImage: String, role: ButtonRole? = nil) -> some View {
        Button(role: role) {
            Task { await runControl(action) }
        } label: {
            if controlLoading == action {
                ProgressView()
            } else {
                Label(title, systemImage: systemImage)
            }
        }
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
