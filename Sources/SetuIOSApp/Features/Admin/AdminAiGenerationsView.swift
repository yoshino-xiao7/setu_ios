import SetuIOSCore
import SwiftUI

struct AdminAiGenerationsView: View {
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<PageResult<AiGenerationJob>> = .idle
    @State private var jobIdText = ""
    @State private var userIdText = ""
    @State private var statusFilter = "ALL"
    @State private var reviewStatusFilter = "ALL"
    @State private var deleteStatusFilter = "ALL"
    @State private var recordStateFilter = "ALL"
    @State private var page = 1
    @State private var reasonDraft: AiGenerationReasonDraft?
    @State private var message: String?
    @State private var isSubmitting = false
    private let pageSize = 12

    var body: some View {
        List {
            if environment.authSession.currentUser?.role != .admin {
                AdminAiGenerationStateSection(
                    title: "权限",
                    stateTitle: "需要管理员权限",
                    message: "请使用管理员账号登录后管理 AI 生成记录。",
                    systemImage: "shield.slash"
                )
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
        .navigationTitle("AI 生成记录")
        .sheet(item: $reasonDraft) { draft in
            AiGenerationReasonSheet(draft: draft, isSubmitting: isSubmitting) { reason in
                Task { await submitReasonAction(draft, reason: reason) }
            }
        }
        .task { await load(resetPage: true) }
        .refreshable { await load(resetPage: false) }
    }

    private var filterSection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "筛选", subtitle: "管理后台")
                TextField("任务 ID", text: $jobIdText)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                TextField("用户 ID", text: $userIdText)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Picker("生成状态", selection: $statusFilter) {
                    Text("全部").tag("ALL")
                    Text("排队中").tag("QUEUED")
                    Text("已接单").tag("CLAIMED")
                    Text("生成中").tag("RUNNING")
                    Text("上传中").tag("UPLOADING")
                    Text("已完成").tag("COMPLETED")
                    Text("失败").tag("FAILED")
                }
                Picker("广场审核", selection: $reviewStatusFilter) {
                    Text("全部").tag("ALL")
                    Text("未提交").tag("NOT_SUBMITTED")
                    Text("待审核").tag("WAITING")
                    Text("已通过").tag("APPROVED")
                    Text("已拒绝").tag("REJECTED")
                    Text("已下架").tag("UNPUBLISHED")
                }
                Picker("删除状态", selection: $deleteStatusFilter) {
                    Text("全部").tag("ALL")
                    Text("无").tag("NONE")
                    Text("待审核").tag("WAITING")
                    Text("已通过").tag("APPROVED")
                    Text("已拒绝").tag("REJECTED")
                }
                Picker("记录状态", selection: $recordStateFilter) {
                    Text("全部历史").tag("ALL")
                    Text("正常记录").tag("ACTIVE")
                    Text("已删除记录").tag("DELETED")
                }
                Button {
                    Task { await load(resetPage: true) }
                } label: {
                    Label("刷新记录", systemImage: "arrow.clockwise")
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
            AdminAiGenerationStateSection(title: "生成记录", stateTitle: "正在加载 AI 生成记录", systemImage: "sparkles.rectangle.stack", isLoading: true)
        case .failed(let message):
            AdminAiGenerationStateSection(title: "生成记录", stateTitle: "AI 生成记录加载失败", message: message, systemImage: "sparkles.rectangle.stack")
        case .loaded(let result):
            if result.list.isEmpty {
                AdminAiGenerationStateSection(title: "生成记录", stateTitle: "暂无 AI 生成记录", message: "当前筛选条件下没有记录。", systemImage: "sparkles.rectangle.stack")
            } else {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "共 \(result.total) 条", subtitle: "AI 生成记录")
                        ForEach(Array(result.list.enumerated()), id: \.element.id) { index, job in
                            if index > 0 {
                                Divider()
                                    .overlay(SetuColor.separator)
                            }
                            AdminAiGenerationRow(job: job) {
                                Task { await unpublish(job) }
                            } onDelete: {
                                reasonDraft = AiGenerationReasonDraft(job: job, kind: .deleteGeneration)
                            } onLocalDelete: {
                                reasonDraft = AiGenerationReasonDraft(job: job, kind: .deleteLocalImage)
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

    private func pagerSection(_ result: PageResult<AiGenerationJob>) -> some View {
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
            .font(SetuTypography.body)
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
            state = .loaded(try await environment.aiGenerationClient.adminGenerations(
                jobId: Int(jobIdText.trimmingCharacters(in: .whitespacesAndNewlines)),
                userId: Int(userIdText.trimmingCharacters(in: .whitespacesAndNewlines)),
                status: statusFilter,
                reviewStatus: reviewStatusFilter,
                deleteStatus: deleteStatusFilter,
                recordState: recordStateFilter,
                page: page,
                pageSize: pageSize
            ))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func unpublish(_ job: AiGenerationJob) async {
        isSubmitting = true
        message = nil
        do {
            let result = try await environment.aiGenerationClient.unpublishAdminGeneration(id: job.id)
            message = "已下架 AI 生成 #\(result.id)"
            await load(resetPage: false)
        } catch {
            message = error.localizedDescription
        }
        isSubmitting = false
    }

    private func submitReasonAction(_ draft: AiGenerationReasonDraft, reason: String) async {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        isSubmitting = true
        message = nil
        do {
            switch draft.kind {
            case .deleteGeneration:
                let result = try await environment.aiGenerationClient.deleteAdminGeneration(
                    id: draft.job.id,
                    reason: trimmed.isEmpty ? nil : trimmed
                )
                message = "已删除 AI 生成 #\(result.id)"
            case .deleteLocalImage:
                let result = try await environment.aiGenerationClient.deleteAdminLocalImage(
                    id: draft.job.id,
                    reason: trimmed.isEmpty ? nil : trimmed
                )
                message = "本机图片删除指令已排队 #\(result.id)"
            }
            reasonDraft = nil
            await load(resetPage: false)
        } catch {
            message = error.localizedDescription
        }
        isSubmitting = false
    }
}

private struct AdminAiGenerationRow: View {
    let job: AiGenerationJob
    let onUnpublish: () -> Void
    let onDelete: () -> Void
    let onLocalDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.md) {
            HStack(alignment: .top, spacing: SetuSpacing.md) {
                AdminAiGenerationThumbnail(urlString: job.imageUrl, title: job.statusTitle)
                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                    Text("#\(job.id) · 用户 \(job.userId.map(String.init) ?? "-")")
                        .font(SetuTypography.headline)
                        .foregroundStyle(SetuColor.textPrimary)
                    Text(job.promptCn)
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                        .lineLimit(3)
                    badgeWrap
                    Text(metaLine)
                        .font(.caption)
                        .foregroundStyle(SetuColor.textTertiary)
                        .lineLimit(2)
                    if let createdAt = job.createdAt {
                        Label(createdAt, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(SetuColor.textTertiary)
                    }
                }
            }

            DisclosureGroup("完整提示词") {
                VStack(alignment: .leading, spacing: 8) {
                    promptBlock(title: "正向", value: job.promptPositive)
                    promptBlock(title: "反向", value: job.promptNegative)
                }
                .padding(.top, 6)
            }

            DisclosureGroup("存储位置") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("私有 OSS", value: job.privateOssStatus ?? "NONE")
                    LabeledContent("OSS 到期", value: job.privateOssExpiresAt ?? "-")
                    LabeledContent("本机状态", value: job.localStorageStatus ?? "NONE")
                    if let localRelativePath = job.localRelativePath, !localRelativePath.isEmpty {
                        Text("相对路径：\(localRelativePath)")
                            .font(.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                    }
                    if let localAbsolutePath = job.localAbsolutePath, !localAbsolutePath.isEmpty {
                        Text("绝对路径：\(localAbsolutePath)")
                            .font(.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                    }
                    if let error = job.privateOssDeleteError, !error.isEmpty {
                        Text("OSS 清理错误：\(error)")
                            .font(.caption)
                            .foregroundStyle(SetuColor.danger)
                    }
                }
                .padding(.top, 6)
            }

            DisclosureGroup("排错链路") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Worker", value: traceValue(job.workerId))
                    LabeledContent("本机任务 UUID", value: traceValue(job.localJobId))
                    LabeledContent("ComfyUI Prompt", value: traceValue(job.comfyPromptId))
                    LabeledContent("Worker 阶段", value: workerStageTitle(job.workerStage))
                    LabeledContent("更新时间", value: job.updatedAt ?? "-")
                    if let workerDetail = job.workerDetail, !workerDetail.isEmpty {
                        Text(workerDetail)
                            .font(.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                    }
                    if let error = job.errorMessage, !error.isEmpty {
                        Text(job.userErrorMessage ?? error)
                            .font(.caption)
                            .foregroundStyle(SetuColor.danger)
                    }
                }
                .padding(.top, 6)
            }

            actionRow
        }
        .padding(.vertical, SetuSpacing.xs)
    }

    private var badgeWrap: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                RequestStatusBadge(title: job.statusTitle, status: generationStatusCode)
                if job.status == "COMPLETED" {
                    RequestStatusBadge(title: "广场：\(reviewStatusTitle)", status: reviewStatusCode)
                }
                if let publicCategory = job.publicCategory {
                    SetuPill(
                        text: publicCategory == "R18" ? "R18" : "全年龄",
                        systemImage: publicCategory == "R18" ? "exclamationmark.triangle" : "checkmark.seal",
                        tone: publicCategory == "R18" ? .danger : .success
                    )
                }
                if let deleteStatus = job.deleteStatus, deleteStatus != "NONE" {
                    RequestStatusBadge(title: deleteStatusTitle(deleteStatus), status: deleteStatusCode(deleteStatus))
                }
                if job.deleted == true {
                    RequestStatusBadge(title: "历史已删除", status: 2)
                }
                SetuPill(text: "OSS：\(job.privateOssStatus ?? "NONE")", systemImage: "icloud", tone: .muted)
                SetuPill(text: "本机：\(job.localStorageStatus ?? "NONE")", systemImage: "externaldrive", tone: .muted)
            }
        }
    }

    private var actionRow: some View {
        HStack {
            if let imageUrl = job.imageUrl, let url = URL(string: imageUrl) {
                Link(destination: url) {
                    Label("查看", systemImage: "eye")
                }
            }
            Spacer()
            if job.publicVisible == true {
                Button(role: .destructive) {
                    onUnpublish()
                } label: {
                    Label("下架", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            if job.deleted != true {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
            if canDeleteLocalImage {
                Button(role: .destructive) {
                    onLocalDelete()
                } label: {
                    Label("本机图片", systemImage: "externaldrive.badge.xmark")
                }
            }
        }
        .buttonStyle(.borderless)
        .font(SetuTypography.caption)
    }

    private var canDeleteLocalImage: Bool {
        guard let path = job.localRelativePath, !path.isEmpty else { return false }
        return job.localStorageStatus != "DELETED"
    }

    private var metaLine: String {
        let seed = job.seed.map(String.init) ?? "随机"
        let mode = job.generationMode == "DUAL" ? "双角色" : "单角色"
        let points = job.adminFree == true ? "管理员免费" : "\(job.pointsCost ?? 0) 积分"
        return "\(job.width)x\(job.height) · steps \(job.steps) · CFG \(job.cfg) · seed \(seed) · \(job.checkpoint ?? "默认模型") · \(mode) · \(points)"
    }

    private var generationStatusCode: Int {
        switch job.status {
        case "COMPLETED": 1
        case "FAILED": 2
        default: 0
        }
    }

    private var reviewStatusTitle: String {
        switch job.reviewStatus {
        case "NOT_SUBMITTED": "未提交"
        case "WAITING": "待审核"
        case "APPROVED": "已通过"
        case "REJECTED": "已拒绝"
        case "UNPUBLISHED": "已下架"
        default: job.reviewStatus
        }
    }

    private var reviewStatusCode: Int {
        switch job.reviewStatus {
        case "APPROVED": 1
        case "REJECTED", "UNPUBLISHED": 2
        default: 0
        }
    }

    private func deleteStatusTitle(_ status: String) -> String {
        switch status {
        case "WAITING": "删除待审核"
        case "APPROVED": "删除已通过"
        case "REJECTED": "删除已拒绝"
        default: status
        }
    }

    private func deleteStatusCode(_ status: String) -> Int {
        switch status {
        case "APPROVED": 1
        case "REJECTED": 2
        default: 0
        }
    }

    private func promptBlock(title: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SetuColor.textPrimary)
            Text(value?.isEmpty == false ? value! : "-")
                .font(.caption)
                .foregroundStyle(SetuColor.textSecondary)
        }
    }

    private func traceValue(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "暂无" }
        return value
    }

    private func workerStageTitle(_ stage: String?) -> String {
        switch stage {
        case "CLAIMED": "已领取"
        case "STARTING_LOCAL_GENERATION": "提交本机生成"
        case "LOCAL_GENERATION_RUNNING": "本机生成中"
        case "LOCAL_GENERATION_FAILED": "本机生成失败"
        case "UPLOADING_TO_CLOUD": "准备上传云端"
        case "DOWNLOADING_LOCAL_IMAGE": "读取本机图片"
        case "COMPLETING_CLOUD_JOB": "云端写入 OSS"
        case "COMPLETED": "云端完成"
        case "REQUEUED": "已退回队列"
        case "FAILED": "失败"
        default: stage ?? "暂无"
        }
    }
}

