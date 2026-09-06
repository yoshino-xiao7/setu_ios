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

    @State private var pendingAction: (() -> Void)?
    @State private var pendingActionTitle = ""

    var body: some View {
        SetuBoard {
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

                }
                createSection
                taskSection
            }
        }
        .setuBackground()
        .navigationTitle("新增图片")
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

    }

    private var createSection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "新建任务", subtitle: "Pixiv 抓取")
                SetuFilterBar(options: [
                    .init(value: "ids", title: "按 ID"),
                    .init(value: "user", title: "按画师"),
                    .init(value: "tag", title: "按标签")
                ], selection: $mode, accessibilityTitle: "模式")

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
                } else if mode == "user" {
                    TextField("画师 UID", text: $userID)
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField("搜索标签", text: $tag)
                        .textFieldStyle(.roundedBorder)
                    SetuFilterBar(options: [
                    .init(value: "popular", title: "热门"),
                    .init(value: "latest", title: "最新")
                ], selection: $tagMode, accessibilityTitle: "排序模式")

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

    }

    @ViewBuilder
    private var taskSection: some View {
        Group {
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
                        SetuRecordBoard(items: result.tasks) { task in
                        PixivTaskRow(task: task) {
                            router.navigate(to: .adminPixivTask(task.taskID))
                        } onCancel: {
                            pendingActionTitle = "确认取消此抓取任务？"; pendingAction = { Task { await cancel(task) } }
                        }
                    }
                }
            }
        }
        }

    }

    private var parsedIDs: [Int] {
        idsInput
            .split { character in
                character == "," || character == "，" || character == "\n" || character == " "
            }
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
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

    @State private var pendingAction: (() -> Void)?
    @State private var pendingActionTitle = ""

    var body: some View {
        SetuBoard {
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

                }
                content
            }
        }
        .setuBackground()
        .navigationTitle("任务详情")
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
            if case .loaded(let task) = state, ["pending", "running"].contains(task.status) {
                Button("取消", role: .destructive) {
                    pendingActionTitle = "确认取消此抓取任务？"; pendingAction = { Task { await cancel(task) } }
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
            SetuRecordCard(headline: task.taskID, supporting: task.message,
                status: .init(task.statusTitle, tone: task.status == "failed" ? .danger : .brand),
                fields: [.init("模式", task.modeTitle), .init("服务时间", task.serverTimestamp ?? "-"),
                         .init("开始时间", task.startedAt ?? "-"), .init("结束时间", task.finishedAt ?? "-")], density: .compact)

            if let progress = task.progress {
                SetuRecordCard(headline: "进度 \(progress.percent)%",
                    fields: [.init("完成", "\(progress.done) / \(progress.total)"), .init("新增", "\(progress.new)"),
                             .init("跳过", "\(progress.skipped)"), .init("失败", "\(progress.failed)")], density: .compact) {
                    ProgressView(value: Double(progress.percent), total: 100).tint(SetuColor.brandPink)
                }

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
        SetuRecordCard(headline: task.taskID,
            status: .init(task.statusTitle, tone: task.status == "failed" || task.status == "cancelled" ? .danger : .brand),
            fields: [.init("模式", task.modeTitle)] + (task.progress.map { progress in [
                .init("完成", "\(progress.done) / \(progress.total)"), .init("新增", "\(progress.new)"),
                .init("跳过", "\(progress.skipped)"), .init("失败", "\(progress.failed)")
            ] } ?? []), density: .compact) {
            VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                if let progress = task.progress { ProgressView(value: Double(progress.percent), total: 100) }
                HStack {
                    Button("详情", action: onOpen).frame(minHeight: 44)
                    Spacer()
                    if ["pending", "running"].contains(task.status) {
                        Button("取消任务", role: .destructive, action: onCancel).frame(minHeight: 44)
                    }
                }
            }
        }
    }
}

private typealias AdminPixivStateSection = AdminRecordStateSection

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
