import SetuIOSCore
import SwiftUI

struct AiDeleteRequestsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    @State private var pager = PagingController<AiGenerationDeleteRequest>(pageSize: 20)
    private var requests: [AiGenerationDeleteRequest] {
        get { pager.items }
        nonmutating set { pager.replaceItems(newValue) }
    }
    private var total: Int { pager.total }
    private var isInitialLoading: Bool { pager.phase == .loadingInitial || (!pager.hasLoadedFirstPage && pager.initialError == nil) }
    private var isLoadingMore: Bool { pager.phase == .loadingMore }
    private var initialError: UserFacingError? { pager.initialError }
    private var loadMoreError: UserFacingError? { pager.loadMoreError }
    private var loadError: UserFacingError? { pager.loadMoreError ?? pager.initialError }

    var showsCloseButton = false
    @State private var statusFilter = "ALL"
    private let pageSize = 20

    var body: some View {
        SetuBoard {
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

            }

            content
        }

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
        SetuFilterBar(
            options: [
                .init(value: "ALL", title: "全部"), .init(value: "WAITING", title: "待审核"), .init(value: "APPROVED", title: "已通过"),
                .init(value: "REJECTED", title: "已拒绝"),
            ], selection: $statusFilter)
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

                SetuSectionHeader(title: "删除申请", subtitle: "共 \(total) 条")
                SetuRecordBoard(items: requests) { request in
                    UserAiDeleteRequestRow(request: request)
                        .onAppear {
                            if request.id == requests.last?.id {
                                Task { await loadMore() }
                            }
                        }
                }

                SetuLoadMoreFooter(state: loadMoreFooterState) {
                    Task { await loadMore() }
                }

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
        let filter = statusFilter
        await pager.loadFirstPage(clearExisting: clearExisting) { page in
            let result = try await environment.aiGenerationClient.deleteRequests(status: filter, page: page, pageSize: pageSize)
            return .init(items: result.list, total: result.total)
        }
    }

    private func loadMore() async {
        let filter = statusFilter
        await pager.loadMore { page in
            let result = try await environment.aiGenerationClient.deleteRequests(status: filter, page: page, pageSize: pageSize)
            return .init(items: result.list, total: result.total)
        }
    }
}

private typealias AiDeleteRequestStateSection = SetuStateSection

private struct UserAiDeleteRequestRow: View {
    let request: AiGenerationDeleteRequest

    var body: some View {
        SetuRecordCard(
            headline: request.job?.promptCn ?? "删除申请", supporting: request.reason,
            status: .init(
                request.statusTitle, tone: request.status == "WAITING" ? .warning : request.status == "APPROVED" ? .success : .danger),
            thumbnailURLString: request.job?.imageUrl,
            fields: [
                .init("创建时间", request.createdAt.map { SetuDateFormatter.string(from: $0) } ?? "暂无", isNumeric: false),
                .init("审核时间", request.reviewedAt.map { SetuDateFormatter.string(from: $0) } ?? "尚未审核", isNumeric: false),
                .init("拒绝原因", request.rejectReason ?? "无", isNumeric: false),
            ])
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
