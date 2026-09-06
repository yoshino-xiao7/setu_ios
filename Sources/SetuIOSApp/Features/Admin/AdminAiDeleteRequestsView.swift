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

    @State private var pendingAction: (() -> Void)?
    @State private var pendingActionTitle = ""

    var body: some View {
        SetuBoard {
            if environment.authSession.currentUser?.role != .admin {
                AdminAiDeleteStateSection(
                    title: "权限",
                    stateTitle: "需要管理员权限",
                    message: "请使用管理员账号登录后审核 AI 删除申请。",
                    systemImage: "shield.slash"
                )
            } else {
                filterSection
                if let message {
                    Group {
                        SetuCard {
                            SetuPill(text: message, systemImage: "checkmark.circle", tone: .info)
                        }

                    }
                }
                content
            }
        }
        .setuBackground()
        .navigationTitle("AI 删除申请")
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
        .sheet(item: $rejectDraft) { draft in
            AiDeleteRejectSheet(draft: draft, isSubmitting: isSubmitting) { reason in
                Task { await reject(draft.request, reason: reason) }
            }
        }
        .task { await load(resetPage: true) }
        .refreshable { await load(resetPage: false) }
    }

    private var filterSection: some View {
        Group {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "筛选")
                    SetuFilterBar(options: [
                    .init(value: "WAITING", title: "待审核"),
                    .init(value: "ALL", title: "全部"),
                    .init(value: "APPROVED", title: "已通过"),
                    .init(value: "REJECTED", title: "已拒绝")
                ], selection: $statusFilter, accessibilityTitle: "状态")

                    SetuPrimaryButton {
                        Task { await load(resetPage: true) }
                    } label: {
                        Label("刷新列表", systemImage: "arrow.clockwise")
                    }
                }
            }

        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            AdminAiDeleteStateSection(title: "删除申请", stateTitle: "正在加载 AI 删除申请", systemImage: "xmark.bin", isLoading: true)
        case .failed(let message):
            AdminAiDeleteStateSection(title: "删除申请", stateTitle: "AI 删除申请加载失败", message: message, systemImage: "exclamationmark.triangle")
        case .loaded(let result):
            if result.list.isEmpty {
                AdminAiDeleteStateSection(title: "删除申请", stateTitle: "暂无 AI 删除申请", systemImage: "xmark.bin")
            } else {
                Group {
                    Group {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "删除申请", subtitle: "共 \(result.total) 条")
                            VStack(spacing: 0) {
                                SetuRecordBoard(items: result.list) { request in
                                    AiDeleteRequestRow(request: request) {
                                        pendingActionTitle = "确认批准删除此 AI 作品？"; pendingAction = { Task { await approve(request) } }
                                    } onReject: {
                                        rejectDraft = AiDeleteRejectDraft(request: request)
                                    }
                                    .disabled(isSubmitting)
                                }
                            }
                        }
                    }

                }
                pagerSection(result)
            }
        }
    }

    private func pagerSection(_ result: PageResult<AiGenerationDeleteRequest>) -> some View {
        Group {
            SetuCard {
                HStack(spacing: SetuSpacing.md) {
                    Button {
                        Task {
                            page = max(1, page - 1)
                            await load(resetPage: false)
                        }
                    } label: {
                        Label("上一页", systemImage: "chevron.left")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(page <= 1 ? SetuColor.textTertiary : SetuColor.brandInk)
                    .frame(minHeight: 44)
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
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(result.page * result.pageSize >= result.total ? SetuColor.textTertiary : SetuColor.brandInk)
                    .frame(minHeight: 44)
                    .disabled(result.page * result.pageSize >= result.total)
                }
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

private typealias AdminAiDeleteStateSection = AdminRecordStateSection

private struct AiDeleteRequestRow: View {
    let request: AiGenerationDeleteRequest
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        SetuRecordCard(headline: "申请 #\(request.id) · 任务 #\(request.jobId)", supporting: request.job?.promptCn,
            status: .init(request.statusTitle, tone: .danger), thumbnailURLString: request.job?.imageUrl,
            fields: [.init("任务状态", request.job?.status ?? "-"), .init("创建时间", request.createdAt ?? "-"),
                     .init("申请原因", request.reason ?? "-"), .init("拒绝原因", request.rejectReason ?? "-")], density: .compact) {
            if request.status == "WAITING" {
                HStack(spacing: SetuSpacing.md) {
                    Button {
                        onApprove()
                    } label: {
                        Label("通过", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SetuColor.success)
                    .background(SetuColor.success.opacity(0.12), in: Capsule())
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        onReject()
                    } label: {
                        Label("拒绝", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SetuColor.danger)
                    .background(SetuColor.danger.opacity(0.12), in: Capsule())
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var statusBadgeCode: Int {
        switch request.status {
        case "APPROVED": 1
        case "REJECTED": 2
        default: 0
        }
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
            SetuBoard {
                Group {
                    SetuRecordCard(headline: "操作确认", status: .init("请核对原因与目标", tone: .danger), density: .compact) {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "拒绝原因")
                            TextField("填写拒绝原因", text: $reason, axis: .vertical)
                                .lineLimit(4...7)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                }
            }
            .setuBackground()
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
                            Label("提交中", systemImage: "hourglass")
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
