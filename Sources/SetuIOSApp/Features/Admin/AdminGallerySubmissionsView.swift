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
                AdminGallerySubmissionStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后审核投稿。", systemImage: "shield.slash")
            } else {
                filterSection
                content
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("投稿审核")
        .task { await load(resetPage: true) }
        .refreshable { await load(resetPage: false) }
    }

    private var filterSection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "筛选")
                Picker("状态", selection: $statusFilter) {
                    Text("待审核").tag("WAITING_MANUAL_REVIEW")
                    Text("全部").tag("ALL")
                    Text("已通过").tag("APPROVED")
                    Text("已发布").tag("PUBLISHED")
                    Text("已拒绝").tag("REJECTED")
                    Text("发布失败").tag("PUBLISH_FAILED")
                }
                .pickerStyle(.segmented)
                Button {
                    Task { await load(resetPage: true) }
                } label: {
                    Label("刷新列表", systemImage: "arrow.clockwise")
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
            AdminGallerySubmissionStateSection(title: "投稿批次", stateTitle: "正在加载投稿批次", systemImage: "tray.full", isLoading: true)
        case .failed(let message):
            AdminGallerySubmissionStateSection(title: "投稿批次", stateTitle: "投稿审核加载失败", message: message, systemImage: "tray.full")
        case .loaded(let result):
            if result.list.isEmpty {
                AdminGallerySubmissionStateSection(title: "投稿批次", stateTitle: "暂无投稿批次", message: "当前筛选条件下没有需要展示的投稿批次。", systemImage: "tray")
            } else {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "共 \(result.total) 个批次", subtitle: "投稿审核")
                    ForEach(Array(result.list.enumerated()), id: \.element.id) { index, batch in
                            if index > 0 {
                                Divider()
                                    .overlay(SetuColor.separator)
                            }
                        Button {
                            router.navigate(to: .adminGallerySubmissionDetail(batch.batchId))
                        } label: {
                            GalleryUploadBatchRow(batch: batch)
                        }
                        .buttonStyle(.plain)
                    }
                }
                }
                .setuListRow()
                pagerSection(result)
            }
        }
    }

    private func pagerSection(_ result: PageResult<GalleryUploadBatchSummary>) -> some View {
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
                AdminGallerySubmissionStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后审核投稿。", systemImage: "shield.slash")
            } else {
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
        .navigationTitle("投稿 #\(batchID)")
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            AdminGallerySubmissionStateSection(title: "投稿详情", stateTitle: "正在加载投稿详情", systemImage: "tray.full", isLoading: true)
        case .failed(let message):
            AdminGallerySubmissionStateSection(title: "投稿详情", stateTitle: "投稿详情加载失败", message: message, systemImage: "tray.full")
        case .loaded(let batch):
            batchSection(batch)
            if batch.status == "WAITING_MANUAL_REVIEW" {
                approveSection(batch)
                rejectSection
            }
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "图片 \(batch.items.count)", subtitle: "投稿明细")
                ForEach(Array(batch.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider()
                                .overlay(SetuColor.separator)
                        }
                    GalleryUploadItemRow(item: item)
                }
            }
            }
            .setuListRow()
        }
    }

    private func batchSection(_ batch: GalleryUploadBatchDetail) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "批次", subtitle: "#\(batch.batchId)")
                AdminGalleryMetadataRow(title: "状态", value: batch.statusTitle)
                AdminGalleryMetadataRow(title: "PID 模式", value: batch.pidMode)
                if let title = batch.title, !title.isEmpty {
                    AdminGalleryMetadataRow(title: "标题", value: title)
                }
                if let author = batch.author, !author.isEmpty {
                    AdminGalleryMetadataRow(title: "作者", value: author)
                }
                if let r18 = batch.r18 {
                    AdminGalleryMetadataRow(title: "R18", value: r18 ? "是" : "否")
                }
                if let aiType = batch.aiType {
                    AdminGalleryMetadataRow(title: "AI 类型", value: "\(aiType)")
                }
                if let tags = batch.tags, !tags.isEmpty {
                    AdminGalleryMetadataRow(title: "标签", value: tags.joined(separator: " / "))
                }
                AdminGalleryMetadataRow(title: "创建时间", value: batch.createdAt)
                if let reviewedAt = batch.reviewedAt {
                    AdminGalleryMetadataRow(title: "审核时间", value: reviewedAt)
                }
                if let publishedAt = batch.publishedAt {
                    AdminGalleryMetadataRow(title: "发布时间", value: publishedAt)
                }
            }
        }
        .setuListRow()
    }

    private func approveSection(_ batch: GalleryUploadBatchDetail) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "批准")
            TextField("审核备注，可选", text: $approveRemark)
                    .textFieldStyle(.roundedBorder)
            Toggle("立即发布", isOn: $publishNow)
            Toggle("标记 R18", isOn: $overrideR18)
            TextField("AI 类型，可选", text: $aiTypeText)
                    .textFieldStyle(.roundedBorder)
            TextField("归一化标签，逗号或换行分隔", text: $normalizedTagsText)
                    .textFieldStyle(.roundedBorder)
            Button {
                Task { await approve(batch) }
            } label: {
                    Label(isSubmitting ? "提交中" : "批准投稿", systemImage: isSubmitting ? "hourglass" : "checkmark.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
            }
                .buttonStyle(.borderedProminent)
                .tint(SetuColor.brandPink)
            .disabled(isSubmitting)
        }
        }
        .setuListRow()
    }

    private var rejectSection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "拒绝")
            TextField("拒绝原因", text: $rejectReason)
                    .textFieldStyle(.roundedBorder)
            Picker("严重程度", selection: $rejectSeverity) {
                Text("低").tag("LOW")
                Text("中").tag("MEDIUM")
                Text("高").tag("HIGH")
            }
                .pickerStyle(.segmented)
            Button(role: .destructive) {
                Task { await reject() }
            } label: {
                Label("拒绝投稿", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(isSubmitting || rejectReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        }
        .setuListRow()
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

private struct AdminGallerySubmissionStateSection: View {
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

private struct AdminGalleryMetadataRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: SetuSpacing.md) {
            Text(title)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(SetuTypography.body)
                .foregroundStyle(SetuColor.textPrimary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
