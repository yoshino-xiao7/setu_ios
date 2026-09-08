import SetuIOSCore
import SwiftUI

struct AdminPixivCrawlView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var health: LoadState<PixivCrawlerHealth> = .idle
    @State private var tasks: LoadState<PixivCrawlerTaskList> = .idle
    @State private var mode = "ids"
    @State private var idsInput = ""
    @State private var userID = ""
    @State private var tag = ""
    @State private var tagMode = "popular"
    @State private var pageFrom = 1
    @State private var pageTo = 5
    @State private var skipExisting = true
    @State private var isSubmitting = false
    @State private var message: String?

    var body: some View {
        List {
            if environment.authSession.currentUser?.role != .admin {
                AdminPixivStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后创建 Pixiv 抓取任务。", systemImage: "shield.slash")
            } else {
                healthSection
                if let message {
                    SetuCard {
                        Label(message, systemImage: "checkmark.circle")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .setuListRow()
                }
                createSection
                taskSection
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("新增图片")
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    @ViewBuilder
    private var healthSection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "爬虫服务")
            switch health {
            case .idle, .loading:
                    SetuEmptyState(title: "正在检查服务", systemImage: "pulse", isLoading: true)
            case .failed(let message):
                SetuFeedbackBanner(error: message)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.danger)
            case .loaded(let health):
                HStack {
                    Label(health.isOnline ? "服务在线" : "服务状态：\(health.status ?? "-")", systemImage: "pulse")
                            .foregroundStyle(health.isOnline ? SetuColor.success : SetuColor.warning)
                    Spacer()
                    Text(health.environment ?? "-")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                }
                    AdminPixivMetadataRow(title: "数据库", value: health.database ?? "-")
                }
            }
        }
        .setuListRow()
    }

    private var createSection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "新建任务", subtitle: "Pixiv 抓取")
                Picker("模式", selection: $mode) {
                    Text("按 PID").tag("ids")
                    Text("按画师").tag("user")
                    Text("按标签").tag("tag")
                }
                .pickerStyle(.segmented)
                Toggle("跳过已存在", isOn: $skipExisting)

                if mode == "ids" {
                    TextEditor(text: $idsInput)
                        .frame(minHeight: 96)
                        .padding(SetuSpacing.xs)
                        .background(SetuColor.surfaceMuted, in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if idsInput.isEmpty {
                                Text("输入 PID，多个用逗号、空格或换行分隔")
                                    .font(SetuTypography.caption)
                                    .foregroundStyle(SetuColor.textTertiary)
                                    .padding(.top, SetuSpacing.md)
                                    .padding(.leading, SetuSpacing.md)
                            }
                        }
                    if !idsInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       case .failure(let error) = Result(catching: { try PixivPIDInput.parse(idsInput) }) {
                        Text(error.localizedDescription).font(.caption).foregroundStyle(SetuColor.danger)
                    }
                } else if mode == "user" {
                    TextField("画师 UID", text: $userID)
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField("搜索标签", text: $tag)
                        .textFieldStyle(.roundedBorder)
                    Picker("排序模式", selection: $tagMode) {
                        Text("热门").tag("popular")
                        Text("最新").tag("latest")
                    }
                    .pickerStyle(.segmented)
                    Stepper("起始页 \(pageFrom)", value: $pageFrom, in: 1...999)
                    Stepper("结束页 \(pageTo)", value: $pageTo, in: pageFrom...999)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Label(isSubmitting ? "创建中" : "开始抓取", systemImage: isSubmitting ? "hourglass" : "play.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(SetuColor.brandPink)
                .disabled(isSubmitting || !canSubmit)
            }
        }
        .setuListRow()
    }

    @ViewBuilder
    private var taskSection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "任务历史")
            switch tasks {
            case .idle, .loading:
                    SetuEmptyState(title: "正在加载任务", systemImage: "tray.full", isLoading: true)
            case .failed(let message):
                    SetuEmptyState(title: "任务加载失败", message: message, systemImage: "tray.full")
            case .loaded(let result):
                if result.tasks.isEmpty {
                        SetuEmptyState(title: "暂无任务", message: "创建抓取任务后会显示在这里。", systemImage: "tray")
                } else {
                    if result.total > result.tasks.count {
                        Text("仅展示最近 \(result.tasks.count) / \(result.total) 个任务")
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                    }
                        ForEach(Array(result.tasks.enumerated()), id: \.element.id) { index, task in
                            if index > 0 {
                                Divider()
                                    .overlay(SetuColor.separator)
                            }
                        PixivTaskRow(task: task) {
                            router.navigate(to: .adminPixivTask(task.taskID))
                        } onCancel: {
                            Task { await cancel(task) }
                        }
                    }
                }
            }
        }
        }
        .setuListRow()
    }

    private var parsedIDs: [Int] {
        (try? PixivPIDInput.parse(idsInput)) ?? []
    }

    private var canSubmit: Bool {
        switch mode {
        case "ids":
            return !parsedIDs.isEmpty
        case "user":
            return !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case "tag":
            return !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }

    private func loadAll() async {
        guard environment.authSession.currentUser?.role == .admin else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadHealth() }
            group.addTask { await loadTasks() }
        }
    }

    private func loadHealth() async {
        health = .loading
        do {
            health = .loaded(try await environment.adminClient.pixivHealth())
        } catch {
            health = .failed(error.localizedDescription)
        }
    }

    private func loadTasks() async {
        tasks = .loading
        do {
            let result = try await environment.adminClient.pixivTasks(limit: 100, offset: 0)
            tasks = .loaded(PixivCrawlerTaskList(
                total: result.total,
                tasks: result.tasks.sorted { left, right in
                    (left.serverTimestamp ?? left.startedAt ?? left.finishedAt ?? "") > (right.serverTimestamp ?? right.startedAt ?? right.finishedAt ?? "")
                }
            ))
        } catch {
            tasks = .failed(error.localizedDescription)
        }
    }

    private func submit() async {
        isSubmitting = true
        message = nil
        do {
            let response: PixivCrawlerActionResponse
            switch mode {
            case "ids":
                response = try await environment.adminClient.crawlPixivByIDs(parsedIDs, skipExisting: skipExisting)
                idsInput = ""
            case "user":
                response = try await environment.adminClient.crawlPixivByUser(userID: userID.trimmingCharacters(in: .whitespacesAndNewlines), skipExisting: skipExisting)
                userID = ""
            case "tag":
                response = try await environment.adminClient.crawlPixivByTag(
                    tag: tag.trimmingCharacters(in: .whitespacesAndNewlines),
                    mode: tagMode,
                    pageFrom: pageFrom,
                    pageTo: pageTo,
                    skipExisting: skipExisting
                )
                tag = ""
            default:
                response = PixivCrawlerActionResponse(taskID: nil, status: nil, message: nil)
            }
            message = response.taskID.map { "任务创建成功：\($0)" } ?? response.message ?? "任务创建成功"
            await loadTasks()
        } catch {
            message = error.localizedDescription
        }
        isSubmitting = false
    }

    private func cancel(_ task: PixivCrawlerTask) async {
        message = nil
        do {
            let response = try await environment.adminClient.cancelPixivTask(taskID: task.taskID)
            message = response.message ?? "任务已取消"
            await loadTasks()
        } catch {
            message = error.localizedDescription
        }
    }
}

