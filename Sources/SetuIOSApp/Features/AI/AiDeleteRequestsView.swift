import SetuIOSCore
import SwiftUI

struct AiDeleteRequestsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    var showsCloseButton = false
    @State private var requests: [AiGenerationDeleteRequest] = []
    @State private var total = 0
    @State private var nextPage = 1
    @State private var isInitialLoading = true
    @State private var isLoadingMore = false
    @State private var loadError: String?
    @State private var loadRevision = 0
    @State private var statusFilter = "ALL"
    private let pageSize = 20

    var body: some View {
        List {
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "筛选")
                        adaptiveStatusPicker
                        .onChange(of: statusFilter) {
                            Task { await loadFirstPage(clearExisting: true) }
                        }
                    }
                }
                .setuListRow()
            }

            content
        }
        .listStyle(.plain)
        .setuBackground()
        .navigationTitle("AI 删除申请")
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadFirstPage() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新删除申请")
            }
        }
        .task { await loadFirstPage() }
        .refreshable { await loadFirstPage() }
    }

    @ViewBuilder
    private var adaptiveStatusPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            statusPicker.pickerStyle(.menu)
        } else {
            statusPicker.pickerStyle(.segmented)
        }
    }

    private var statusPicker: some View {
        Picker("状态", selection: $statusFilter) {
            Text("全部").tag("ALL")
            Text("待审核").tag("WAITING")
            Text("已通过").tag("APPROVED")
            Text("已拒绝").tag("REJECTED")
        }
    }

    @ViewBuilder
    private var content: some View {
        if isInitialLoading {
            AiDeleteRequestStateSection(title: "删除申请", stateTitle: "正在加载 AI 删除申请", systemImage: "xmark.bin", isLoading: true)
        } else if requests.isEmpty {
            if let loadError {
                AiDeleteRequestStateSection(
                    title: "删除申请",
                    stateTitle: "AI 删除申请加载失败",
                    message: loadError,
                    systemImage: "exclamationmark.triangle",
                    actionTitle: "重试",
                    action: { Task { await loadFirstPage() } }
                )
            } else {
                AiDeleteRequestStateSection(
                    title: "删除申请",
                    stateTitle: "暂无 AI 删除申请",
                    message: "在作品详情中提交删除申请后，会显示在这里。",
                    systemImage: "xmark.bin"
                )
            }
        } else {
            Section {
                SetuCard {
                    VStack(alignment: .leading, spacing: SetuSpacing.md) {
                        SetuSectionHeader(title: "删除申请", subtitle: "共 \(total) 条")
                        VStack(spacing: 0) {
                            ForEach(Array(requests.enumerated()), id: \.element.id) { index, request in
                                UserAiDeleteRequestRow(request: request)
                                    .onAppear {
                                        if request.id == requests.last?.id {
                                            Task { await loadMore() }
                                        }
                                    }

                                if index < requests.count - 1 {
                                    Divider().overlay(SetuColor.separator)
                                }
                            }
                        }
                    }
                }
                .setuListRow()

                SetuLoadMoreFooter(state: loadMoreFooterState) {
                    Task { await loadMore() }
                }
                .setuListRow()
            }
        }
    }

    private var hasMore: Bool {
        requests.count < total
    }

    private var loadMoreFooterState: SetuLoadMoreFooterState {
        if isLoadingMore { return .loading }
        if let loadError { return .failed(loadError) }
        if !hasMore { return .complete("已加载全部 \(total) 条删除申请") }
        return .idle
    }

    private func loadFirstPage(clearExisting: Bool = false) async {
        loadRevision += 1
        let revision = loadRevision
        let requestedFilter = statusFilter
        if clearExisting {
            requests = []
            total = 0
            nextPage = 1
        }
        isInitialLoading = requests.isEmpty
        isLoadingMore = false
        loadError = nil
        do {
            let result = try await environment.aiGenerationClient.deleteRequests(
                status: requestedFilter,
                page: 1,
                pageSize: pageSize
            )
            guard revision == loadRevision, requestedFilter == statusFilter else { return }
            requests = result.list
            total = result.total
            nextPage = 2
        } catch {
            guard revision == loadRevision, requestedFilter == statusFilter else { return }
            loadError = UserFacingErrorMapper.map(error).message
        }
        guard revision == loadRevision, requestedFilter == statusFilter else { return }
        isInitialLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, !isInitialLoading else { return }
        let revision = loadRevision
        let requestedFilter = statusFilter
        let requestedPage = nextPage
        isLoadingMore = true
        loadError = nil
        defer {
            if revision == loadRevision {
                isLoadingMore = false
            }
        }
        do {
            let result = try await environment.aiGenerationClient.deleteRequests(
                status: requestedFilter,
                page: requestedPage,
                pageSize: pageSize
            )
            guard revision == loadRevision, requestedFilter == statusFilter, requestedPage == nextPage else { return }
            let existingIDs = Set(requests.map(\.id))
            requests.append(contentsOf: result.list.filter { !existingIDs.contains($0.id) })
            total = result.total
            nextPage += 1
        } catch {
            guard revision == loadRevision, requestedFilter == statusFilter else { return }
            loadError = UserFacingErrorMapper.map(error).message
        }
    }
}

private struct AiDeleteRequestStateSection: View {
    let title: String
    let stateTitle: String
    var message: String?
    var systemImage: String
    var isLoading = false
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        Section {
            SetuCard {
                VStack(alignment: .leading, spacing: SetuSpacing.md) {
                    SetuSectionHeader(title: title)
                    SetuEmptyState(
                        title: stateTitle,
                        message: message,
                        systemImage: systemImage,
                        isLoading: isLoading,
                        actionTitle: actionTitle,
                        action: action
                    )
                }
            }
            .setuListRow()
        }
    }
}

private struct UserAiDeleteRequestRow: View {
    let request: AiGenerationDeleteRequest

    var body: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.md) {
            HStack(alignment: .top, spacing: SetuSpacing.md) {
                AiDeleteRequestThumbnail(urlString: request.job?.imageUrl, status: request.job?.statusTitle)
                VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                    Text(request.job?.promptCn ?? "删除申请")
                        .font(SetuTypography.headline)
                        .foregroundStyle(SetuColor.textPrimary)
                    Text("图片删除申请")
                        .font(SetuTypography.caption)
                        .foregroundStyle(SetuColor.textSecondary)
                    HStack(spacing: 8) {
                        StatusBadge(title: request.statusTitle, status: request.status)
                        if let createdAt = request.createdAt {
                            Label(SetuDateFormatter.string(from: createdAt), systemImage: "calendar")
                                .font(SetuTypography.caption)
                                .foregroundStyle(SetuColor.textSecondary)
                        }
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
            if let reviewedAt = request.reviewedAt {
                Label("审核时间：\(SetuDateFormatter.string(from: reviewedAt))", systemImage: "checkmark.seal")
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            }
        }
        .padding(.vertical, SetuSpacing.sm)
    }
}

private struct AiDeleteRequestThumbnail: View {
    let urlString: String?
    let status: String?

    var body: some View {
        Group {
            if let urlString, URL(string: urlString) != nil {
                SetuRemoteImage(
                    urlString: urlString,
                    accessibilityLabel: "AI 作品删除申请缩略图",
                    width: 72,
                    height: 72,
                    cornerRadius: SetuRadius.sm
                )
            } else {
                placeholder
            }
        }
        .frame(width: 72, height: 72)
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
