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
                AdminAiDeleteStateSection(
                    title: "权限",
                    stateTitle: "需要管理员权限",
                    message: "请使用管理员账号登录后审核 AI 删除申请。",
                    systemImage: "shield.slash"
                )
            } else {
                filterSection
                if let message {
                    Section {
                        SetuCard {
                            SetuPill(text: message, systemImage: "checkmark.circle", tone: .info)
                        }
                        .setuListRow()
                    }
                }
                content
            }
        }
        .listStyle(.plain)
        .setuBackground()
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
        Section {
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

                    SetuPrimaryButton {
                        Task { await load(resetPage: true) }
                    } label: {
                        Label("刷新列表", systemImage: "arrow.clockwise")
                    }
                }
            }
            .setuListRow()
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
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "删除申请", subtitle: "共 \(result.total) 条")
                            VStack(spacing: 0) {
                                ForEach(Array(result.list.enumerated()), id: \.element.id) { index, request in
                                    AiDeleteRequestRow(request: request) {
                                        Task { await approve(request) }
                                    } onReject: {
                                        rejectDraft = AiDeleteRejectDraft(request: request)
                                    }
                                    .disabled(isSubmitting)

                                    if index < result.list.count - 1 {
                                        Divider().overlay(SetuColor.separator)
                                    }
                                }
                            }
                        }
                    }
                    .setuListRow()
                }
                pagerSection(result)
            }
        }
    }

    private func pagerSection(_ result: PageResult<AiGenerationDeleteRequest>) -> some View {
        Section {
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
            .setuListRow()
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

private struct AdminAiDeleteStateSection: View {
    let title: String
    let stateTitle: String
    var message: String?
    var systemImage: String
    var isLoading = false

    var body: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: title)
                    SetuEmptyState(title: stateTitle, message: message, systemImage: systemImage, isLoading: isLoading)
                }
            }
            .setuListRow()
        }
    }
}

private struct AiDeleteRequestRow: View {
    let request: AiGenerationDeleteRequest
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.md) {
            HStack(alignment: .top, spacing: SetuSpacing.md) {
                AiDeleteThumbnail(urlString: request.job?.imageUrl, status: request.job?.status)
                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                    Text("申请 #\(request.id) · 任务 #\(request.jobId)")
                        .font(SetuTypography.headline)
                        .foregroundStyle(SetuColor.textPrimary)
                    Text(request.job?.promptCn ?? "任务记录不可用")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .lineLimit(3)
                    HStack(spacing: 8) {
                        RequestStatusBadge(title: request.statusTitle, status: statusBadgeCode)
                        if let jobStatus = request.job?.status {
                            Text(jobStatus)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, SetuSpacing.sm)
                                .padding(.vertical, SetuSpacing.xs)
                                .background(SetuColor.surfaceMuted, in: Capsule())
                                .foregroundStyle(SetuColor.textSecondary)
                        }
                    }
                    if let createdAt = request.createdAt {
                        Label(createdAt, systemImage: "calendar")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                    }
                }
            }

            if let reason = request.reason, !reason.isEmpty {
                Text("申请原因：\(reason)")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            }
            if let rejectReason = request.rejectReason, !rejectReason.isEmpty {
                SetuPill(text: "拒绝原因：\(rejectReason)", systemImage: "xmark.circle", tone: .danger)
            }

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
        .padding(.vertical, SetuSpacing.sm)
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
        .background(SetuColor.brandSoft.opacity(0.18), in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
    }

    private var placeholder: some View {
        VStack(spacing: 4) {
            Image(systemName: "photo")
            if let status {
                Text(status)
                    .font(.caption2)
            }
        }
        .foregroundStyle(SetuColor.brandPink)
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
            List {
                Section {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "拒绝原因")
                            TextField("填写拒绝原因", text: $reason, axis: .vertical)
                                .lineLimit(4...7)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .setuListRow()
                }
            }
            .listStyle(.plain)
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
