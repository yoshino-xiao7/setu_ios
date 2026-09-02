import SetuIOSCore
import SwiftUI

struct AdminImageDeleteRequestsView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<PageResult<ImageDeleteRequestItem>> = .idle
    @State private var statusFilter: DeleteRequestStatusFilter = .pending
    @State private var page = 1
    @State private var selectedRequestIDs: Set<Int> = []
    @State private var actionMessage: String?
    @State private var isBulkReviewing = false
    private let pageSize = 20

    var body: some View {
        List {
            if environment.authSession.currentUser?.role != .admin {
                AdminImageDeleteStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后审核图片删除申请。", systemImage: "shield.slash")
            } else {
                if let actionMessage {
                    SetuCard {
                        Label(actionMessage, systemImage: "checkmark.circle")
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .setuListRow()
                }
                filterSection
                content
            }
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("删除申请审核")
        .task { await load(resetPage: true) }
        .refreshable { await load(resetPage: false) }
    }

    private var filterSection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "筛选")
                Picker("状态", selection: $statusFilter) {
                    ForEach(DeleteRequestStatusFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
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
            AdminImageDeleteStateSection(title: "删除申请", stateTitle: "正在加载删除申请", systemImage: "trash.slash", isLoading: true)
        case .failed(let message):
            AdminImageDeleteStateSection(title: "删除申请", stateTitle: "删除申请加载失败", message: message, systemImage: "trash.slash")
        case .loaded(let result):
            if result.list.isEmpty {
                AdminImageDeleteStateSection(title: "删除申请", stateTitle: "暂无申请", message: "当前筛选条件下没有图片删除申请。", systemImage: "tray")
            } else {
                let pendingItems = result.list.filter { $0.status == 0 }
                if !pendingItems.isEmpty {
                    bulkReviewSection(pendingItems)
                }
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "共 \(result.total) 条", subtitle: "图片删除申请")
                    ForEach(Array(result.list.enumerated()), id: \.element.id) { index, request in
                            if index > 0 {
                                Divider()
                                    .overlay(SetuColor.separator)
                            }
                        HStack(spacing: SetuSpacing.md) {
                            if request.status == 0 {
                                Button {
                                    toggleSelection(request.id)
                                } label: {
                                    Image(systemName: selectedRequestIDs.contains(request.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedRequestIDs.contains(request.id) ? SetuColor.success : SetuColor.textTertiary)
                                            .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.borderless)
                                .disabled(isBulkReviewing)
                            }

                            Button {
                                router.navigate(to: .adminImageDeleteRequestDetail(request.id))
                            } label: {
                                ImageDeleteRequestRow(request: request)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                }
                .setuListRow()
                pagerSection(result)
            }
        }
    }

    private func bulkReviewSection(_ pendingItems: [ImageDeleteRequestItem]) -> some View {
        let pendingIDs = Set(pendingItems.map(\.id))
        let selectedCount = selectedRequestIDs.intersection(pendingIDs).count
        let allSelected = selectedCount == pendingItems.count

        return SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "批量审核")
                HStack {
                Button(allSelected ? "取消全选当前页" : "选择当前页待审核") {
                    if allSelected {
                        selectedRequestIDs.subtract(pendingIDs)
                    } else {
                        selectedRequestIDs.formUnion(pendingIDs)
                    }
                }
                .disabled(isBulkReviewing)

                Spacer()

                Text("已选 \(selectedCount) / \(pendingItems.count)")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
            }

            HStack {
                Button("清空选择") {
                    selectedRequestIDs.removeAll()
                }
                .disabled(isBulkReviewing || selectedRequestIDs.isEmpty)

                Spacer()

                Button(role: .destructive) {
                    Task { await batchReview(approve: false) }
                } label: {
                    Label("批量拒绝", systemImage: "xmark.circle")
                }
                .disabled(isBulkReviewing || selectedCount == 0)

                Button {
                    Task { await batchReview(approve: true) }
                } label: {
                        Label(isBulkReviewing ? "处理中" : "批量同意", systemImage: isBulkReviewing ? "hourglass" : "checkmark.circle")
                            .frame(minHeight: 44)
                }
                .disabled(isBulkReviewing || selectedCount == 0)
            }
        }
        }
        .setuListRow()
    }

    private func pagerSection(_ result: PageResult<ImageDeleteRequestItem>) -> some View {
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
            selectedRequestIDs.removeAll()
        }
        state = .loading
        do {
            let result: PageResult<ImageDeleteRequestItem>
            if statusFilter == .pendingOnly {
                result = try await environment.imageDeleteRequestClient.adminPending(page: page, pageSize: pageSize)
            } else {
                result = try await environment.imageDeleteRequestClient.adminList(
                    status: statusFilter.queryValue,
                    page: page,
                    pageSize: pageSize
                )
            }
            selectedRequestIDs.formIntersection(Set(result.list.filter { $0.status == 0 }.map(\.id)))
            state = .loaded(result)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func toggleSelection(_ id: Int) {
        if selectedRequestIDs.contains(id) {
            selectedRequestIDs.remove(id)
        } else {
            selectedRequestIDs.insert(id)
        }
    }

    private func batchReview(approve: Bool) async {
        let requestIDs = Array(currentPendingIDs().intersection(selectedRequestIDs)).sorted()
        guard !requestIDs.isEmpty else { return }
        isBulkReviewing = true
        actionMessage = nil
        do {
            let response = try await environment.imageDeleteRequestClient.batchReview(
                requestIDs: requestIDs,
                approve: approve,
                remark: approve ? "iOS 批量同意" : "iOS 批量拒绝"
            )
            selectedRequestIDs.removeAll()
            actionMessage = "批量审核完成：成功 \(response.successCount)，失败 \(response.failureCount)"
            await load(resetPage: false)
        } catch {
            actionMessage = error.localizedDescription
        }
        isBulkReviewing = false
    }

    private func currentPendingIDs() -> Set<Int> {
        guard case .loaded(let result) = state else { return [] }
        return Set(result.list.filter { $0.status == 0 }.map(\.id))
    }
}