private struct AdminAiGenerationThumbnail: View {
    let urlString: String?
    let title: String

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
        .frame(width: 92, height: 112)
        .background(SetuColor.brandSoft.opacity(0.12), in: RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SetuRadius.sm, style: .continuous)
                .stroke(SetuColor.separator, lineWidth: 1)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles.rectangle.stack")
            Text(title)
                .font(.caption2)
        }
        .foregroundStyle(SetuColor.brandPink)
    }
}

private struct AiGenerationReasonSheet: View {
    @Environment(\.dismiss) private var dismiss
    let draft: AiGenerationReasonDraft
    let isSubmitting: Bool
    let onSubmit: (String) -> Void
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            List {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: draft.kind.reasonTitle, subtitle: draft.kind.title)
                    TextField(draft.kind.reasonPlaceholder, text: $reason, axis: .vertical)
                        .lineLimit(4...7)
                            .textFieldStyle(.roundedBorder)
                }
                }
                .setuListRow()
                if draft.kind == .deleteLocalImage, let path = draft.job.localAbsolutePath {
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                            SetuSectionHeader(title: "本机路径")
                        Text(path)
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                    .setuListRow()
                }
            }
            .listStyle(.plain)
            .setuBackground()
            .navigationTitle(draft.kind.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .destructive) {
                        onSubmit(reason)
                    } label: {
                        Text(isSubmitting ? "提交中" : draft.kind.confirmTitle)
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }
}

private struct AdminAiGenerationStateSection: View {
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

private struct AiGenerationReasonDraft: Identifiable {
    let job: AiGenerationJob
    let kind: AiGenerationReasonKind

    var id: String { "\(kind.rawValue)-\(job.id)" }
}

private enum AiGenerationReasonKind: String {
    case deleteGeneration
    case deleteLocalImage

    var title: String {
        switch self {
        case .deleteGeneration: "删除 AI 生图"
        case .deleteLocalImage: "删除本机归档图片"
        }
    }

    var reasonTitle: String {
        switch self {
        case .deleteGeneration: "删除原因"
        case .deleteLocalImage: "指令原因"
        }
    }

    var reasonPlaceholder: String {
        switch self {
        case .deleteGeneration: "可选：记录删除原因"
        case .deleteLocalImage: "可选：记录下发原因"
        }
    }

    var confirmTitle: String {
        switch self {
        case .deleteGeneration: "确认删除"
        case .deleteLocalImage: "确认下发"
        }
    }
}
