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
        SetuBoard {
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

                }
                content
            }
        }
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
                SetuFilterBar(options: [
                    .init(value: "WAITING", title: "待审核"),
                    .init(value: "ALL", title: "全部"),
                    .init(value: "APPROVED", title: "已通过"),
                    .init(value: "REJECTED", title: "已拒绝")
                ], selection: $statusFilter, accessibilityTitle: "状态")

                SetuFilterBar(options: [
                    .init(value: "ALL", title: "全部"),
                    .init(value: "GENERAL", title: "全年龄"),
                    .init(value: "R18", title: "R18")
                ], selection: $categoryFilter, accessibilityTitle: "分类")

                Button {
                    Task { await load(resetPage: true) }
                } label: {
                    Label("刷新队列", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(SetuColor.brandOnLight)
                .foregroundStyle(.white)
            }
        }

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
                Group {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "共 \(result.total) 条", subtitle: "AI 审核")
                    SetuRecordBoard(items: result.list) { review in
                        AiReviewRow(review: review) {
                            Task { await approve(review) }
                        } onReject: {
                            rejectDraft = AiReviewRejectDraft(review: review)
                        }
                        .disabled(isSubmitting)
                    }
                }
                }

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
        SetuRecordCard(headline: "审核 #\(review.id) · 任务 #\(review.jobId)", supporting: review.job?.promptCn,
            status: .init(review.statusTitle, tone: review.status == "REJECTED" ? .danger : .brand),
            thumbnailURLString: review.job?.imageUrl,
            fields: [.init("分类", review.categoryTitle), .init("创建时间", review.createdAt ?? "-"),
                     .init("投稿说明", review.submitNote ?? "-"), .init("拒绝原因", review.rejectReason ?? "-")], density: .compact) {
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
    }

    private var statusBadgeCode: Int {
        switch review.status {
        case "APPROVED": 1
        case "REJECTED": 2
        default: 0
        }
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
            SetuBoard {
                SetuRecordCard(headline: "操作确认", status: .init("请核对原因与目标", tone: .danger), density: .compact) {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "拒绝原因", subtitle: "审核 #\(draft.review.id)")
                    TextField("填写拒绝原因", text: $reason, axis: .vertical)
                        .lineLimit(4...7)
                            .textFieldStyle(.roundedBorder)
                }
                }

            }
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

private typealias AdminAiReviewStateSection = AdminRecordStateSection

private struct AiReviewRejectDraft: Identifiable {
    let review: AiGenerationReview
    var id: Int { review.id }
}
