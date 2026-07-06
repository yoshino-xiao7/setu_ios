import SetuIOSCore
import SwiftUI

struct AdminImageAuditView: View {
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
        List {
            if environment.authSession.currentUser?.role != .admin {
                ContentUnavailableView("需要管理员权限", systemImage: "shield.slash", description: Text("请使用管理员账号登录后管理图片库。"))
            } else {
                filterSection
                statsSection
                bulkSection
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
        .navigationTitle("图片库管理")
        .sheet(item: $reasonDraft) { draft in
            ImageAuditReasonSheet(draft: draft, isSubmitting: isSubmitting) { reason in
                Task { await submitReasonAction(draft, reason: reason) }
            }
        }
        .task { await load(resetPage: true) }
        .refreshable { await load(resetPage: false) }
    }

    private var filterSection: some View {
        Section("筛选") {
            Picker("范围", selection: $scope) {
                Text("未审核").tag("UNREVIEWED")
                Text("到期复审").tag("DUE_REVIEW")
                Text("全部").tag("ALL")
            }
            TextField("PID", text: $pidText)
            TextField("p", text: $pText)
            if scope == "DUE_REVIEW" {
                TextField("复审天数", text: $staleDaysText)
            }
            Picker("可用性", selection: $availabilityStatus) {
                Text("全部").tag("ALL")
                Text("未知").tag("UNKNOWN")
                Text("可用").tag("OK")
                Text("疑似失效").tag("SUSPECTED_BROKEN")
                Text("已失效").tag("BROKEN")
            }
            Toggle("只看失效", isOn: $onlyBroken)
            HStack {
                Button {
                    Task { await load(resetPage: true) }
                } label: {
                    Label("查询", systemImage: "magnifyingglass")
                }
                Spacer()
                Button("重置") {
                    resetFilters()
                    Task { await load(resetPage: true) }
                }
            }
        }
    }

    @ViewBuilder
    private var statsSection: some View {
        if case .loaded(let result) = state {
            Section("统计") {
                if let stats = result.stats {
                    LabeledContent("未审核", value: "\(stats.unreviewed)")
                    LabeledContent("到期复审", value: "\(stats.dueReview)")
                    LabeledContent("全部图片", value: "\(stats.all)")
                }
                if let dueBefore = result.dueBefore, scope == "DUE_REVIEW" {
                    LabeledContent("复审截止", value: dueBefore)
                }
            }
        }
    }

    @ViewBuilder
    private var bulkSection: some View {
        if isAuditScope, case .loaded(let result) = state, !result.list.isEmpty {
            Section("批量审核") {
                LabeledContent("已选", value: "\(selectedImageIDs.count) / \(result.list.count)")
                HStack {
                    Button(selectedImageIDs.count == result.list.count ? "取消全选" : "选择当前页") {
                        toggleCurrentPage(result.list)
                    }
                    Spacer()
                    Button("清空") {
                        selectedImageIDs.removeAll()
                    }
                    .disabled(selectedImageIDs.isEmpty)
                }
                Button {
                    Task { await checkAvailability(Array(selectedImageIDs)) }
                } label: {
                    Label("检测已选", systemImage: "checkmark.shield")
                }
                .disabled(selectedImageIDs.isEmpty || isSubmitting)
                HStack {
                    Button {
                        Task { await submitBatch(status: 1, remark: nil) }
                    } label: {
                        Label("批量正常", systemImage: "checkmark.circle")
                    }
                    .disabled(selectedImageIDs.isEmpty || isSubmitting)
                    Spacer()
                    Button(role: .destructive) {
                        reasonDraft = ImageAuditReasonDraft(kind: .batchProblem, image: nil, imageIDs: Array(selectedImageIDs))
                    } label: {
                        Label("批量问题", systemImage: "xmark.circle")
                    }
                    .disabled(selectedImageIDs.isEmpty || isSubmitting)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            ProgressView("正在加载图片库")
        case .failed(let message):
            ContentUnavailableView("图片库加载失败", systemImage: "photo.badge.exclamationmark", description: Text(message))
        case .loaded(let result):
            if result.list.isEmpty {
                ContentUnavailableView("暂无图片", systemImage: "photo.stack", description: Text("当前筛选条件下没有图片。"))
            } else {
                Section("共 \(result.total) 张") {
                    ForEach(result.list) { image in
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
                        }
                        .disabled(isSubmitting)
                    }
                }
                pagerSection(result)
            }
        }
    }

    private func pagerSection(_ result: ImageAuditPageResult) -> some View {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if isAuditScope {
                    Button {
                        onToggleSelection()
                    } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? .pink : .secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                }
                ImageAuditThumbnail(urlString: image.urlOriginal)
                VStack(alignment: .leading, spacing: 6) {
                    Text(image.pidText)
                        .font(.headline)
                    Text(image.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(2)
                    Text("作者：\(image.author)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    badgeRow
                    Text("\(image.width)x\(image.height) · \(image.ext) · UID \(image.uid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let detail = availabilityDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let remark = image.lastAuditRemark, !remark.isEmpty {
                Text("审核备注：\(remark)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let admin = image.lastAuditAdminEmail, let time = image.lastAuditTime {
                Text("最近审核：\(admin) · \(time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            actionRow
        }
        .padding(.vertical, 4)
    }

    private var badgeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text(image.ratingTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((image.r18 == 1 ? Color.red : Color.green).opacity(0.14), in: Capsule())
                    .foregroundStyle(image.r18 == 1 ? .red : .green)
                if image.aiType == 2 {
                    Text("AI")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.16), in: Capsule())
                        .foregroundStyle(.orange)
                }
                RequestStatusBadge(title: image.availabilityTitle, status: availabilityStatusCode)
                RequestStatusBadge(title: image.auditStatusTitle, status: auditStatusCode)
            }
        }
    }

    private var actionRow: some View {
        HStack {
            if let url = URL(string: image.urlOriginal) {
                Link(destination: url) {
                    Label("查看", systemImage: "eye")
                }
            }
            Button {
                onCheckAvailability()
            } label: {
                Label("检测", systemImage: "checkmark.shield")
            }
            Spacer()
            if isAuditScope {
                Button {
                    onPass()
                } label: {
                    Label("正常", systemImage: "checkmark.circle")
                }
                Button(role: .destructive) {
                    onProblem()
                } label: {
                    Label("问题", systemImage: "xmark.circle")
                }
            } else {
                Button(role: .destructive) {
                    onDeleteRequest()
                } label: {
                    Label("申请删除", systemImage: "trash")
                }
            }
        }
        .buttonStyle(.borderless)
        .font(.footnote)
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

private struct ImageAuditThumbnail: View {
    let urlString: String

    var body: some View {
        Group {
            if let url = URL(string: urlString) {
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
        Image(systemName: "photo")
            .foregroundStyle(.pink)
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
            Form {
                Section(draft.kind.sectionTitle) {
                    TextField(draft.kind.placeholder, text: $reason, axis: .vertical)
                        .lineLimit(4...7)
                }
                if let image = draft.image {
                    Section("图片") {
                        LabeledContent("PID", value: image.pidText)
                        LabeledContent("标题", value: image.title)
                    }
                } else {
                    Section("批量") {
                        LabeledContent("图片数", value: "\(draft.imageIDs.count)")
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
                    .disabled(isSubmitting || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

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
