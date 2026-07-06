import SetuIOSCore
import SwiftUI

struct AdminOperationLogsView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<PageResult<AdminOperationLogItem>> = .idle
    @State private var traceId = ""
    @State private var userEmail = ""
    @State private var eventType = ""
    @State private var statusFilter = "ALL"
    @State private var code = ""
    @State private var targetType = ""
    @State private var targetId = ""
    @State private var page = 1
    private let pageSize = 20

    var body: some View {
        List {
            if environment.authSession.currentUser?.role != .admin {
                ContentUnavailableView("需要管理员权限", systemImage: "shield.slash", description: Text("请使用管理员账号登录后查看操作日志。"))
            } else {
                filterSection
                content
            }
        }
        .navigationTitle("操作日志")
        .task { await load(resetPage: true) }
        .refreshable { await load(resetPage: false) }
    }

    private var filterSection: some View {
        Section("筛选") {
            TextField("Trace ID", text: $traceId)
            TextField("用户邮箱", text: $userEmail)
            TextField("事件类型", text: $eventType)
            Picker("状态", selection: $statusFilter) {
                Text("全部").tag("ALL")
                Text("成功").tag("SUCCESS")
                Text("失败").tag("FAILED")
                Text("部分成功").tag("PARTIAL")
            }
            TextField("业务 code", text: $code)
            TextField("目标类型", text: $targetType)
            TextField("目标 ID", text: $targetId)

            HStack {
                Button {
                    Task { await load(resetPage: true) }
                } label: {
                    Label("查询", systemImage: "magnifyingglass")
                }
                Spacer()
                Button("重置") {
                    resetFilters()
                    Task { await load(resetPage: true) }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ProgressView("正在加载操作日志")
        case .failed(let message):
            ContentUnavailableView("操作日志加载失败", systemImage: "doc.text.magnifyingglass", description: Text(message))
        case .loaded(let result):
            if result.list.isEmpty {
                ContentUnavailableView("暂无日志", systemImage: "doc.text", description: Text("当前筛选条件下没有操作日志。"))
            } else {
                Section("共 \(result.total) 条") {
                    ForEach(result.list) { log in
                        Button {
                            router.navigate(to: .adminOperationLogDetail(log.id))
                        } label: {
                            OperationLogRow(log: log)
                        }
                        .buttonStyle(.plain)
                    }
                }
                pagerSection(result)
            }
        }
    }

    private func pagerSection(_ result: PageResult<AdminOperationLogItem>) -> some View {
        Section {
            HStack {
                Button("上一页") {
                    Task {
                        page = max(1, page - 1)
                        await load(resetPage: false)
                    }
                }
                .disabled(page <= 1)
                Spacer()
                Text("第 \(result.page) 页")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("下一页") {
                    Task {
                        page += 1
                        await load(resetPage: false)
                    }
                }
                .disabled(result.page * result.pageSize >= result.total)
            }
        }
    }

    private func load(resetPage: Bool) async {
        guard environment.authSession.currentUser?.role == .admin else { return }
        if resetPage {
            page = 1
        }
        state = .loading
        do {
            state = .loaded(try await environment.adminClient.operationLogs(
                page: page,
                pageSize: pageSize,
                traceId: clean(traceId),
                userEmail: clean(userEmail),
                eventType: clean(eventType),
                status: statusFilter == "ALL" ? nil : statusFilter,
                code: clean(code),
                targetType: clean(targetType),
                targetId: clean(targetId)
            ))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func resetFilters() {
        traceId = ""
        userEmail = ""
        eventType = ""
        statusFilter = "ALL"
        code = ""
        targetType = ""
        targetId = ""
    }

    private func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct AdminOperationLogDetailView: View {
    @Bindable var environment: AppEnvironment
    let logID: Int
    @State private var state: LoadState<AdminOperationLogDetail> = .idle

    var body: some View {
        List {
            if environment.authSession.currentUser?.role != .admin {
                ContentUnavailableView("需要管理员权限", systemImage: "shield.slash", description: Text("请使用管理员账号登录后查看操作日志。"))
            } else {
                content
            }
        }
        .navigationTitle("日志 #\(logID)")
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ProgressView("正在加载日志详情")
        case .failed(let message):
            ContentUnavailableView("日志详情加载失败", systemImage: "doc.text.magnifyingglass", description: Text(message))
        case .loaded(let detail):
            Section("基础信息") {
                LabeledContent("事件", value: detail.eventType)
                LabeledContent("状态", value: detail.statusTitle)
                LabeledContent("用户", value: detail.userEmail ?? detail.userId.map(String.init) ?? "-")
                LabeledContent("目标", value: "\(detail.targetType ?? "-") / \(detail.targetId ?? "-")")
                LabeledContent("路径", value: "\(detail.method ?? "-") \(detail.path ?? "-")")
                LabeledContent("Trace ID", value: detail.traceId ?? "-")
                LabeledContent("Request ID", value: detail.requestId ?? "-")
                LabeledContent("IP", value: detail.ip ?? "-")
                LabeledContent("时间", value: detail.createdAt)
                if let durationMs = detail.durationMs {
                    LabeledContent("耗时", value: "\(durationMs) ms")
                }
            }

            if let message = detail.message, !message.isEmpty {
                Section("消息") {
                    Text(message)
                }
            }

            payloadSection("请求", detail.displayRequestPayload)
            payloadSection("响应", detail.displayResponsePayload)
            payloadSection("扩展信息", detail.displayExtraPayload)

            if let userAgent = detail.userAgent, !userAgent.isEmpty {
                Section("User Agent") {
                    Text(userAgent)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func payloadSection(_ title: String, _ payload: String?) -> some View {
        Section(title) {
            if let payload, !payload.isEmpty {
                Text(prettyPayload(payload))
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            } else {
                Text("无")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        guard environment.authSession.currentUser?.role == .admin else { return }
        state = .loading
        do {
            state = .loaded(try await environment.adminClient.operationLogDetail(id: logID))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func prettyPayload(_ payload: String) -> String {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8)
        else {
            return payload
        }
        return string
    }
}

private struct OperationLogRow: View {
    let log: AdminOperationLogItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(log.eventType)
                        .font(.headline)
                    Text(log.userEmail ?? log.userId.map { "用户 #\($0)" } ?? "未知用户")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(log.statusTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            if let message = log.message, !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Label(log.targetType ?? "-", systemImage: "scope")
                if let targetId = log.targetId {
                    Label(targetId, systemImage: "number")
                }
                Label(log.createdAt, systemImage: "calendar")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch log.status {
        case "SUCCESS":
            return .green
        case "FAILED":
            return .red
        case "PARTIAL":
            return .orange
        default:
            return .secondary
        }
    }
}
