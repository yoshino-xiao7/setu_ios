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
                ContentUnavailableView("需要管理员权限", systemImage: "shield.slash", description: Text("请使用管理员账号登录后创建 Pixiv 抓取任务。"))
            } else {
                healthSection
                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                createSection
                taskSection
            }
        }
        .navigationTitle("新增图片")
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    @ViewBuilder
    private var healthSection: some View {
        Section("爬虫服务") {
            switch health {
            case .idle, .loading:
                ProgressView("正在检查服务")
            case .failed(let message):
                Label(message, systemImage: "xmark.circle")
                    .foregroundStyle(.red)
            case .loaded(let health):
                HStack {
                    Label(health.isOnline ? "服务在线" : "服务状态：\(health.status ?? "-")", systemImage: "pulse")
                        .foregroundStyle(health.isOnline ? .green : .orange)
                    Spacer()
                    Text(health.environment ?? "-")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("数据库", value: health.database ?? "-")
            }
        }
    }

    private var createSection: some View {
        Section("新建任务") {
            Picker("模式", selection: $mode) {
                Text("按 ID").tag("ids")
                Text("按画师").tag("user")
                Text("按标签").tag("tag")
            }
            Toggle("跳过已存在", isOn: $skipExisting)

            if mode == "ids" {
                TextEditor(text: $idsInput)
                    .frame(minHeight: 96)
                    .overlay(alignment: .topLeading) {
                        if idsInput.isEmpty {
                            Text("输入 PID，多个用逗号、空格或换行分隔")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                    }
            } else if mode == "user" {
                TextField("画师 UID", text: $userID)
            } else {
                TextField("搜索标签", text: $tag)
                Picker("排序模式", selection: $tagMode) {
                    Text("热门").tag("popular")
                    Text("最新").tag("latest")
                }
                Stepper("起始页 \(pageFrom)", value: $pageFrom, in: 1...999)
                Stepper("结束页 \(pageTo)", value: $pageTo, in: pageFrom...999)
            }

            Button {
                Task { await submit() }
            } label: {
                if isSubmitting {
                    ProgressView()
                } else {
                    Label("开始抓取", systemImage: "play.circle")
                }
            }
            .disabled(isSubmitting || !canSubmit)
        }
    }

    @ViewBuilder
    private var taskSection: some View {
        Section("任务历史") {
            switch tasks {
            case .idle, .loading:
                ProgressView("正在加载任务")
            case .failed(let message):
                ContentUnavailableView("任务加载失败", systemImage: "tray.full", description: Text(message))
            case .loaded(let result):
                if result.tasks.isEmpty {
                    ContentUnavailableView("暂无任务", systemImage: "tray")
                } else {
                    if result.total > result.tasks.count {
                        Text("仅展示最近 \(result.tasks.count) / \(result.total) 个任务")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(result.tasks) { task in
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

    var body: some View {
        List {
            if environment.authSession.currentUser?.role != .admin {
                ContentUnavailableView("需要管理员权限", systemImage: "shield.slash", description: Text("请使用管理员账号登录后查看任务详情。"))
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
            ProgressView("正在加载任务详情")
        case .failed(let message):
            ContentUnavailableView("任务详情加载失败", systemImage: "tray.full", description: Text(message))
        case .loaded(let task):
            Section("任务") {
                LabeledContent("ID", value: task.taskID)
                LabeledContent("模式", value: task.modeTitle)
                LabeledContent("状态", value: task.statusTitle)
                if let serverTimestamp = task.serverTimestamp {
                    LabeledContent("服务时间", value: serverTimestamp)
                }
                if let startedAt = task.startedAt {
                    LabeledContent("开始时间", value: startedAt)
                }
                if let finishedAt = task.finishedAt {
                    LabeledContent("结束时间", value: finishedAt)
                }
                if let message = task.message, !message.isEmpty {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }

            if let progress = task.progress {
                Section("进度") {
                    ProgressView(value: Double(progress.percent), total: 100)
                    LabeledContent("完成", value: "\(progress.done) / \(progress.total)")
                    LabeledContent("新增", value: "\(progress.new)")
                    LabeledContent("跳过", value: "\(progress.skipped)")
                    LabeledContent("失败", value: "\(progress.failed)")
                }
            }

            Section("日志") {
                Text(task.logs?.suffix(1200).joined(separator: "\n") ?? "No logs available")
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.taskID)
                        .font(.headline.monospaced())
                        .lineLimit(1)
                    Text(task.modeTitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(task.statusTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            if let progress = task.progress {
                ProgressView(value: Double(progress.percent), total: 100)
                HStack(spacing: 10) {
                    Label("\(progress.done)/\(progress.total)", systemImage: "chart.bar")
                    Label("新 \(progress.new)", systemImage: "plus.circle")
                    Label("跳 \(progress.skipped)", systemImage: "forward")
                    Label("错 \(progress.failed)", systemImage: "exclamationmark.triangle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Button("详情", action: onOpen)
                Spacer()
                if ["pending", "running"].contains(task.status) {
                    Button("取消", role: .destructive, action: onCancel)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch task.status {
        case "completed":
            return .green
        case "failed":
            return .red
        case "cancelled":
            return .orange
        case "running":
            return .blue
        default:
            return .secondary
        }
    }
}
