import SetuIOSCore
import SwiftUI
#if os(iOS)
struct ArtworkPIDImportView: View {
    let environment: AppEnvironment
    let imported: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var input: String
    @State private var submitting = false
    @State private var error: String?

    init(environment: AppEnvironment, initialPID: String = "", imported: @escaping () -> Void) {
        self.environment = environment; self.imported = imported
        _input = State(initialValue: initialPID)
    }
    var body: some View {
        NavigationStack {
            Form {
                if environment.authSession.currentUser?.role == .admin {
                    Section("通过 PID 新增图片") {
                        Text("成功抓取后直接进入本站图库。已有图片会跳过，缺少的页面会补齐。").font(.caption).foregroundStyle(SetuColor.textSecondary)
                        TextEditor(text: $input).frame(minHeight: 110).disabled(submitting).accessibilityLabel("输入 PID，多个用逗号、空格或换行分隔")
                        Button(submitting ? "正在提交" : "提交 PID") { Task { await submit() } }.disabled(submitting)
                    }
                    if let error { Section { Text(error).foregroundStyle(SetuColor.danger) } }
                } else { Text("需要管理员权限") }
            }
            .navigationTitle("新增图片").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }

        }
    }
    private func submit() async {
        submitting = true; error = nil
        defer { submitting = false }
        do {
            let ids = try PixivPIDInput.parse(input)
            let response = try await environment.adminClient.crawlPixivByIDs(ids, skipExisting: true)
            guard let id = response.taskID, !id.isEmpty else { error = response.message ?? "爬虫未返回任务编号"; return }
            dismiss(); imported()
        } catch { self.error = error.localizedDescription }
    }
}
#endif