struct AdminPixivTaskDetailView: View {
    @Bindable var environment: AppEnvironment
    let taskID: String
    @State private var state: LoadState<PixivCrawlerTask> = .idle
    @State private var message: String?

    var body: some View {
        List {
            if environment.authSession.currentUser?.role != .admin {
                AdminPixivStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后查看任务详情。", systemImage: "shield.slash")
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
        .navigationTitle("任务详情")
        .toolbar {
            if case .loaded(let task) = state, ["pending", "running"].contains(task.status) {
                Button("取消", role: .destructive) {
                    Task { await cancel(task) }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            AdminPixivStateSection(title: "任务", stateTitle: "正在加载任务详情", systemImage: "tray.full", isLoading: true)
        case .failed(let message):
            AdminPixivStateSection(title: "任务", stateTitle: "任务详情加载失败", message: message, systemImage: "tray.full")
        case .loaded(let task):
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "任务", subtitle: task.taskID)
                    AdminPixivMetadataRow(title: "ID", value: task.taskID)
                    AdminPixivMetadataRow(title: "模式", value: task.modeTitle)
                    AdminPixivMetadataRow(title: "状态") {
                        PixivStatusPill(status: task.status, title: task.statusTitle)
                    }
                    if let serverTimestamp = task.serverTimestamp {
                        AdminPixivMetadataRow(title: "服务时间", value: serverTimestamp)
                    }
                    if let startedAt = task.startedAt {
                        AdminPixivMetadataRow(title: "开始时间", value: startedAt)
                    }
                    if let finishedAt = task.finishedAt {
                        AdminPixivMetadataRow(title: "结束时间", value: finishedAt)
                    }
                    if let message = task.message, !message.isEmpty {
                        Text(message)
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                }
            }
            }
            .setuListRow()

            if let progress = task.progress {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "进度", subtitle: "\(progress.percent)%")
                    ProgressView(value: Double(progress.percent), total: 100)
                            .tint(SetuColor.brandPink)
                        AdminPixivMetadataRow(title: "完成", value: "\(progress.done) / \(progress.total)")
                        AdminPixivMetadataRow(title: "新增", value: "\(progress.new)")
                        AdminPixivMetadataRow(title: "跳过", value: "\(progress.skipped)")
                        AdminPixivMetadataRow(title: "失败", value: "\(progress.failed)")
                    }
                }
                .setuListRow()
            }

            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "日志")
                Text(task.logs?.suffix(1200).joined(separator: "\n") ?? "No logs available")
                    .font(.footnote.monospaced())
                        .foregroundStyle(SetuColor.textPrimary)
                    .textSelection(.enabled)
            }
            }
            .setuListRow()
        }
    }

    private func load() async {
        guard environment.authSession.currentUser?.role == .admin else { return }
        state = .loading
        do {
            state = .loaded(try await environment.adminClient.pixivTask(taskID: taskID))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func cancel(_ task: PixivCrawlerTask) async {
        message = nil
        do {
            let response = try await environment.adminClient.cancelPixivTask(taskID: task.taskID)
            message = response.message ?? "任务已取消"
            await load()
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct PixivTaskRow: View {
    let task: PixivCrawlerTask
    let onOpen: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.taskID)
                        .font(.headline.monospaced())
                        .foregroundStyle(SetuColor.textPrimary)
                        .lineLimit(1)
                    Text(task.modeTitle)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                }
                Spacer()
                PixivStatusPill(status: task.status, title: task.statusTitle)
            }

            if let progress = task.progress {
                ProgressView(value: Double(progress.percent), total: 100)
                    .tint(SetuColor.brandPink)
                HStack(spacing: 10) {
                    Label("\(progress.done)/\(progress.total)", systemImage: "chart.bar")
                    Label("新 \(progress.new)", systemImage: "plus.circle")
                    Label("跳 \(progress.skipped)", systemImage: "forward")
                    Label("错 \(progress.failed)", systemImage: "exclamationmark.triangle")
                }
                .font(.caption)
                .foregroundStyle(SetuColor.textTertiary)
            }

            HStack {
                Button(action: onOpen) {
                    Label("详情", systemImage: "doc.text.magnifyingglass")
                        .frame(minHeight: 44)
                }
                Spacer()
                if ["pending", "running"].contains(task.status) {
                    Button(role: .destructive, action: onCancel) {
                        Label("取消", systemImage: "xmark.circle")
                            .frame(minHeight: 44)
                    }
                }
            }
            .buttonStyle(.borderless)
            .font(SetuTypography.caption)
        }
        .padding(.vertical, SetuSpacing.xs)
    }
}

private typealias AdminPixivStateSection = SetuStateSection

private struct AdminPixivMetadataRow<Value: View>: View {
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
                .frame(width: 72, alignment: .leading)
            value
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private extension AdminPixivMetadataRow where Value == Text {
    init(title: String, value: String) {
        self.title = title
        self.value = Text(value)
            .font(SetuTypography.body)
            .foregroundStyle(SetuColor.textPrimary)
    }
}

private struct PixivStatusPill: View {
    let status: String
    let title: String

    var body: some View {
        SetuPill(text: title, systemImage: "flag", tone: tone)
    }

    private var tone: SetuPillTone {
        switch status {
        case "completed":
            .success
        case "failed":
            .danger
        case "cancelled":
            .warning
        case "running":
            .info
        default:
            .muted
        }
    }
}
