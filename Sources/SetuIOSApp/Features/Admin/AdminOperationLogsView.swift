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
        SetuBoard {
            if environment.authSession.currentUser?.role != .admin {
                AdminOperationLogStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后查看操作日志。", systemImage: "shield.slash")
            } else {
                filterSection
                content
            }
        }
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
                SetuFilterBar(options: [
                    .init(value: "ALL", title: "全部"),
                    .init(value: "SUCCESS", title: "成功"),
                    .init(value: "FAILED", title: "失败"),
                    .init(value: "PARTIAL", title: "部分成功")
                ], selection: $statusFilter, accessibilityTitle: "状态")

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
                Group {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "共 \(result.total) 条", subtitle: "操作日志")
                    SetuRecordBoard(items: result.list) { log in
                        Button {
                            router.navigate(to: .adminOperationLogDetail(log.id))
                        } label: {
                            OperationLogRow(log: log)
                        }
                        .buttonStyle(.plain)
                    }
                }
                }

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
        SetuBoard {
            if environment.authSession.currentUser?.role != .admin {
                AdminOperationLogStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后查看操作日志。", systemImage: "shield.slash")
            } else {
                content
            }
        }
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
            SetuRecordCard(headline: detail.eventType,
                status: .init(detail.statusTitle, tone: detail.status == "FAILED" ? .danger : .brand),
                fields: [.init("用户", detail.userEmail ?? detail.userId.map(String.init) ?? "-"),
                         .init("目标", "\(detail.targetType ?? "-") / \(detail.targetId ?? "-")"),
                         .init("路径", "\(detail.method ?? "-") \(detail.path ?? "-")"),
                         .init("Trace ID", detail.traceId ?? "-"), .init("Request ID", detail.requestId ?? "-"),
                         .init("IP", detail.ip ?? "-"), .init("时间", detail.createdAt),
                         .init("耗时", detail.durationMs.map { "\($0) ms" } ?? "-")], density: .compact)

            if let message = detail.message, !message.isEmpty {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "消息")
                    Text(message)
                            .font(SetuTypography.body)
                            .foregroundStyle(SetuColor.textPrimary)
                    }
                }

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
        SetuRecordCard(headline: log.eventType, supporting: log.message,
            status: .init(log.statusTitle, tone: log.status == "FAILED" ? .danger : (log.status == "SUCCESS" ? .success : .warning)),
            fields: [.init("用户", log.userEmail ?? log.userId.map(String.init) ?? "未知用户"),
                     .init("目标类型", log.targetType ?? "-"), .init("目标 ID", log.targetId ?? "-"),
                     .init("时间", log.createdAt)], density: .compact)
    }
}

private typealias AdminOperationLogStateSection = AdminRecordStateSection
