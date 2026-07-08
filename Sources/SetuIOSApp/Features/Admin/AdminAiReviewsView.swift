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
                AdminAiReviewStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后审核 AI 作品。", systemImage: "shield.slash")
            } else {
                filterSection
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
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "筛选")
                Picker("状态", selection: $statusFilter) {
                    Text("待审核").tag("WAITING")
                    Text("全部").tag("ALL")
                    Text("已通过").tag("APPROVED")
                    Text("已拒绝").tag("REJECTED")
                }
                .pickerStyle(.segmented)
                Picker("分类", selection: $categoryFilter) {
                    Text("全部").tag("ALL")
                    Text("全年龄").tag("GENERAL")
                    Text("R18").tag("R18")
                }
                .pickerStyle(.segmented)
                Button {
                    Task { await load(resetPage: true) }
                } label: {
                    Label("刷新队列", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(SetuColor.brandPink)
            }
        }
        .setuListRow()
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            AdminAiReviewStateSection(title: "审核队列", stateTitle: "正在加载 AI 审核队列", systemImage: "checklist", isLoading: true)
        case .failed(let message):
            AdminAiReviewStateSection(title: "审核队列", stateTitle: "AI 审核队列加载失败", message: message, systemImage: "checklist")
        case .loaded(let result):
            if result.list.isEmpty {
                AdminAiReviewStateSection(title: "审核队列", stateTitle: "暂无审核任务", systemImage: "checklist")
            } else {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "共 \(result.total) 条", subtitle: "AI 审核")
                    ForEach(Array(result.list.enumerated()), id: \.element.id) { index, review in
                            if index > 0 {
                                Divider()
                                    .overlay(SetuColor.separator)
                            }
                        AiReviewRow(review: review) {
                            Task { await approve(review) }
                        } onReject: {
                            rejectDraft = AiReviewRejectDraft(review: review)
                        }
                        .disabled(isSubmitting)
                    }
                }
                }
                .setuListRow()
                pagerSection(result)
            }
        }
    }

    private func pagerSection(_ result: PageResult<AiGenerationReview>) -> some View {
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
        .setuListRow()
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
        VStack(alignment: .leading, spacing: SetuSpacing.md) {
            HStack(alignment: .top, spacing: SetuSpacing.md) {
                AiReviewThumbnail(urlString: review.job?.imageUrl)
                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                    Text("审核 #\(review.id) · 任务 #\(review.jobId)")
                        .font(SetuTypography.headline)
                        .foregroundStyle(SetuColor.textPrimary)
                    Text(review.job?.promptCn ?? "无提示词")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .lineLimit(3)
                    HStack(spacing: 8) {
                        RequestStatusBadge(title: review.statusTitle, status: statusBadgeCode)
                        SetuPill(
                            text: review.categoryTitle,
                            systemImage: review.category == "R18" ? "exclamationmark.triangle" : "checkmark.seal",
                            tone: review.category == "R18" ? .danger : .success
                        )
                    }
                    if let createdAt = review.createdAt {
                        Label(createdAt, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(SetuColor.textTertiary)
                    }
                }
            }

            if let note = review.submitNote, !note.isEmpty {
                Text(note)
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            }
            if let reason = review.rejectReason, !reason.isEmpty {
                Text(reason)
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.danger)
            }

            if review.status == "WAITING" {
                HStack {
                    Button {
                        onApprove()
                    } label: {
                        Label("通过", systemImage: "checkmark.circle")
                            .frame(minHeight: 44)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        onReject()
                    } label: {
                        Label("拒绝", systemImage: "xmark.circle")
                            .frame(minHeight: 44)
                    }
                }
                .buttonStyle(.borderless)
                .font(SetuTypography.caption)
            }
        }
        .padding(.vertical, SetuSpacing.xs)
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
        .background(SetuColor.brandSoft.opacity(0.12), in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous)
                .stroke(SetuColor.separator, lineWidth: 1)
        }
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .foregroundStyle(SetuColor.brandPink)
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
            List {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "拒绝原因", subtitle: "审核 #\(draft.review.id)")
                    TextField("填写拒绝原因", text: $reason, axis: .vertical)
                        .lineLimit(4...7)
                            .textFieldStyle(.roundedBorder)
                }
                }
                .setuListRow()
            }
            .listStyle(.plain)
            .setuBackground()
            .navigationTitle("拒绝审核 #\(draft.review.id)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .destructive) {
                        onSubmit(reason)
                    } label: {
                        Text(isSubmitting ? "提交中" : "确认拒绝")
                    }
                    .disabled(isSubmitting || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct AdminAiReviewStateSection: View {
    let title: String
    let stateTitle: String
    var message: String?
    var systemImage: String
    var isLoading = false

    var body: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: title)
                SetuEmptyState(title: stateTitle, message: message, systemImage: systemImage, isLoading: isLoading)
            }
        }
        .setuListRow()
    }
}

private struct AiReviewRejectDraft: Identifiable {
    let review: AiGenerationReview
    var id: Int { review.id }
}
