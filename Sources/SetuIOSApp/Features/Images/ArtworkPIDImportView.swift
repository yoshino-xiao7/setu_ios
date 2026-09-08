import SetuIOSCore
import SwiftUI
#if os(iOS)
struct ArtworkPIDImportView: View {
    let environment: AppEnvironment
    let imported: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var input: String
    @State private var submitting = false
    @State private var task: PixivCrawlerTask?
    @State private var taskID: String?
    @State private var error: String?
    @State private var refresh = UUID()

    init(environment: AppEnvironment, initialPID: String = "", imported: @escaping () -> Void) {
        self.environment = environment; self.imported = imported
        _input = State(initialValue: initialPID)
    }
    private var running: Bool { taskID != nil && (task == nil || ["pending", "running"].contains(task?.status ?? "")) }
    var body: some View {
        NavigationStack {
            Form {
                if environment.authSession.currentUser?.role == .admin {
                    Section("通过 PID 新增图片") {
                        Text("成功抓取后直接进入本站图库。已有图片会跳过，缺少的页面会补齐。").font(.caption).foregroundStyle(SetuColor.textSecondary)
                        TextEditor(text: $input).frame(minHeight: 110).disabled(running).accessibilityLabel("输入 PID，多个用逗号、空格或换行分隔")
                        Button(submitting ? "正在提交" : "提交 PID") { Task { await submit() } }.disabled(submitting || running)
                    }
                    if let error { Section { Text(error).foregroundStyle(SetuColor.danger) } }
                    if let task {
                        Section("任务状态：\(task.statusTitle)") {
                            if let progress = task.progress {
                                ProgressView(value: Double(progress.done), total: Double(max(1, progress.total)))
                                Text("新增 \(progress.new) · 跳过 \(progress.skipped) · 失败 \(progress.failed)").font(.caption)
                            }
                            ForEach(task.results ?? []) { result in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("PID \(result.pid)")
                                    Text(result.galleryVerified == true ? "已进入图库" : result.message ?? "尚未核验入库")
                                        .font(.caption).foregroundStyle(result.galleryVerified == true ? SetuColor.success : SetuColor.textSecondary)
                                    if result.galleryVerified != true && !running {
                                        Button("重试此 PID") { input = String(result.pid); Task { await submit() } }.disabled(submitting)
                                    }
                                }
                            }
                            if !running && task.results?.isEmpty != false { Text("爬虫未返回逐 PID 核验结果，请到后台检查。").font(.caption) }
                            Button("刷新状态") { refresh = UUID() }
                        }
                    } else if taskID != nil { ProgressView("正在获取任务状态") }
                } else { Text("需要管理员权限") }
            }
            .navigationTitle("新增图片").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .task(id: "\(taskID ?? "")-\(refresh)") {
                guard let taskID else { return }
                do {
                    while !Task.isCancelled {
                        let result = try await environment.adminClient.pixivTask(taskID: taskID)
                        try Task.checkCancellation()
                        task = result
                        if !["pending", "running"].contains(result.status) {
                            if result.results?.contains(where: { $0.galleryVerified == true }) == true { imported() }
                            return
                        }
                        try await Task.sleep(for: .seconds(3))
                    }
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
        }
    }
    private func submit() async {
        submitting = true; error = nil
        defer { submitting = false }
        do {
            let ids = try PixivPIDInput.parse(input)
            let response = try await environment.adminClient.crawlPixivByIDs(ids, skipExisting: true)
            guard let id = response.taskID else { error = response.message ?? "爬虫未返回任务编号"; return }
            task = nil; taskID = id
        } catch { self.error = error.localizedDescription }
    }
}
#endif
