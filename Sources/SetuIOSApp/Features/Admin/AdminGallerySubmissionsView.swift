import SetuIOSCore
import SwiftUI

struct AdminGallerySubmissionsView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<PageResult<GalleryUploadBatchSummary>> = .idle
    @State private var statusFilter = "WAITING_MANUAL_REVIEW"
    @State private var page = 1
    private let pageSize = 20

    var body: some View {
        List {
            if environment.authSession.currentUser?.role != .admin {
                ContentUnavailableView("需要管理员权限", systemImage: "shield.slash", description: Text("请使用管理员账号登录后审核投稿。"))
            } else {
                filterSection
                content
            }
        }
        .navigationTitle("投稿审核")
        .task { await load(resetPage: true) }
        .refreshable { await load(resetPage: false) }
    }

    private var filterSection: some View {
        Section("筛选") {
            Picker("状态", selection: $statusFilter) {
                Text("待审核").tag("WAITING_MANUAL_REVIEW")
                Text("全部").tag("ALL")
                Text("已通过").tag("APPROVED")
                Text("已发布").tag("PUBLISHED")
                Text("已拒绝").tag("REJECTED")
                Text("发布失败").tag("PUBLISH_FAILED")
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
            ProgressView("正在加载投稿批次")
        case .failed(let message):
            ContentUnavailableView("投稿审核加载失败", systemImage: "tray.full", description: Text(message))
        case .loaded(let result):
            if result.list.isEmpty {
                ContentUnavailableView("暂无投稿批次", systemImage: "tray", description: Text("当前筛选条件下没有需要展示的投稿批次。"))
            } else {
                Section("共 \(result.total) 个批次") {
                    ForEach(result.list) { batch in
                        Button {
                            router.navigate(to: .adminGallerySubmissionDetail(batch.batchId))
                        } label: {
                            GalleryUploadBatchRow(batch: batch)
                        }
                        .buttonStyle(.plain)
                    }
                }
                pagerSection(result)
            }
        }
    }

    private func pagerSection(_ result: PageResult<GalleryUploadBatchSummary>) -> some View {
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
            state = .loaded(try await environment.galleryUploadClient.adminList(
                status: statusFilter,
                page: page,
                pageSize: pageSize
            ))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct AdminGallerySubmissionDetailView: View {
    @Bindable var environment: AppEnvironment
    let batchID: Int
    @State private var state: LoadState<GalleryUploadBatchDetail> = .idle
    @State private var message: String?
    @State private var isSubmitting = false
    @State private var approveRemark = ""
    @State private var publishNow = true
    @State private var overrideR18 = false
    @State private var aiTypeText = ""
    @State private var normalizedTagsText = ""
    @State private var rejectReason = ""
    @State private var rejectSeverity = "MEDIUM"

    var body: some View {
        List {
            if environment.authSession.currentUser?.role != .admin {
                ContentUnavailableView("需要管理员权限", systemImage: "shield.slash", description: Text("请使用管理员账号登录后审核投稿。"))
            } else {
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
        .navigationTitle("投稿 #\(batchID)")
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ProgressView("正在加载投稿详情")
        case .failed(let message):
            ContentUnavailableView("投稿详情加载失败", systemImage: "tray.full", description: Text(message))
        case .loaded(let batch):
            batchSection(batch)
            if batch.status == "WAITING_MANUAL_REVIEW" {
                approveSection(batch)
                rejectSection
            }
            Section("图片 \(batch.items.count)") {
                ForEach(batch.items) { item in
                    GalleryUploadItemRow(item: item)
                }
            }
        }
    }

    private func batchSection(_ batch: GalleryUploadBatchDetail) -> some View {
        Section("批次") {
            LabeledContent("状态", value: batch.statusTitle)
            LabeledContent("PID 模式", value: batch.pidMode)
            if let title = batch.title, !title.isEmpty {
                LabeledContent("标题", value: title)
            }
            if let author = batch.author, !author.isEmpty {
                LabeledContent("作者", value: author)
            }
            if let r18 = batch.r18 {
                LabeledContent("R18", value: r18 ? "是" : "否")
            }
            if let aiType = batch.aiType {
                LabeledContent("AI 类型", value: "\(aiType)")
            }
            if let tags = batch.tags, !tags.isEmpty {
                Text(tags.joined(separator: " / "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("创建时间", value: batch.createdAt)
            if let reviewedAt = batch.reviewedAt {
                LabeledContent("审核时间", value: reviewedAt)
            }
            if let publishedAt = batch.publishedAt {
                LabeledContent("发布时间", value: publishedAt)
            }
        }
    }

    private func approveSection(_ batch: GalleryUploadBatchDetail) -> some View {
        Section("批准") {
            TextField("审核备注，可选", text: $approveRemark)
            Toggle("立即发布", isOn: $publishNow)
            Toggle("标记 R18", isOn: $overrideR18)
            TextField("AI 类型，可选", text: $aiTypeText)
            TextField("归一化标签，逗号或换行分隔", text: $normalizedTagsText)
            Button {
                Task { await approve(batch) }
            } label: {
                if isSubmitting {
                    ProgressView()
                } else {
                    Label("批准投稿", systemImage: "checkmark.circle")
                }
            }
            .disabled(isSubmitting)
        }
    }

    private var rejectSection: some View {
        Section("拒绝") {
            TextField("拒绝原因", text: $rejectReason)
            Picker("严重程度", selection: $rejectSeverity) {
                Text("低").tag("LOW")
                Text("中").tag("MEDIUM")
                Text("高").tag("HIGH")
            }
            Button(role: .destructive) {
                Task { await reject() }
            } label: {
                Label("拒绝投稿", systemImage: "xmark.circle")
            }
            .disabled(isSubmitting || rejectReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func load() async {
        guard environment.authSession.currentUser?.role == .admin else { return }
        state = .loading
        do {
            state = .loaded(try await environment.galleryUploadClient.adminDetail(batchID: batchID))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func approve(_ batch: GalleryUploadBatchDetail) async {
        isSubmitting = true
        message = nil
        do {
            let tags = parsedTags
            let response = try await environment.galleryUploadClient.approve(
                batchID: batch.batchId,
                request: GalleryAdminApproveRequest(
                    remark: clean(approveRemark),
                    publishNow: publishNow,
                    r18: overrideR18,
                    aiType: Int(aiTypeText.trimmingCharacters(in: .whitespacesAndNewlines)),
                    normalizedTags: tags.isEmpty ? nil : tags
                )
            )
            message = "已批准投稿，当前状态：\(GalleryUploadStatus.title(for: response.status))"
            await load()
        } catch {
            message = error.localizedDescription
        }
        isSubmitting = false
    }

    private func reject() async {
        isSubmitting = true
        message = nil
        do {
            let response = try await environment.galleryUploadClient.reject(
                batchID: batchID,
                request: GalleryAdminRejectRequest(reason: rejectReason, severity: rejectSeverity)
            )
            message = "已拒绝投稿，当前状态：\(GalleryUploadStatus.title(for: response.status))"
            await load()
        } catch {
            message = error.localizedDescription
        }
        isSubmitting = false
    }

    private var parsedTags: [String] {
        normalizedTagsText
            .split { character in
                character == "," || character == "\n" || character == " "
            }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
