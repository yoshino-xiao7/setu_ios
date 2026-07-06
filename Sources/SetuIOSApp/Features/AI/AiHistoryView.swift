import SetuIOSCore
import SwiftUI

struct AiHistoryView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<PageResult<AiGenerationJob>> = .idle
    @State private var statusFilter = ""

    var body: some View {
        List {
            Picker("状态", selection: $statusFilter) {
                Text("全部").tag("")
                Text("排队中").tag("QUEUED")
                Text("生成中").tag("RUNNING")
                Text("已完成").tag("COMPLETED")
                Text("失败").tag("FAILED")
            }
            .pickerStyle(.segmented)
            .onChange(of: statusFilter) {
                Task { await load() }
            }

            switch state {
            case .idle, .loading:
                ProgressView("正在加载")
            case .failed(let message):
                ContentUnavailableView("历史加载失败", systemImage: "clock.badge.exclamationmark", description: Text(message))
            case .loaded(let page):
                if page.list.isEmpty {
                    ContentUnavailableView("暂无 AI 生成记录", systemImage: "sparkles", description: Text("创建绘图任务后，任务状态和结果会显示在这里。"))
                } else {
                    Section("共 \(page.total) 条") {
                        ForEach(page.list) { job in
                            Button {
                                router.navigate(to: .aiGenerationDetail(job.id))
                            } label: {
                                AiGenerationRow(job: job)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("AI 绘图历史")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await environment.aiGenerationClient.listMine(status: statusFilter))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct AiGenerationRow: View {
    let job: AiGenerationJob

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.promptCn)
                        .font(.headline)
                        .lineLimit(2)
                    Text("#\(job.id) · \(job.width)x\(job.height) · \(job.steps) 步")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(title: job.statusTitle, status: job.status)
            }

            if let detail = job.userErrorMessage ?? job.workerDetail, !detail.isEmpty {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(job.status == "FAILED" ? .red : .secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                if let cost = job.pointsCost {
                    Label("\(cost) 积分", systemImage: "bolt.circle")
                }
                if job.publicVisible == true {
                    Label("公开", systemImage: "globe")
                }
                if let createdAt = job.createdAt {
                    Label(createdAt, systemImage: "calendar")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct StatusBadge: View {
    let title: String
    let status: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case "COMPLETED": .green
        case "FAILED": .red
        case "RUNNING", "UPLOADING": .blue
        default: .orange
        }
    }
}
