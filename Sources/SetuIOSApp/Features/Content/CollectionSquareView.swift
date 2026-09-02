import SetuIOSCore
import SwiftUI

struct CollectionSquareView: View {
    @Environment(RouterPath.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var environment: AppEnvironment
    @State private var pager = PagingController<CollectionInfo>(pageSize: 20)
    private var collections: [CollectionInfo] {
        get { pager.items }
        nonmutating set { pager.replaceItems(newValue) }
    }
    private var total: Int { pager.total }
    private var isInitialLoading: Bool { pager.phase == .loadingInitial || (!pager.hasLoadedFirstPage && pager.initialError == nil) }
    private var isLoadingMore: Bool { pager.phase == .loadingMore }
    private var initialError: UserFacingError? { pager.initialError }
    private var loadMoreError: UserFacingError? { pager.loadMoreError }
    private var loadError: UserFacingError? { pager.loadMoreError ?? pager.initialError }

    @State private var sort = "hot"
    @State private var searchText = ""
    @State private var keyword = ""
    @State private var feedback: SetuFeedback?
    private let pageSize = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SetuSpacing.lg) {
                adaptiveSortPicker
                .onChange(of: sort) {
                    Task { await loadFirstPage(clearExisting: true) }
                }

                if let feedback {
                    SetuFeedbackBanner(feedback: feedback)
                }

                if let initialError, !collections.isEmpty {
                    SetuLoadMoreFooter(state: .failed(initialError)) {
                        Task { await loadFirstPage() }
                    }
                }

                if isInitialLoading {
                    SetuCard {
                        SetuEmptyState(
                            title: "正在加载收藏夹广场",
                            message: "正在整理公开收藏夹。",
                            systemImage: "globe.asia.australia",
                            isLoading: true
                        )
                    }
                } else if collections.isEmpty {
                    emptyState
                } else {
                    SetuSectionHeader(title: "公开收藏夹", subtitle: "共 \(total) 个")
                        .accessibilityIdentifier("collections.square.loaded")
                    LazyVGrid(columns: gridColumns, spacing: SetuSpacing.md) {
                        ForEach(collections) { collection in
                            CollectionSquareTile(collection: collection) {
                                router.navigate(to: .publicCollectionDetail(collection.id))
                            } onLike: {
                                Task { await like(collection) }
                            } onFavorite: {
                                Task { await favorite(collection) }
                            } onOwner: {
                                router.navigate(to: .publicUserProfile(collection.userId))
                            }
                            .onAppear {
                                if collection.id == collections.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                        }
                    }
                    SetuLoadMoreFooter(state: loadMoreFooterState) {
                        Task { await loadMore() }
                    }
                }
            }
            .padding(.horizontal, SetuSpacing.lg)
            .padding(.vertical, SetuSpacing.md)
        }
        .setuBackground()
        .setuFeedbackPresentation($feedback)
        .accessibilityIdentifier("collections.square.page")
        .navigationTitle("收藏夹广场")
        .searchable(text: $searchText, prompt: "搜索收藏夹")
        .onSubmit(of: .search) {
            Task { await submitSearch() }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty, !keyword.isEmpty {
                Task {
                    keyword = ""
                    await loadFirstPage(clearExisting: true)
                }
            }
        }
        .task { await loadFirstPage() }
        .refreshable { await loadFirstPage() }
    }

    @ViewBuilder
    private var adaptiveSortPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            sortPicker.pickerStyle(.menu)
        } else {
            sortPicker.pickerStyle(.segmented)
        }
    }

    private var sortPicker: some View {
        Picker("排序", selection: $sort) {
            Text("热门").tag("hot")
            Text("最新").tag("new")
            Text("点赞").tag("like")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if let initialError {
            SetuCard {
                VStack(spacing: SetuSpacing.md) {
                    SetuEmptyState(title: "广场加载失败", message: initialError, systemImage: "globe.asia.australia")
                    Button("重试") {
                        Task { await loadFirstPage() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else {
            SetuCard {
                SetuEmptyState(title: "暂无公开收藏夹", message: "换个关键词或排序方式再试试。", systemImage: "rectangle.stack")
            }
        }
    }

    private var gridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: 156), spacing: SetuSpacing.md)]
    }

    private var hasMore: Bool { pager.hasMore }

    private var loadMoreFooterState: SetuLoadMoreFooterState {
        if isLoadingMore { return .loading }
        if let loadMoreError { return .failed(loadMoreError) }
        if !hasMore { return .complete("已加载全部 \(total) 个收藏夹") }
        return .idle
    }

    private func loadFirstPage(clearExisting: Bool = false) async {
        let filter = sort
        let requestedKeyword = keyword
        await pager.loadFirstPage(clearExisting: clearExisting) { page in
            let result = try await environment.collectionClient.square(page: page, size: pageSize, sort: filter, keyword: requestedKeyword)
            return .init(items: result.list, total: result.total)
        }
    }

    private func loadMore() async {
        let filter = sort
        let requestedKeyword = keyword
        await pager.loadMore { page in
            let result = try await environment.collectionClient.square(page: page, size: pageSize, sort: filter, keyword: requestedKeyword)
            return .init(items: result.list, total: result.total)
        }
    }

    private func submitSearch() async {
        keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        await loadFirstPage(clearExisting: true)
    }

    private func like(_ collection: CollectionInfo) async {
        feedback = nil
        do {
            let shouldLike = collection.likedByMe != true
            try await environment.collectionClient.likeSquareCollection(id: collection.id, liked: shouldLike)
            let successMessage = shouldLike ? "已点赞" : "已取消点赞"
            let didRefresh = await refreshCollection(id: collection.id)
            feedback = didRefresh
                ? .success(successMessage)
                : .warning("\(successMessage)，最新状态稍后刷新")
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }

    private func favorite(_ collection: CollectionInfo) async {
        feedback = nil
        do {
            let shouldFavorite = collection.favoritedByMe != true
            try await environment.collectionClient.favoriteSquareCollection(id: collection.id, favorited: shouldFavorite)
            let successMessage = shouldFavorite ? "已收藏" : "已取消收藏"
            let didRefresh = await refreshCollection(id: collection.id)
            feedback = didRefresh
                ? .success(successMessage)
                : .warning("\(successMessage)，最新状态稍后刷新")
        } catch {
            feedback = .error(UserFacingErrorMapper.map(error))
        }
    }

    private func refreshCollection(id: Int) async -> Bool {
        guard let refreshed = try? await environment.collectionClient.squareDetail(id: id),
              let index = collections.firstIndex(where: { $0.id == id }) else { return false }
        collections[index] = refreshed
        return true
    }
}

private struct CollectionSquareTile: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let collection: CollectionInfo
    let onOpen: () -> Void
    let onLike: () -> Void
    let onFavorite: () -> Void
    let onOwner: () -> Void

    var body: some View {
        SetuCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 0) {
                        ContentGridImageView(
                            urlString: collection.coverUrl ?? collection.previewImages?.first?.bestURLString,
                            accessibilityLabel: collection.name
                        )

                        Text(collection.name)
                            .font(SetuTypography.headline)
                            .foregroundStyle(SetuColor.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, SetuSpacing.md)
                            .padding(.top, SetuSpacing.md)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开收藏夹：\(collection.name)")
                .accessibilityIdentifier("collections.square.tile.\(collection.id).open")

                VStack(alignment: .leading, spacing: SetuSpacing.sm) {
                    if let description = collection.description, !description.isEmpty {
                        Text(description)
                            .font(SetuTypography.caption)
                            .foregroundStyle(SetuColor.textSecondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: onOwner) {
                        Label(collection.ownerNickname ?? "匿名分享者", systemImage: "person.crop.circle")
                            .font(SetuTypography.caption)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityLabel("查看\(collection.ownerNickname ?? "匿名分享者")的主页")

                    VStack(alignment: .leading, spacing: SetuSpacing.xs) {
                        HStack {
                            Label("\(collection.itemCount ?? 0) 张", systemImage: "photo")
                            Spacer(minLength: SetuSpacing.xs)
                            Label("\(collection.shareViewCount ?? 0)", systemImage: "eye")
                        }
                        HStack {
                            Label("\(collection.likeCount ?? collection.shareLikeCount ?? 0)", systemImage: "hand.thumbsup")
                            Spacer(minLength: SetuSpacing.xs)
                            Label("\(collection.favoriteCount ?? collection.shareFavCount ?? 0)", systemImage: "star")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(SetuColor.textSecondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "共 \(collection.itemCount ?? 0) 张，浏览 \(collection.shareViewCount ?? 0) 次，点赞 \(collection.likeCount ?? collection.shareLikeCount ?? 0) 次，收藏 \(collection.favoriteCount ?? collection.shareFavCount ?? 0) 次"
                    )

                    HStack {
                        Button(action: onLike) {
                            Image(systemName: collection.likedByMe == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(collection.likedByMe == true ? "取消点赞《\(collection.name)》" : "点赞《\(collection.name)》")
                        .accessibilityValue(collection.likedByMe == true ? "已点赞" : "未点赞")

                        Spacer()

                        Button(action: onFavorite) {
                            Image(systemName: collection.favoritedByMe == true ? "star.fill" : "star")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(collection.favoritedByMe == true ? "取消收藏《\(collection.name)》" : "收藏《\(collection.name)》")
                        .accessibilityValue(collection.favoritedByMe == true ? "已收藏" : "未收藏")
                    }
                    .foregroundStyle(SetuColor.brandPink)
                }
                .padding(SetuSpacing.md)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("collections.square.tile.\(collection.id)")
    }
}

#if DEBUG
#Preview("收藏夹广场 · 375 · AX3") {
    SetuFeaturePreviewHost { environment, _ in
        CollectionSquareView(environment: environment)
    }
    .frame(width: 375, height: 812)
    .preferredColorScheme(.light)
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
