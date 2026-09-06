import SetuIOSCore
import SwiftUI

struct ImageDeleteRequestsView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var pager = PagingController<ImageDeleteRequestItem>(pageSize: 10)
    private var requests: [ImageDeleteRequestItem] {
        get { pager.items }
        nonmutating set { pager.replaceItems(newValue) }
    }
    private var total: Int { pager.total }
    private var isInitialLoading: Bool { pager.phase == .loadingInitial || (!pager.hasLoadedFirstPage && pager.initialError == nil) }
    private var isLoadingMore: Bool { pager.phase == .loadingMore }
    private var initialError: UserFacingError? { pager.initialError }
    private var loadMoreError: UserFacingError? { pager.loadMoreError }
    private var loadError: UserFacingError? { pager.loadMoreError ?? pager.initialError }

    private let pageSize = 10

    var body: some View {
        SetuBoard {
            if isInitialLoading {
                ImageDeleteStateSection(title: "删除申请", stateTitle: "正在加载删除申请", systemImage: "trash", isLoading: true)
            } else if requests.isEmpty {
                if let loadError {
                    ImageDeleteStateSection(
                        title: "删除申请",
                        stateTitle: "删除申请加载失败",
                        message: loadError,
                        systemImage: "trash.slash",
                        actionTitle: "重试",
                        action: { Task { await loadFirstPage() } }
                    )
                } else {
                    ImageDeleteStateSection(title: "删除申请", stateTitle: "暂无删除申请", message: "你提交过的图片删除申请会显示在这里。", systemImage: "trash")
                }
            } else {
                Section {

                    SetuSectionHeader(title: "删除申请", subtitle: "共 \(total) 条")
                    SetuRecordBoard(items: requests) { request in
                        Button {
                            router.navigate(to: .imageDeleteRequestDetail(request.id))
                        } label: {
                            ImageDeleteRequestRow(request: request)
                        }
                        .buttonStyle(.plain)
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

        .setuBackground()
        .navigationTitle("我的删除申请")
        .task { await loadFirstPage() }
        .refreshable { await loadFirstPage() }
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

    private func loadFirstPage() async {
        await pager.loadFirstPage(clearExisting: false) { page in
            let result = try await environment.imageDeleteRequestClient.listMine(page: page, pageSize: pageSize)
            return .init(items: result.list, total: result.total)
        }
    }

    private func loadMore() async {
        await pager.loadMore { page in
            let result = try await environment.imageDeleteRequestClient.listMine(page: page, pageSize: pageSize)
            return .init(items: result.list, total: result.total)
        }
    }
}

typealias ImageDeleteStateSection = SetuStateSection

struct ImageDeleteRequestRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let request: ImageDeleteRequestItem

    var body: some View {
        SetuRecordCard(
            headline: request.imageTitle ?? "未命名作品", supporting: request.reason,
            status: .init(request.statusTitle, tone: request.status == 0 ? .warning : request.status == 1 ? .success : .danger),
            thumbnailURLString: request.thumbnailUrl,
            fields: [
                .init("作者", request.imageAuthor ?? "未知作者", isNumeric: false),
                .init("申请时间", SetuDateFormatter.string(from: request.createdAt), isNumeric: false),
            ])
    }

    private var thumbnail: some View {
        SetuRemoteImage(
            urlString: request.thumbnailUrl,
            accessibilityLabel: "待处理图片：\(request.imageTitle ?? "未命名作品")",
            allowsTapToRetry: false
        )
    }

    private var titleText: some View {
        Text(request.imageTitle ?? "未命名作品")
            .font(SetuTypography.headline)
            .foregroundStyle(SetuColor.textPrimary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var requestDetails: some View {
        VStack(alignment: .leading, spacing: SetuSpacing.xs) {
            if let author = request.imageAuthor, !author.isEmpty {
                Text(author)
                    .font(SetuTypography.caption)
                    .foregroundStyle(SetuColor.textSecondary)
            }
            Text(request.reason)
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
            Label(SetuDateFormatter.string(from: request.createdAt), systemImage: "calendar")
                .font(SetuTypography.caption)
                .foregroundStyle(SetuColor.textTertiary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct RequestStatusBadge: View {
    let title: String
    let status: Int

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case 0:
            return SetuColor.warning
        case 1:
            return SetuColor.success
        case 2:
            return SetuColor.danger
        default:
            return SetuColor.textSecondary
        }
    }
}