struct AdminImageDeleteRequestDetailView: View {
    @Bindable var environment: AppEnvironment
    let requestID: Int
    @State private var state: LoadState<ImageDeleteRequestDetail> = .idle
    @State private var remark = ""
    @State private var message: String?
    @State private var isSubmitting = false

    var body: some View {
        List {
            if environment.authSession.currentUser?.role != .admin {
                AdminImageDeleteStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后审核图片删除申请。", systemImage: "shield.slash")
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
        .navigationTitle("审核详情")
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            AdminImageDeleteStateSection(title: "审核详情", stateTitle: "正在加载申请详情", systemImage: "trash.slash", isLoading: true)
        case .failed(let message):
            AdminImageDeleteStateSection(title: "审核详情", stateTitle: "申请详情加载失败", message: message, systemImage: "trash.slash")
        case .loaded(let detail):
            statusSection(detail)
            imageSection(detail)
            reasonSection(detail)
            if detail.status == 0 {
                reviewActionSection
            } else {
                reviewInfoSection(detail)
            }
        }
    }

    private func statusSection(_ detail: ImageDeleteRequestDetail) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "申请状态")
                HStack {
                RequestStatusBadge(title: detail.statusTitle, status: detail.status)
                Spacer()
                Text(detail.createdAt)
                    .font(.caption)
                        .foregroundStyle(SetuColor.textTertiary)
            }
                AdminImageDeleteMetadataRow(title: "申请 ID", value: "\(detail.id)")
                AdminImageDeleteMetadataRow(title: "申请人", value: detail.userNickname.isEmpty ? detail.userEmail : detail.userNickname)
                AdminImageDeleteMetadataRow(title: "用户 ID", value: "\(detail.userId)")
            }
        }
        .setuListRow()
    }

    private func imageSection(_ detail: ImageDeleteRequestDetail) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "图片信息")
            DetailImagePreview(urlString: detail.urlOriginal)
                AdminImageDeleteMetadataRow(title: "PID", value: "\(detail.pid)_p\(detail.p)")
            if let title = detail.title, !title.isEmpty {
                    AdminImageDeleteMetadataRow(title: "标题", value: title)
            }
            if let author = detail.author, !author.isEmpty {
                    AdminImageDeleteMetadataRow(title: "作者", value: author)
            }
            if let uid = detail.uid {
                    AdminImageDeleteMetadataRow(title: "作者 UID", value: "\(uid)")
            }
            if let width = detail.width, let height = detail.height {
                    AdminImageDeleteMetadataRow(title: "尺寸", value: "\(width) x \(height)")
            }
            if let ext = detail.ext, !ext.isEmpty {
                    AdminImageDeleteMetadataRow(title: "格式", value: ext)
            }
            if let r18 = detail.r18 {
                    AdminImageDeleteMetadataRow(title: "R18", value: r18 == 1 ? "是" : "否")
            }
            if let tags = detail.tags, !tags.isEmpty {
                TagFlow(tags: tags)
            }
        }
        }
        .setuListRow()
    }

    private func reasonSection(_ detail: ImageDeleteRequestDetail) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "申请原因")
            Text(detail.reason.isEmpty ? "无" : detail.reason)
                    .font(SetuTypography.body)
                    .foregroundStyle(detail.reason.isEmpty ? SetuColor.textSecondary : SetuColor.textPrimary)
            }
        }
        .setuListRow()
    }

    private var reviewActionSection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "审核")
            TextField("审核备注，可选", text: $remark)
                    .textFieldStyle(.roundedBorder)
            HStack {
                Button(role: .destructive) {
                    Task { await review(approve: false) }
                } label: {
                    Label("拒绝", systemImage: "xmark.circle")
                        .frame(minHeight: 44)
                }
                .disabled(isSubmitting)

                Spacer()

                Button {
                    Task { await review(approve: true) }
                } label: {
                        Label(isSubmitting ? "提交中" : "批准删除", systemImage: isSubmitting ? "hourglass" : "checkmark.circle")
                            .frame(minHeight: 44)
                }
                .disabled(isSubmitting)
            }
        }
        }
        .setuListRow()
    }

    private func reviewInfoSection(_ detail: ImageDeleteRequestDetail) -> some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "审核信息")
                AdminImageDeleteMetadataRow(title: "审核人", value: detail.adminEmail ?? "-")
                AdminImageDeleteMetadataRow(title: "审核时间", value: detail.reviewedAt ?? "-")
            if let adminRemark = detail.adminRemark, !adminRemark.isEmpty {
                    AdminImageDeleteMetadataRow(title: "备注", value: adminRemark)
                }
            }
        }
        .setuListRow()
    }

    private func load() async {
        guard environment.authSession.currentUser?.role == .admin else { return }
        state = .loading
        do {
            state = .loaded(try await environment.imageDeleteRequestClient.adminDetail(id: requestID))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func review(approve: Bool) async {
        isSubmitting = true
        message = nil
        do {
            let trimmedRemark = remark.trimmingCharacters(in: .whitespacesAndNewlines)
            try await environment.imageDeleteRequestClient.review(
                requestID: requestID,
                approve: approve,
                remark: trimmedRemark.isEmpty ? nil : trimmedRemark
            )
            message = approve ? "已批准删除申请" : "已拒绝删除申请"
            await load()
        } catch {
            message = error.localizedDescription
        }
        isSubmitting = false
    }
}

private enum DeleteRequestStatusFilter: String, CaseIterable, Identifiable {
    case pendingOnly
    case all
    case pending
    case approved
    case rejected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pendingOnly: "待审核队列"
        case .all: "全部"
        case .pending: "待审核"
        case .approved: "已批准"
        case .rejected: "已拒绝"
        }
    }

    var queryValue: Int? {
        switch self {
        case .pendingOnly, .all: nil
        case .pending: 0
        case .approved: 1
        case .rejected: 2
        }
    }
}

private typealias AdminImageDeleteStateSection = SetuStateSection

private struct AdminImageDeleteMetadataRow: View {
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
