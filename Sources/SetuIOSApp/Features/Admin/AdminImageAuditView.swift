import SetuIOSCore
import SwiftUI

struct AdminImageAuditView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var state: LoadState<ImageAuditPageResult> = .idle
    @State private var scope = "UNREVIEWED"
    @State private var pidText = ""
    @State private var pText = ""
    @State private var staleDaysText = "30"
    @State private var availabilityStatus = "ALL"
    @State private var onlyBroken = false
    @State private var page = 1
    @State private var selectedImageIDs = Set<Int>()
    @State private var reasonDraft: ImageAuditReasonDraft?
    @State private var message: String?
    @State private var isSubmitting = false
    private let pageSize = 12

    var body: some View {
        SetuBoard {
            if environment.authSession.currentUser?.role != .admin {
                AdminImageAuditStateSection(title: "权限", stateTitle: "需要管理员权限", message: "请使用管理员账号登录后管理图片库。", systemImage: "shield.slash")
            } else {
                filterSection
                statsSection
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
        .navigationTitle("图片库管理")
        .setuActionDock { if environment.authSession.currentUser?.role == .admin { bulkSection } }
        .sheet(item: $reasonDraft) { draft in
            ImageAuditReasonSheet(draft: draft, isSubmitting: isSubmitting) { reason in
                Task { await submitReasonAction(draft, reason: reason) }
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
                    .init(value: "UNREVIEWED", title: "未审核"),
                    .init(value: "DUE_REVIEW", title: "到期复审"),
                    .init(value: "ALL", title: "全部")
                ], selection: $scope, accessibilityTitle: "范围")

                TextField("PID", text: $pidText)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                TextField("p", text: $pText)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                if scope == "DUE_REVIEW" {
                    TextField("复审天数", text: $staleDaysText)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                SetuFilterBar(options: [
                    .init(value: "ALL", title: "全部"),
                    .init(value: "UNKNOWN", title: "未知"),
                    .init(value: "OK", title: "可用"),
                    .init(value: "SUSPECTED_BROKEN", title: "疑似失效"),
                    .init(value: "BROKEN", title: "已失效")
                ], selection: $availabilityStatus, accessibilityTitle: "可用性")
                Toggle("只看失效", isOn: $onlyBroken)
                HStack {
                    Button {
                        Task { await load(resetPage: true) }
                    } label: {
                        Label("查询", systemImage: "magnifyingglass")
                            .frame(minHeight: 44)
                    }
                    Spacer()
                    Button("重置") {
                        resetFilters()
                        Task { await load(resetPage: true) }
                    }
                    .frame(minHeight: 44)
                }
            }
        }

    }

    @ViewBuilder
    private var statsSection: some View {
        if case .loaded(let result) = state {
            SetuRecordCard(headline: "统计", fields: {
                    var fields: [SetuRecordField] = []
                if let stats = result.stats {
                        fields.append(.init("未审核", "\(stats.unreviewed)"))
                        fields.append(.init("到期复审", "\(stats.dueReview)"))
                        fields.append(.init("全部图片", "\(stats.all)"))
                }
                if let dueBefore = result.dueBefore, scope == "DUE_REVIEW" {
                        fields.append(.init("复审截止", dueBefore))
                    }

                    return fields
                }(), density: .compact)

        }
    }

    @ViewBuilder
    private var bulkSection: some View {
        if isAuditScope, case .loaded(let result) = state, !result.list.isEmpty {
            VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                Text("已选 \(selectedImageIDs.count) / \(result.list.count)").font(SetuTypography.caption)
                Menu {
                    Button(selectedImageIDs.count == result.list.count ? "取消全选" : "选择当前页") { toggleCurrentPage(result.list) }
                    Button("清空选择") { selectedImageIDs.removeAll() }.disabled(selectedImageIDs.isEmpty)
                    Button("检测已选") { Task { await checkAvailability(Array(selectedImageIDs)) } }.disabled(selectedImageIDs.isEmpty)
                    Button("批量正常") { Task { await submitBatch(status: 1, remark: nil) } }.disabled(selectedImageIDs.isEmpty)
                    Button("批量问题", role: .destructive) {
                        reasonDraft = ImageAuditReasonDraft(kind: .batchProblem, image: nil, imageIDs: Array(selectedImageIDs))
                    }.disabled(selectedImageIDs.isEmpty)
                } label: {
                    Label("批量审核", systemImage: "checklist").frame(maxWidth: .infinity, minHeight: 50)
                }.disabled(isSubmitting)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            AdminImageAuditStateSection(title: "图片库", stateTitle: "正在加载图片库", systemImage: "photo.stack", isLoading: true)
        case .failed(let message):
            AdminImageAuditStateSection(title: "图片库", stateTitle: "图片库加载失败", message: message, systemImage: "photo.badge.exclamationmark")
        case .loaded(let result):
            if result.list.isEmpty {
                AdminImageAuditStateSection(title: "图片库", stateTitle: "暂无图片", message: "当前筛选条件下没有图片。", systemImage: "photo.stack")
            } else {
                Group {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "共 \(result.total) 张", subtitle: "图片库")
                    SetuRecordBoard(items: result.list) { image in
                        ImageAuditRow(
                            image: image,
                            isAuditScope: isAuditScope,
                            isSelected: selectedImageIDs.contains(image.id)
                        ) {
                            toggleSelection(image.id)
                        } onPass: {
                            Task { await submitSingle(image, status: 1, remark: nil) }
                        } onProblem: {
                            reasonDraft = ImageAuditReasonDraft(kind: .singleProblem, image: image, imageIDs: [image.id])
                        } onDeleteRequest: {
                            reasonDraft = ImageAuditReasonDraft(kind: .deleteRequest, image: image, imageIDs: [image.id])
                        } onCheckAvailability: {
                            Task { await checkAvailability([image.id]) }
                        } onDetail: {
                            router.navigate(to: .adminImageDetail(image.pid, image.p))
                        }
                        .disabled(isSubmitting)
                    }
                }
                }

                pagerSection(result)
            }
        }
    }

    private func pagerSection(_ result: ImageAuditPageResult) -> some View {
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

    private var isAuditScope: Bool {
        scope != "ALL"
    }

    private func load(resetPage: Bool) async {
        guard environment.authSession.currentUser?.role == .admin else { return }
        if resetPage {
            page = 1
            selectedImageIDs.removeAll()
        }
        state = .loading
        do {
            state = .loaded(try await environment.adminClient.imageAuditList(
                page: page,
                pageSize: pageSize,
                scope: scope,
                pid: Int(pidText.trimmingCharacters(in: .whitespacesAndNewlines)),
                p: Int(pText.trimmingCharacters(in: .whitespacesAndNewlines)),
                staleDays: scope == "DUE_REVIEW" ? Int(staleDaysText.trimmingCharacters(in: .whitespacesAndNewlines)) : nil,
                availabilityStatus: availabilityStatus == "ALL" ? nil : availabilityStatus,
                onlyBroken: onlyBroken ? true : nil
            ))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func resetFilters() {
        scope = "UNREVIEWED"
        pidText = ""
        pText = ""
        staleDaysText = "30"
        availabilityStatus = "ALL"
        onlyBroken = false
        selectedImageIDs.removeAll()
    }

    private func toggleSelection(_ id: Int) {
        if selectedImageIDs.contains(id) {
            selectedImageIDs.remove(id)
        } else {
            selectedImageIDs.insert(id)
        }
    }

    private func toggleCurrentPage(_ images: [ImageAuditItem]) {
        let ids = Set(images.map(\.id))
        if ids.isSubset(of: selectedImageIDs), !ids.isEmpty {
            selectedImageIDs.subtract(ids)
        } else {
            selectedImageIDs.formUnion(ids)
        }
    }

    private func submitSingle(_ image: ImageAuditItem, status: Int, remark: String?) async {
        isSubmitting = true
        message = nil
        do {
            try await environment.adminClient.submitImageAudit(imageID: image.id, status: status, remark: remark)
            selectedImageIDs.remove(image.id)
            message = status == 1 ? "已标记 \(image.pidText) 正常" : "已标记 \(image.pidText) 有问题"
            await load(resetPage: false)
        } catch {
            message = error.localizedDescription
        }
        isSubmitting = false
    }

    private func submitBatch(status: Int, remark: String?) async {
        let ids = Array(selectedImageIDs)
        guard !ids.isEmpty else { return }
        isSubmitting = true
        message = nil
        do {
            let result = try await environment.adminClient.submitImageAuditBatch(imageIDs: ids, status: status, remark: remark)
            message = "批量审核完成：成功 \(result.successCount)，失败 \(result.failureCount)"
            selectedImageIDs.removeAll()
            reasonDraft = nil
            await load(resetPage: false)
        } catch {
            message = error.localizedDescription
        }
        isSubmitting = false
    }

    private func checkAvailability(_ ids: [Int]) async {
        guard !ids.isEmpty else { return }
        isSubmitting = true
        message = nil
        do {
            let result = try await environment.adminClient.checkImageAvailability(imageIDs: ids)
            message = "可用性检测完成：成功 \(result.successCount)，失败 \(result.failureCount)"
            await load(resetPage: false)
        } catch {
            message = error.localizedDescription
        }
        isSubmitting = false
    }

    private func submitReasonAction(_ draft: ImageAuditReasonDraft, reason: String) async {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        switch draft.kind {
        case .singleProblem:
            guard let image = draft.image, !trimmed.isEmpty else {
                message = "请填写问题描述"
                return
            }
            await submitSingle(image, status: 2, remark: trimmed)
            reasonDraft = nil
        case .batchProblem:
            guard !trimmed.isEmpty else {
                message = "请填写批量问题描述"
                return
            }
            await submitBatch(status: 2, remark: trimmed)
        case .deleteRequest:
            guard let image = draft.image, !trimmed.isEmpty else {
                message = "请填写删除原因"
                return
            }
            await submitDeleteRequest(image, reason: trimmed)
        }
    }

    private func submitDeleteRequest(_ image: ImageAuditItem, reason: String) async {
        isSubmitting = true
        message = nil
        do {
            try await environment.imageDeleteRequestClient.submit(pid: image.pid, p: image.p, reason: reason)
            message = "已提交 \(image.pidText) 的删除申请"
            reasonDraft = nil
        } catch {
            message = error.localizedDescription
        }
        isSubmitting = false
    }
}

private struct ImageAuditRow: View {
    let image: ImageAuditItem
    let isAuditScope: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onPass: () -> Void
    let onProblem: () -> Void
    let onDeleteRequest: () -> Void
    let onCheckAvailability: () -> Void
    let onDetail: () -> Void

    var body: some View {
        SetuRecordCard(headline: image.pidText, supporting: image.title,
            status: .init(image.auditStatusTitle, tone: image.lastAuditStatus == 2 ? .danger : .brand),
            thumbnailURLString: image.urlOriginal,
            fields: [.init("作者", image.author), .init("尺寸", "\(image.width) × \(image.height)"),
                     .init("格式", image.ext), .init("UID", "\(image.uid)"),
                     .init("可用性", availabilityDetail ?? image.availabilityTitle),
                     .init("审核备注", image.lastAuditRemark ?? "-"),
                     .init("审核人", image.lastAuditAdminEmail ?? "-"), .init("审核时间", image.lastAuditTime ?? "-")], density: .compact) {
            badgeRow
            if isAuditScope {
                Button(action: onToggleSelection) {
                    Label(isSelected ? "取消选择" : "选择", systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                        .frame(minHeight: 44)
                }.buttonStyle(.borderless)
            }
            actionRow
        }
    }

    private var badgeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SetuPill(
                    text: image.ratingTitle,
                    systemImage: image.r18 == 1 ? "exclamationmark.triangle" : "checkmark.seal",
                    tone: image.r18 == 1 ? .danger : .success
                )
                if image.aiType == 2 {
                    SetuPill(text: "AI", systemImage: "sparkles", tone: .warning)
                }
                RequestStatusBadge(title: image.availabilityTitle, status: availabilityStatusCode)
                RequestStatusBadge(title: image.auditStatusTitle, status: auditStatusCode)
            }
        }
    }

    private var actionRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading) {
            if let url = URL(string: image.urlOriginal) {
                Link(destination: url) {
                    Label("查看", systemImage: "eye").frame(minHeight: 44)
                }
            }
            Button {
                onDetail()
            } label: {
                Label("详情", systemImage: "info.circle").frame(minHeight: 44)
            }
            Button {
                onCheckAvailability()
            } label: {
                Label("检测", systemImage: "checkmark.shield").frame(minHeight: 44)
            }
            if isAuditScope {
                Button {
                    onPass()
                } label: {
                    Label("正常", systemImage: "checkmark.circle").frame(minHeight: 44)
                }
                Button(role: .destructive) {
                    onProblem()
                } label: {
                    Label("问题", systemImage: "xmark.circle").frame(minHeight: 44)
                }
            } else {
                Button(role: .destructive) {
                    onDeleteRequest()
                } label: {
                    Label("申请删除", systemImage: "trash").frame(minHeight: 44)
                }
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.large)
        .font(SetuTypography.caption)
    }

    private var availabilityStatusCode: Int {
        switch image.availabilityStatus {
        case "OK": 1
        case "BROKEN", "SUSPECTED_BROKEN": 2
        default: 0
        }
    }

    private var auditStatusCode: Int {
        switch image.lastAuditStatus {
        case 1: 1
        case 2: 2
        default: 0
        }
    }

    private var availabilityDetail: String? {
        if let error = image.lastAvailabilityError, !error.isEmpty {
            return error
        }
        if let status = image.lastAvailabilityHttpStatus {
            return "HTTP \(status)"
        }
        if let failCount = image.availabilityFailCount, failCount > 0 {
            return "连续失败 \(failCount) 次"
        }
        return nil
    }
}

