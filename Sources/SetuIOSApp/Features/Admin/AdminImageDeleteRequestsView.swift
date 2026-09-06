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

    @State private var pendingAction: (() -> Void)?
    @State private var pendingActionTitle = ""

    var body: some View {
        SetuBoard {
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

                }
                filterSection
                content
            }
        }
        .setuBackground()
        .navigationTitle("删除申请审核")
        .setuActionDock {
            if environment.authSession.currentUser?.role == .admin, case .loaded(let result) = state {
                let pendingItems = result.list.filter { $0.status == 0 }
                if !pendingItems.isEmpty { bulkReviewSection(pendingItems) }
            }
        }
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
        .task { await load(resetPage: true) }
        .refreshable { await load(resetPage: false) }
    }

    private var filterSection: some View {
        SetuCard {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "筛选")
                SetuFilterBar(options: DeleteRequestStatusFilter.allCases.map { .init(value: $0, title: $0.title) }, selection: $statusFilter, accessibilityTitle: "状态")

                Button {
                    Task { await load(resetPage: true) }
                } label: {
                    Label("刷新列表", systemImage: "arrow.clockwise")
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
            AdminImageDeleteStateSection(title: "删除申请", stateTitle: "正在加载删除申请", systemImage: "trash.slash", isLoading: true)
        case .failed(let message):
            AdminImageDeleteStateSection(title: "删除申请", stateTitle: "删除申请加载失败", message: message, systemImage: "trash.slash")
        case .loaded(let result):
            if result.list.isEmpty {
                AdminImageDeleteStateSection(title: "删除申请", stateTitle: "暂无申请", message: "当前筛选条件下没有图片删除申请。", systemImage: "tray")
            } else {

                Group {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "共 \(result.total) 条", subtitle: "图片删除申请")
                    SetuRecordBoard(items: result.list) { request in
                        SetuRecordCard(headline: request.imageTitle ?? "未命名作品",
                            status: .init(request.statusTitle, tone: .danger), thumbnailURLString: request.thumbnailUrl,
                            fields: [.init("作者", request.imageAuthor ?? "-"), .init("申请原因", request.reason),
                                     .init("创建时间", SetuDateFormatter.string(from: request.createdAt))], density: .compact,
                            onTap: { router.navigate(to: .adminImageDeleteRequestDetail(request.id)) }) {
                            if request.status == 0 {
                                Button { toggleSelection(request.id) } label: {
                                    Label(selectedRequestIDs.contains(request.id) ? "取消选择" : "选择此申请",
                                          systemImage: selectedRequestIDs.contains(request.id) ? "checkmark.circle.fill" : "circle")
                                        .frame(minHeight: 44)
                                }
                                .accessibilityValue(selectedRequestIDs.contains(request.id) ? "已选择" : "未选择")
                                .buttonStyle(.borderless)
                                .disabled(isBulkReviewing)
                            }
                        }
                    }
                }
                }

                pagerSection(result)
            }
        }
    }

    private func bulkReviewSection(_ pendingItems: [ImageDeleteRequestItem]) -> some View {
        let pendingIDs = Set(pendingItems.map(\.id))
        let selectedCount = selectedRequestIDs.intersection(pendingIDs).count
        return VStack(alignment: .leading, spacing: SetuSpacing.xs) {
            Text("已选 \(selectedCount) / \(pendingItems.count)").font(SetuTypography.caption)
            Menu {
                Button(selectedCount == pendingItems.count ? "取消全选当前页" : "选择当前页待审核") {
                    if selectedCount == pendingItems.count { selectedRequestIDs.subtract(pendingIDs) }
                    else { selectedRequestIDs.formUnion(pendingIDs) }
                }
                Button("清空选择") { selectedRequestIDs.removeAll() }.disabled(selectedRequestIDs.isEmpty)
                Button("批量拒绝", role: .destructive) {
                    pendingActionTitle = "确认批量拒绝已选申请？"
                    pendingAction = { Task { await batchReview(approve: false) } }
                }.disabled(selectedCount == 0)
                Button("批量同意删除", role: .destructive) {
                    pendingActionTitle = "确认批量批准删除已选图片？"
                    pendingAction = { Task { await batchReview(approve: true) } }
                }.disabled(selectedCount == 0)
            } label: {
                Label("批量审核", systemImage: "checklist").frame(maxWidth: .infinity, minHeight: 50)
            }.disabled(isBulkReviewing)
        }
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

    @State private var pendingAction: (() -> Void)?
    @State private var pendingActionTitle = ""

    var body: some View {
        SetuBoard {
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

                }
                content
            }
        }
        .setuBackground()
        .navigationTitle("审核详情")
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
        SetuRecordCard(headline: "申请 #\(detail.id)", status: .init(detail.statusTitle, tone: .danger),
            fields: [.init("申请人", detail.userNickname.isEmpty ? detail.userEmail : detail.userNickname),
                     .init("用户 ID", "\(detail.userId)"), .init("创建时间", detail.createdAt)], density: .compact)
    }

    private func imageSection(_ detail: ImageDeleteRequestDetail) -> some View {
        SetuRecordCard(headline: "\(detail.pid)_p\(detail.p)", supporting: detail.title,
            thumbnailURLString: detail.urlOriginal,
            fields: [.init("作者", detail.author ?? "-"), .init("作者 UID", detail.uid.map(String.init) ?? "-"),
                     .init("尺寸", "\(detail.width ?? 0) × \(detail.height ?? 0)"), .init("格式", detail.ext ?? "-"),
                     .init("R18", detail.r18.map { $0 == 1 ? "是" : "否" } ?? "-"),
                     .init("标签", detail.tags?.joined(separator: " / ") ?? "-")], density: .compact)
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

    }

    private var reviewActionSection: some View {
        SetuRecordCard(headline: "审核", status: .init("请核对后操作", tone: .danger), density: .compact) {
            VStack(alignment: .leading, spacing: SetuSpacing.md) {
                SetuSectionHeader(title: "审核")
            TextField("审核备注，可选", text: $remark)
                    .textFieldStyle(.roundedBorder)
            HStack {
                Button(role: .destructive) {
                    pendingActionTitle = "确认拒绝此删除申请？"; pendingAction = { Task { await review(approve: false) } }
                } label: {
                    Label("拒绝", systemImage: "xmark.circle")
                        .frame(minHeight: 44)
                }
                .disabled(isSubmitting)

                Spacer()

                Button {
                    pendingActionTitle = "确认批准删除此图片？"; pendingAction = { Task { await review(approve: true) } }
                } label: {
                        Label(isSubmitting ? "提交中" : "批准删除", systemImage: isSubmitting ? "hourglass" : "checkmark.circle")
                            .frame(minHeight: 44)
                }
                .disabled(isSubmitting)
            }
        }
        }

    }

    private func reviewInfoSection(_ detail: ImageDeleteRequestDetail) -> some View {
        SetuRecordCard(headline: "审核信息", fields: {
                    var fields: [SetuRecordField] = []
                fields.append(.init("审核人", detail.adminEmail ?? "-"))
                fields.append(.init("审核时间", detail.reviewedAt ?? "-"))
            if let adminRemark = detail.adminRemark, !adminRemark.isEmpty {
                    fields.append(.init("备注", adminRemark))
                }
                    return fields
                }(), density: .compact)

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

private typealias AdminImageDeleteStateSection = AdminRecordStateSection
