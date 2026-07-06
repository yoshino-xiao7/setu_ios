import SetuIOSCore
import SwiftUI

struct AdminAiDeleteRequestsView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<PageResult<AiGenerationDeleteRequest>> = .idle
    @State private var statusFilter = "WAITING"
    @State private var page = 1
    @State private var rejectDraft: AiDeleteRejectDraft?
    @State private var message: String?
    @State private var isSubmitting = false
    private let pageSize = 20

    var body: some View {
        List {
            if environment.authSession.currentUser?.role != .admin {
                ContentUnavailableView("需要管理员权限", systemImage: "shield.slash", description: Text("请使用管理员账号登录后审核 AI 删除申请。"))
            } else {
                filterSection
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
        .navigationTitle("AI 删除申请")
        .sheet(item: $rejectDraft) { draft in
            AiDeleteRejectSheet(draft: draft, isSubmitting: isSubmitting) { reason in
                Task { await reject(draft.request, reason: reason) }
            }
        }
        .task { await load(resetPage: true) }
        .refreshable { await load(resetPage: false) }
    }

    private var filterSection: some View {
        Section("筛选") {
            Picker("状态", selection: $statusFilter) {
                Text("待审核").tag("WAITING")
                Text("全部").tag("ALL")
                Text("已通过").tag("APPROVED")
                Text("已拒绝").tag("REJECTED")
            }
            Button {
                Task { await load(resetPage: true) }
            } label: {
                Label("刷新列表", systemImage: "arrow.clockwise")
            }
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
                ContentUnavailableView("暂无 AI 删除申请", systemImage: "xmark.bin")
            } else {
                Section("共 \(result.total) 条") {
                    ForEach(result.list) { request in
                        AiDeleteRequestRow(request: request) {
                            Task { await approve(request) }
                        } onReject: {
                            rejectDraft = AiDeleteRejectDraft(request: request)
                        }
                        .disabled(isSubmitting)
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
        guard environment.authSession.currentUser?.role == .admin else { return }
        if resetPage {
            page = 1
        }
        state = .loading
        do {
            state = .loaded(try await environment.aiGenerationClient.adminDeleteRequests(
                status: statusFilter,
                page: page,
                pageSize: pageSize
            ))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func approve(_ request: AiGenerationDeleteRequest) async {
        isSubmitting = true
        message = nil
        do {
            let result = try await environment.aiGenerationClient.approveAdminDeleteRequest(id: request.id)
            message = "已通过删除申请 #\(result.id)"
            await load(resetPage: false)
        } catch {
            message = error.localizedDescription
        }
        isSubmitting = false
    }

    private func reject(_ request: AiGenerationDeleteRequest, reason: String) async {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            message = "请填写拒绝原因"
            return
        }
        isSubmitting = true
        message = nil
        do {
            let result = try await environment.aiGenerationClient.rejectAdminDeleteRequest(id: request.id, reason: trimmed)
            message = "已拒绝删除申请 #\(result.id)"
            rejectDraft = nil
            await load(resetPage: false)
        } catch {
            message = error.localizedDescription
        }
        isSubmitting = false
    }
}

private struct AiDeleteRequestRow: View {
    let request: AiGenerationDeleteRequest
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AiDeleteThumbnail(urlString: request.job?.imageUrl, status: request.job?.status)
                VStack(alignment: .leading, spacing: 6) {
                    Text("申请 #\(request.id) · 任务 #\(request.jobId)")
                        .font(.headline)
                    Text(request.job?.promptCn ?? "任务记录不可用")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    HStack(spacing: 8) {
                        RequestStatusBadge(title: request.statusTitle, status: statusBadgeCode)
                        if let jobStatus = request.job?.status {
                            Text(jobStatus)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.14), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let createdAt = request.createdAt {
                        Label(createdAt, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

            if request.status == "WAITING" {
                HStack {
                    Button {
                        onApprove()
                    } label: {
                        Label("通过", systemImage: "checkmark.circle")
                    }
                    Spacer()
                    Button(role: .destructive) {
                        onReject()
                    } label: {
                        Label("拒绝", systemImage: "xmark.circle")
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusBadgeCode: Int {
        switch request.status {
        case "APPROVED": 1
        case "REJECTED": 2
        default: 0
        }
    }
}

private struct AiDeleteThumbnail: View {
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
        .frame(width: 88, height: 88)
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

private struct AiDeleteRejectSheet: View {
    @Environment(\.dismiss) private var dismiss
    let draft: AiDeleteRejectDraft
    let isSubmitting: Bool
    let onSubmit: (String) -> Void
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("拒绝原因") {
                    TextField("填写拒绝原因", text: $reason, axis: .vertical)
                        .lineLimit(4...7)
                }
            }
            .navigationTitle("拒绝申请 #\(draft.request.id)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .destructive) {
                        onSubmit(reason)
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("确认拒绝")
                        }
                    }
                    .disabled(isSubmitting || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct AiDeleteRejectDraft: Identifiable {
    let request: AiGenerationDeleteRequest
    var id: Int { request.id }
}
