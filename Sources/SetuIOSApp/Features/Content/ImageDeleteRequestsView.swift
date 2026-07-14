import SetuIOSCore
import SwiftUI

struct ImageDeleteRequestsView: View {
    @Environment(RouterPath.self) private var router
    @Bindable var environment: AppEnvironment
    @State private var requests: [ImageDeleteRequestItem] = []
    @State private var total = 0
    @State private var nextPage = 1
    @State private var isInitialLoading = true
    @State private var isLoadingMore = false
    @State private var loadError: String?
    @State private var loadRevision = 0
    private let pageSize = 10

    var body: some View {
        List {
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
                    SetuCard {
                        VStack(alignment: .leading, spacing: SetuSpacing.md) {
                            SetuSectionHeader(title: "删除申请", subtitle: "共 \(total) 条")
                            VStack(spacing: 0) {
                                ForEach(Array(requests.enumerated()), id: \.element.id) { index, request in
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
        .listStyle(.plain)
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
        loadRevision += 1
        let revision = loadRevision
        isInitialLoading = requests.isEmpty
        isLoadingMore = false
        loadError = nil
        do {
            let result = try await environment.imageDeleteRequestClient.listMine(page: 1, pageSize: pageSize)
            guard revision == loadRevision else { return }
            requests = result.list
            total = result.total
            nextPage = 2
        } catch {
            guard revision == loadRevision else { return }
            loadError = UserFacingErrorMapper.map(error).message
        }
        guard revision == loadRevision else { return }
        isInitialLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, !isInitialLoading else { return }
        let revision = loadRevision
        let requestedPage = nextPage
        isLoadingMore = true
        loadError = nil
        defer {
            if revision == loadRevision {
                isLoadingMore = false
            }
        }
        do {
            let result = try await environment.imageDeleteRequestClient.listMine(page: requestedPage, pageSize: pageSize)
            guard revision == loadRevision, requestedPage == nextPage else { return }
            let existingIDs = Set(requests.map(\.id))
            requests.append(contentsOf: result.list.filter { !existingIDs.contains($0.id) })
            total = result.total
            nextPage += 1
        } catch {
            guard revision == loadRevision else { return }
            loadError = UserFacingErrorMapper.map(error).message
        }
    }
}

struct ImageDeleteStateSection: View {
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

struct ImageDeleteRequestRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let request: ImageDeleteRequestItem

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                    HStack(alignment: .top, spacing: SetuSpacing.md) {
                        thumbnail
                        titleText
                    }
                    RequestStatusBadge(title: request.statusTitle, status: request.status)
                    requestDetails
                }
            } else {
                HStack(alignment: .top, spacing: SetuSpacing.md) {
                    thumbnail
                    VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                        HStack(alignment: .top) {
                            titleText
                            Spacer()
                            RequestStatusBadge(title: request.statusTitle, status: request.status)
                        }
                        requestDetails
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SetuColor.textTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, SetuSpacing.sm)
        .contentShape(Rectangle())
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
