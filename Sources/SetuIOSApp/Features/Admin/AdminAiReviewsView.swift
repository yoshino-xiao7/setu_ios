import SetuIOSCore
import SwiftUI

struct AdminAiReviewsView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<PageResult<AiGenerationReview>> = .idle
    @State private var statusFilter = "WAITING"
    @State private var categoryFilter = "ALL"
    @State private var page = 1
    @State private var rejectDraft: AiReviewRejectDraft?
    @State private var message: String?
    @State private var isSubmitting = false
    private let pageSize = 20

    var body: some View {
        List {
            if environment.authSession.currentUser?.role != .admin {
                ContentUnavailableView("需要管理员权限", systemImage: "shield.slash", description: Text("请使用管理员账号登录后审核 AI 作品。"))
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
        .navigationTitle("AI 审核队列")
        .sheet(item: $rejectDraft) { draft in
            AiReviewRejectSheet(draft: draft, isSubmitting: isSubmitting) { reason in
                Task { await reject(draft.review, reason: reason) }
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
            Picker("分类", selection: $categoryFilter) {
                Text("全部").tag("ALL")
                Text("全年龄").tag("GENERAL")
                Text("R18").tag("R18")
            }
            Button {
                Task { await load(resetPage: true) }
            } label: {
                Label("刷新队列", systemImage: "arrow.clockwise")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ProgressView("正在加载 AI 审核队列")
        case .failed(let message):
            ContentUnavailableView("AI 审核队列加载失败", systemImage: "checklist", description: Text(message))
        case .loaded(let result):
            if result.list.isEmpty {
                ContentUnavailableView("暂无审核任务", systemImage: "checklist")
            } else {
                Section("共 \(result.total) 条") {
                    ForEach(result.list) { review in
                        AiReviewRow(review: review) {
                            Task { await approve(review) }
                        } onReject: {
                            rejectDraft = AiReviewRejectDraft(review: review)
                        }
                        .disabled(isSubmitting)
                    }
                }
                pagerSection(result)
            }
        }
    }

    private func pagerSection(_ result: PageResult<AiGenerationReview>) -> some View {
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
            state = .loaded(try await environment.aiGenerationClient.adminReviews(
                status: statusFilter,
                category: categoryFilter,
                page: page,
                pageSize: pageSize
            ))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func approve(_ review: AiGenerationReview) async {
        isSubmitting = true
        message = nil
        do {
            let result = try await environment.aiGenerationClient.approveAdminReview(id: review.id)
            message = "已通过审核 #\(result.id)"
            await load(resetPage: false)
        } catch {
            message = error.localizedDescription
        }
        isSubmitting = false
    }

    private func reject(_ review: AiGenerationReview, reason: String) async {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            message = "请填写拒绝原因"
            return
        }
        isSubmitting = true
        message = nil
        do {
            let result = try await environment.aiGenerationClient.rejectAdminReview(id: review.id, reason: trimmed)
            message = "已拒绝审核 #\(result.id)"
            rejectDraft = nil
            await load(resetPage: false)
        } catch {
            message = error.localizedDescription
        }
        isSubmitting = false
    }
}

private struct AiReviewRow: View {
    let review: AiGenerationReview
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AiReviewThumbnail(urlString: review.job?.imageUrl)
                VStack(alignment: .leading, spacing: 6) {
                    Text("审核 #\(review.id) · 任务 #\(review.jobId)")
                        .font(.headline)
                    Text(review.job?.promptCn ?? "无提示词")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    HStack(spacing: 8) {
                        RequestStatusBadge(title: review.statusTitle, status: statusBadgeCode)
                        Text(review.categoryTitle)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((review.category == "R18" ? Color.red : Color.green).opacity(0.14), in: Capsule())
                            .foregroundStyle(review.category == "R18" ? .red : .green)
                    }
                    if let createdAt = review.createdAt {
                        Label(createdAt, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let note = review.submitNote, !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let reason = review.rejectReason, !reason.isEmpty {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if review.status == "WAITING" {
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
        switch review.status {
        case "APPROVED": 1
        case "REJECTED": 2
        default: 0
        }
    }
}

private struct AiReviewThumbnail: View {
    let urlString: String?

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
        Image(systemName: "photo")
            .foregroundStyle(.pink)
    }
}

private struct AiReviewRejectSheet: View {
    @Environment(\.dismiss) private var dismiss
    let draft: AiReviewRejectDraft
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
            .navigationTitle("拒绝审核 #\(draft.review.id)")
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

private struct AiReviewRejectDraft: Identifiable {
    let review: AiGenerationReview
    var id: Int { review.id }
}
