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
        SetuBoard {
            if environment.authSession.currentUser?.role != .admin {
                AdminGallerySubmissionStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后审核投稿。", systemImage: "shield.slash")
            } else {
                filterSection
                content
            }
        }
        .setuBackground()
        .navigationTitle("投稿审核")
        .task { await load(resetPage: true) }
        .refreshable { await load(resetPage: false) }
    }

    private var filterSection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "筛选")
                SetuFilterBar(options: [
                    .init(value: "WAITING_MANUAL_REVIEW", title: "待审核"),
                    .init(value: "ALL", title: "全部"),
                    .init(value: "APPROVED", title: "已通过"),
                    .init(value: "PUBLISHED", title: "已发布"),
                    .init(value: "REJECTED", title: "已拒绝"),
                    .init(value: "PUBLISH_FAILED", title: "发布失败")
                ], selection: $statusFilter, accessibilityTitle: "状态")

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
                Group {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "共 \(result.total) 个批次", subtitle: "投稿审核")
                    SetuRecordBoard(items: result.list) { batch in
                        Button {
                            router.navigate(to: .adminGallerySubmissionDetail(batch.batchId))
                        } label: {
                            SetuRecordCard(headline: batch.title?.isEmpty == false ? batch.title! : "未命名投稿",
                                status: .init(batch.statusTitle, tone: batch.status == "REJECTED" ? .danger : .brand),
                                fields: [.init("作者", batch.author ?? "未知作者"), .init("图片", "\(batch.itemCount)"),
                                         .init("已上传", "\(batch.uploadedCount)"), .init("已发布", "\(batch.publishedCount)"),
                                         .init("创建时间", SetuDateFormatter.string(from: batch.createdAt))], density: .compact)
                        }
                        .buttonStyle(.plain)
                    }
                }
                }

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

    @State private var pendingAction: (() -> Void)?
    @State private var pendingActionTitle = ""

    var body: some View {
        SetuBoard {
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

                }
                content
            }
        }
        .setuBackground()
        .navigationTitle("投稿 #\(batchID)")
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
            Group {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: "图片 \(batch.items.count)", subtitle: "投稿明细")
                SetuRecordBoard(items: batch.items) { item in
                    SetuRecordCard(headline: item.title?.isEmpty == false ? item.title! : "投稿图片",
                        status: .init(item.statusTitle, tone: item.rejectReason == nil ? .brand : .danger),
                        thumbnailURLString: item.previewUrl,
                        fields: [.init("作者", item.author ?? "未知作者"), .init("拒绝原因", item.rejectReason ?? "-")], density: .compact)
                }
            }
            }

        }
    }

    private func batchSection(_ batch: GalleryUploadBatchDetail) -> some View {
        SetuRecordCard(headline: "批次 #\(batch.batchId)", status: .init(batch.statusTitle, tone: batch.status == "REJECTED" ? .danger : .brand), fields: {
                    var fields: [SetuRecordField] = []
                fields.append(.init("状态", batch.statusTitle))
                fields.append(.init("PID 模式", batch.pidMode))
                if let title = batch.title, !title.isEmpty {
                    fields.append(.init("标题", title))
                }
                if let author = batch.author, !author.isEmpty {
                    fields.append(.init("作者", author))
                }
                if let r18 = batch.r18 {
                    fields.append(.init("R18", r18 ? "是" : "否"))
                }
                if let aiType = batch.aiType {
                    fields.append(.init("AI 类型", "\(aiType)"))
                }
                if let tags = batch.tags, !tags.isEmpty {
                    fields.append(.init("标签", tags.joined(separator: " / ")))
                }
                fields.append(.init("创建时间", batch.createdAt))
                if let reviewedAt = batch.reviewedAt {
                    fields.append(.init("审核时间", reviewedAt))
                }
                if let publishedAt = batch.publishedAt {
                    fields.append(.init("发布时间", publishedAt))
                }
                    return fields
                }(), density: .compact)

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

    }

    private var rejectSection: some View {
        SetuRecordCard(headline: "拒绝", status: .init("请核对后操作", tone: .danger), density: .compact) {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "拒绝")
            TextField("拒绝原因", text: $rejectReason)
                    .textFieldStyle(.roundedBorder)
            SetuFilterBar(options: [
                    .init(value: "LOW", title: "低"),
                    .init(value: "MEDIUM", title: "中"),
                    .init(value: "HIGH", title: "高")
                ], selection: $rejectSeverity, accessibilityTitle: "严重程度")

            Button(role: .destructive) {
                pendingActionTitle = "确认拒绝此投稿？"; pendingAction = { Task { await reject() } }
            } label: {
                Label("拒绝投稿", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(isSubmitting || rejectReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
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

private typealias AdminGallerySubmissionStateSection = AdminRecordStateSection
