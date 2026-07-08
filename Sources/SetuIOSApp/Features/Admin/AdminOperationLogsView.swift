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
                AdminOperationLogStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后查看操作日志。", systemImage: "shield.slash")
            } else {
                filterSection
                content
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("操作日志")
        .task { await load(resetPage: true) }
        .refreshable { await load(resetPage: false) }
    }

    private var filterSection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "筛选")
                TextField("Trace ID", text: $traceId)
                    .textFieldStyle(.roundedBorder)
                TextField("用户邮箱", text: $userEmail)
                    .textFieldStyle(.roundedBorder)
                TextField("事件类型", text: $eventType)
                    .textFieldStyle(.roundedBorder)
                Picker("状态", selection: $statusFilter) {
                    Text("全部").tag("ALL")
                    Text("成功").tag("SUCCESS")
                    Text("失败").tag("FAILED")
                    Text("部分成功").tag("PARTIAL")
                }
                .pickerStyle(.segmented)
                TextField("业务 code", text: $code)
                    .textFieldStyle(.roundedBorder)
                TextField("目标类型", text: $targetType)
                    .textFieldStyle(.roundedBorder)
                TextField("目标 ID", text: $targetId)
                    .textFieldStyle(.roundedBorder)

            HStack {
                Button {
                    Task { await load(resetPage: true) }
                } label: {
                    Label("查询", systemImage: "magnifyingglass")
                            .frame(minHeight: 44)
                }
                Spacer()
                Button("重置") {
                    resetFilters()
                    Task { await load(resetPage: true) }
                }
                    .frame(minHeight: 44)
            }
            }
        }
        .setuListRow()
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            AdminOperationLogStateSection(title: "操作日志", stateTitle: "正在加载操作日志", systemImage: "doc.text.magnifyingglass", isLoading: true)
        case .failed(let message):
            AdminOperationLogStateSection(title: "操作日志", stateTitle: "操作日志加载失败", message: message, systemImage: "doc.text.magnifyingglass")
        case .loaded(let result):
            if result.list.isEmpty {
                AdminOperationLogStateSection(title: "操作日志", stateTitle: "暂无日志", message: "当前筛选条件下没有操作日志。", systemImage: "doc.text")
            } else {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "共 \(result.total) 条", subtitle: "操作日志")
                    ForEach(Array(result.list.enumerated()), id: \.element.id) { index, log in
                            if index > 0 {
                                Divider()
                                    .overlay(SetuColor.separator)
                            }
                        Button {
                            router.navigate(to: .adminOperationLogDetail(log.id))
                        } label: {
                            OperationLogRow(log: log)
                        }
                        .buttonStyle(.plain)
                    }
                }
                }
                .setuListRow()
                pagerSection(result)
            }
        }
    }

    private func pagerSection(_ result: PageResult<AdminOperationLogItem>) -> some View {
        SetuCard {
            HStack {
                Button {
                    Task {
                        page = max(1, page - 1)
                        await load(resetPage: false)
                    }
                } label: {
                    Label("上一页", systemImage: "chevron.left")
                        .frame(minHeight: 44)
                }
                .disabled(page <= 1)
                Spacer()
                Text("第 \(result.page) 页")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
                Spacer()
                Button {
                    Task {
                        page += 1
                        await load(resetPage: false)
                    }
                } label: {
                    Label("下一页", systemImage: "chevron.right")
                        .frame(minHeight: 44)
                }
                .disabled(result.page * result.pageSize >= result.total)
            }
        }
        .setuListRow()
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
                AdminOperationLogStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后查看操作日志。", systemImage: "shield.slash")
            } else {
                content
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("日志 #\(logID)")
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            AdminOperationLogStateSection(title: "日志详情", stateTitle: "正在加载日志详情", systemImage: "doc.text.magnifyingglass", isLoading: true)
        case .failed(let message):
            AdminOperationLogStateSection(title: "日志详情", stateTitle: "日志详情加载失败", message: message, systemImage: "doc.text.magnifyingglass")
        case .loaded(let detail):
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "基础信息")
                    AdminOperationMetadataRow(title: "事件", value: detail.eventType)
                    AdminOperationMetadataRow(title: "状态") {
                        OperationStatusPill(status: detail.status, title: detail.statusTitle)
                    }
                    AdminOperationMetadataRow(title: "用户", value: detail.userEmail ?? detail.userId.map(String.init) ?? "-")
                    AdminOperationMetadataRow(title: "目标", value: "\(detail.targetType ?? "-") / \(detail.targetId ?? "-")")
                    AdminOperationMetadataRow(title: "路径", value: "\(detail.method ?? "-") \(detail.path ?? "-")")
                    AdminOperationMetadataRow(title: "Trace ID", value: detail.traceId ?? "-")
                    AdminOperationMetadataRow(title: "Request ID", value: detail.requestId ?? "-")
                    AdminOperationMetadataRow(title: "IP", value: detail.ip ?? "-")
                    AdminOperationMetadataRow(title: "时间", value: detail.createdAt)
                    if let durationMs = detail.durationMs {
                        AdminOperationMetadataRow(title: "耗时", value: "\(durationMs) ms")
                    }
                }
            }
            .setuListRow()

            if let message = detail.message, !message.isEmpty {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "消息")
                    Text(message)
                            .font(SetuTypography.body)
                            .foregroundStyle(SetuColor.textPrimary)
                    }
                }
                .setuListRow()
            }

            payloadSection("请求", detail.displayRequestPayload)
            payloadSection("响应", detail.displayResponsePayload)
            payloadSection("扩展信息", detail.displayExtraPayload)

            if let userAgent = detail.userAgent, !userAgent.isEmpty {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "User Agent")
                    Text(userAgent)
                        .font(.footnote)
                            .foregroundStyle(SetuColor.textPrimary)
                        .textSelection(.enabled)
                }
                }
                .setuListRow()
            }
        }
    }

    private func payloadSection(_ title: String, _ payload: String?) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: title)
            if let payload, !payload.isEmpty {
                Text(prettyPayload(payload))
                    .font(.footnote.monospaced())
                        .foregroundStyle(SetuColor.textPrimary)
                    .textSelection(.enabled)
            } else {
                Text("无")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
            }
        }
        }
        .setuListRow()
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
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(log.eventType)
                        .font(SetuTypography.headline)
                        .foregroundStyle(SetuColor.textPrimary)
                    Text(log.userEmail ?? log.userId.map { "用户 #\($0)" } ?? "未知用户")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                }
                Spacer()
                OperationStatusPill(status: log.status, title: log.statusTitle)
            }

            if let message = log.message, !message.isEmpty {
                Text(message)
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
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
            .foregroundStyle(SetuColor.textTertiary)
        }
        .padding(.vertical, SetuSpacing.xs)
    }
}

private struct AdminOperationLogStateSection: View {
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

private struct AdminOperationMetadataRow<Value: View>: View {
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

private extension AdminOperationMetadataRow where Value == Text {
    init(title: String, value: String) {
        self.title = title
        self.value = Text(value)
            .font(SetuTypography.body)
            .foregroundStyle(SetuColor.textPrimary)
    }
}

private struct OperationStatusPill: View {
    let status: String
    let title: String

    var body: some View {
        SetuPill(text: title, systemImage: "flag", tone: tone)
    }

    private var tone: SetuPillTone {
        switch status {
        case "SUCCESS":
            .success
        case "FAILED":
            .danger
        case "PARTIAL":
            .warning
        default:
            .muted
        }
    }
}
