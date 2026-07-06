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
                ContentUnavailableView("需要管理员权限", systemImage: "shield.slash", description: Text("请使用管理员账号登录后管理 AI 生成记录。"))
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
        Section("筛选") {
            TextField("任务 ID", text: $jobIdText)
            TextField("用户 ID", text: $userIdText)
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
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ProgressView("正在加载 AI 生成记录")
        case .failed(let message):
            ContentUnavailableView("AI 生成记录加载失败", systemImage: "sparkles.rectangle.stack", description: Text(message))
        case .loaded(let result):
            if result.list.isEmpty {
                ContentUnavailableView("暂无 AI 生成记录", systemImage: "sparkles.rectangle.stack")
            } else {
                Section("共 \(result.total) 条") {
                    ForEach(result.list) { job in
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
                pagerSection(result)
            }
        }
    }

    private func pagerSection(_ result: PageResult<AiGenerationJob>) -> some View {
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AdminAiGenerationThumbnail(urlString: job.imageUrl, title: job.statusTitle)
                VStack(alignment: .leading, spacing: 6) {
                    Text("#\(job.id) · 用户 \(job.userId.map(String.init) ?? "-")")
                        .font(.headline)
                    Text(job.promptCn)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    badgeWrap
                    Text(metaLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let createdAt = job.createdAt {
                        Label(createdAt, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                    }
                    if let localAbsolutePath = job.localAbsolutePath, !localAbsolutePath.isEmpty {
                        Text("绝对路径：\(localAbsolutePath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let error = job.privateOssDeleteError, !error.isEmpty {
                        Text("OSS 清理错误：\(error)")
                            .font(.caption)
                            .foregroundStyle(.red)
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
                            .foregroundStyle(.secondary)
                    }
                    if let error = job.errorMessage, !error.isEmpty {
                        Text(job.userErrorMessage ?? error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.top, 6)
            }

            actionRow
        }
        .padding(.vertical, 4)
    }

    private var badgeWrap: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                RequestStatusBadge(title: job.statusTitle, status: generationStatusCode)
                if job.status == "COMPLETED" {
                    RequestStatusBadge(title: "广场：\(reviewStatusTitle)", status: reviewStatusCode)
                }
                if let publicCategory = job.publicCategory {
                    Text(publicCategory == "R18" ? "R18" : "全年龄")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((publicCategory == "R18" ? Color.red : Color.green).opacity(0.14), in: Capsule())
                        .foregroundStyle(publicCategory == "R18" ? .red : .green)
                }
                if let deleteStatus = job.deleteStatus, deleteStatus != "NONE" {
                    RequestStatusBadge(title: deleteStatusTitle(deleteStatus), status: deleteStatusCode(deleteStatus))
                }
                if job.deleted == true {
                    RequestStatusBadge(title: "历史已删除", status: 2)
                }
                Text("OSS：\(job.privateOssStatus ?? "NONE")")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                    .foregroundStyle(.secondary)
                Text("本机：\(job.localStorageStatus ?? "NONE")")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                    .foregroundStyle(.secondary)
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
        .font(.footnote)
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
            Text(value?.isEmpty == false ? value! : "-")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        .background(.pink.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles.rectangle.stack")
            Text(title)
                .font(.caption2)
        }
        .foregroundStyle(.pink)
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
            Form {
                Section(draft.kind.reasonTitle) {
                    TextField(draft.kind.reasonPlaceholder, text: $reason, axis: .vertical)
                        .lineLimit(4...7)
                }
                if draft.kind == .deleteLocalImage, let path = draft.job.localAbsolutePath {
                    Section("本机路径") {
                        Text(path)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(draft.kind.title)
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
                            Text(draft.kind.confirmTitle)
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
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