private struct ImageAuditReasonSheet: View {
    @Environment(\.dismiss) private var dismiss
    let draft: ImageAuditReasonDraft
    let isSubmitting: Bool
    let onSubmit: (String) -> Void
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            SetuBoard {
                SetuRecordCard(headline: "操作确认", status: .init("请核对原因与目标", tone: .danger), density: .compact) {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: draft.kind.sectionTitle, subtitle: draft.kind.title)
                    TextField(draft.kind.placeholder, text: $reason, axis: .vertical)
                        .lineLimit(4...7)
                            .textFieldStyle(.roundedBorder)
                }
                }

                if let image = draft.image {
                    SetuRecordCard(headline: "图片", fields: [
                    .init("PID", image.pidText),
                    .init("标题", image.title)
                ], density: .compact)

                } else {
                    SetuRecordCard(headline: "批量", fields: [
                    .init("图片数", "\(draft.imageIDs.count)")
                ], density: .compact)

                }
            }
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
                    .disabled(isSubmitting || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private typealias AdminImageAuditStateSection = AdminRecordStateSection

private struct ImageAuditReasonDraft: Identifiable {
    let kind: ImageAuditReasonKind
    let image: ImageAuditItem?
    let imageIDs: [Int]

    var id: String {
        "\(kind.rawValue)-\(image?.id ?? imageIDs.hashValue)"
    }
}

private enum ImageAuditReasonKind: String {
    case singleProblem
    case batchProblem
    case deleteRequest

    var title: String {
        switch self {
        case .singleProblem: "标记为有问题"
        case .batchProblem: "批量标记为有问题"
        case .deleteRequest: "申请删除图片"
        }
    }

    var sectionTitle: String {
        switch self {
        case .singleProblem, .batchProblem: "问题描述"
        case .deleteRequest: "删除原因"
        }
    }

    var placeholder: String {
        switch self {
        case .singleProblem, .batchProblem: "例如：图片无法加载、内容不符、低质量等"
        case .deleteRequest: "请输入删除原因"
        }
    }

    var confirmTitle: String {
        switch self {
        case .singleProblem, .batchProblem: "确认提交"
        case .deleteRequest: "提交申请"
        }
    }
}
