import SetuIOSCore
import SwiftUI

struct AiDeleteRequestsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<PageResult<AiGenerationDeleteRequest>> = .idle
    @State private var statusFilter = "ALL"
    @State private var page = 1
    private let pageSize = 20

    var body: some View {
        NavigationStack {
            List {
                Section("筛选") {
                    Picker("状态", selection: $statusFilter) {
                        Text("全部").tag("ALL")
                        Text("待审核").tag("WAITING")
                        Text("已通过").tag("APPROVED")
                        Text("已拒绝").tag("REJECTED")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: statusFilter) {
                        Task { await load(resetPage: true) }
                    }
                }

                content
            }
            .navigationTitle("AI 删除申请")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await load(resetPage: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task { await load(resetPage: true) }
            .refreshable { await load(resetPage: false) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ProgressView("正在加载 AI 删除申请")
        case .failed(let message):
            ContentUnavailableView("AI 删除申请加载失败", systemImage: "xmark.bin", description: Text(message))
        case .loaded(let result):
            if result.list.isEmpty {
                ContentUnavailableView("暂无 AI 删除申请", systemImage: "xmark.bin", description: Text("在 AI 任务详情中提交删除申请后，会显示在这里。"))
            } else {
                Section("共 \(result.total) 条") {
                    ForEach(result.list) { request in
                        UserAiDeleteRequestRow(request: request)
                    }
                }
                pagerSection(result)
            }
        }
    }

    private func pagerSection(_ result: PageResult<AiGenerationDeleteRequest>) -> some View {
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
        if resetPage {
            page = 1
        }
        state = .loading
        do {
            state = .loaded(try await environment.aiGenerationClient.deleteRequests(
                status: statusFilter,
                page: page,
                pageSize: pageSize
            ))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct UserAiDeleteRequestRow: View {
    let request: AiGenerationDeleteRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AiDeleteRequestThumbnail(urlString: request.job?.imageUrl, status: request.job?.status)
                VStack(alignment: .leading, spacing: 6) {
                    Text("申请 #\(request.id) · 任务 #\(request.jobId)")
                        .font(.headline)
                    Text(request.job?.promptCn ?? "任务记录不可用")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    HStack(spacing: 8) {
                        StatusBadge(title: request.statusTitle, status: request.status)
                        if let createdAt = request.createdAt {
                            Label(createdAt, systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let reason = request.reason, !reason.isEmpty {
                Text("申请原因：\(reason)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let rejectReason = request.rejectReason, !rejectReason.isEmpty {
                Text("拒绝原因：\(rejectReason)")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let reviewedAt = request.reviewedAt {
                Label("审核时间：\(reviewedAt)", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AiDeleteRequestThumbnail: View {
    let urlString: String?
    let status: String?

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 72, height: 72)
        .background(.pink.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        VStack(spacing: 4) {
            Image(systemName: "photo")
            if let status {
                Text(status)
                    .font(.caption2)
            }
        }
        .foregroundStyle(.pink)
    }
}
